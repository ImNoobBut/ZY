"""
Sleeping Routine for Zy — Remote Admin + sync API.

Persistence: Postgres when DATABASE_URL is set, else SQLite (backend/data/app.db).
Run locally:  pip install -r requirements.txt && python main.py
Dashboard: http://127.0.0.1:8081/
"""

from __future__ import annotations

import os
import secrets
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import bcrypt
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session
import uvicorn

from db import (
    Account,
    AdminCommand,
    AdminToken,
    Device,
    DeviceStatusRow,
    SyncEntity,
    get_db,
    init_db,
    utcnow,
)

APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
TOKEN_TTL_SECONDS = 3600
ADMIN_TOKEN_TTL_SECONDS = TOKEN_TTL_SECONDS * 24
PAIRING_RATE_LIMIT = 20
AUTH_RATE_LIMIT = 15
RATE_WINDOW_SECONDS = 60.0

app = FastAPI(title="Sleeping Routine for Zy — Admin + Sync API", version="0.9.1")

# ip_or_key -> recent attempt timestamps (in-memory; resets on process restart)
_rate_buckets: dict[str, list[float]] = {}


def _client_key(request: Request, suffix: str) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        ip = forwarded.split(",")[0].strip()
    else:
        ip = request.client.host if request.client else "unknown"
    return f"{ip}:{suffix}"


def _rate_limit(key: str, *, limit: int, window: float = RATE_WINDOW_SECONDS) -> None:
    now = time.time()
    bucket = _rate_buckets.setdefault(key, [])
    bucket[:] = [t for t in bucket if now - t < window]
    if len(bucket) >= limit:
        raise HTTPException(status_code=429, detail="Too many attempts — try again shortly")
    bucket.append(now)


def _cors_origins() -> list[str]:
    raw = (os.environ.get("CORS_ORIGINS") or "").strip()
    if not raw:
        return []
    return [o.strip() for o in raw.split(",") if o.strip()]


_extra_origins = _cors_origins()
app.add_middleware(
    CORSMiddleware,
    allow_origins=_extra_origins,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?|https://.*\.pages\.dev",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Pydantic models ---


class DeviceStatus(BaseModel):
    batteryLevel: float | None = None
    isCharging: bool | None = None
    routineActive: bool
    routineStartedAt: datetime | None = None
    sleepTimerEndsAt: datetime | None = None
    spotifyConnected: bool
    alarmEnabled: bool
    nextAlarm: datetime | None = None
    isPlayingOwnAudio: bool
    lastCheckIn: datetime
    preferredBedtime: str | None = None
    currentStreak: int | None = None


class RegisterBody(BaseModel):
    displayName: str = "Zy iPhone"


class CheckInBody(BaseModel):
    deviceStatus: DeviceStatus


class RefreshBody(BaseModel):
    refreshToken: str


class PairBody(BaseModel):
    pairingCode: str


class JoinAccountBody(BaseModel):
    pairingCode: str
    displayName: str = "Zy linked device"


class AuthRegisterBody(BaseModel):
    email: str
    password: str = Field(min_length=8, max_length=72)
    displayName: str = Field(min_length=1, max_length=120)
    deviceDisplayName: str = "Zy device"


class AuthLoginBody(BaseModel):
    email: str
    password: str = Field(min_length=1, max_length=72)
    deviceDisplayName: str = "Zy device"


class AuthMePatchBody(BaseModel):
    displayName: str = Field(min_length=1, max_length=120)


class SyncMutation(BaseModel):
    entityType: str = Field(description="preferences | alarm | session | routine")
    entityId: str
    payload: dict[str, Any] = Field(default_factory=dict)
    updatedAt: datetime
    deleted: bool = False


class SyncPushBody(BaseModel):
    mutations: list[SyncMutation]


class AdminCommandBody(BaseModel):
    type: str
    payload: dict[str, Any] = Field(default_factory=dict)


class AckCommandsBody(BaseModel):
    ids: list[str]


ALLOWED_ENTITY_TYPES = frozenset({"preferences", "alarm", "session", "routine"})
ALLOWED_ADMIN_COMMANDS = frozenset(
    {
        "setAlarmEnabled",
        "setBedtime",
        "setWakeTime",
        "startRoutine",
        "endRoutine",
        "stopAudio",
        "startQuietAudio",
        "extendSleepTimer",
    }
)


def _normalize_email(raw: str) -> str:
    return raw.strip().lower()


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


def _normalize_pairing_code(raw: str) -> str:
    digits = "".join(ch for ch in raw.strip() if ch.isdigit())
    if not digits:
        return raw.strip()
    if len(digits) > 6:
        return digits[-6:]
    return digits.zfill(6)


def _new_pairing_code(db: Session) -> str:
    for _ in range(40):
        code = f"{secrets.randbelow(1_000_000):06d}"
        exists = db.scalar(select(Device).where(Device.pairing_code == code))
        if not exists:
            return code
    raise HTTPException(status_code=500, detail="Could not allocate pairing code")


def _issue_tokens() -> tuple[str, str, float]:
    access = secrets.token_urlsafe(32)
    refresh = secrets.token_urlsafe(32)
    expires = time.time() + TOKEN_TTL_SECONDS
    return access, refresh, expires


def _device_auth_payload(device: Device, account: Account | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "deviceId": device.id,
        "accountId": device.account_id,
        "accessToken": device.access_token,
        "refreshToken": device.refresh_token,
        "pairingCode": device.pairing_code,
        "expiresIn": TOKEN_TTL_SECONDS,
    }
    if account is not None:
        payload["email"] = account.email
        payload["displayName"] = account.display_name
    return payload


def _create_device_for_account(
    db: Session,
    *,
    account_id: str,
    device_display_name: str,
) -> Device:
    device_id = str(uuid.uuid4())
    pairing = _new_pairing_code(db)
    access, refresh, expires = _issue_tokens()
    device = Device(
        id=device_id,
        account_id=account_id,
        display_name=device_display_name.strip() or "Zy device",
        access_token=access,
        refresh_token=refresh,
        pairing_code=pairing,
        access_expires_at=expires,
    )
    db.add(device)
    return device


def require_device(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> Device:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    device = db.scalar(select(Device).where(Device.access_token == token))
    if not device:
        raise HTTPException(status_code=401, detail="Invalid access token")
    if device.access_expires_at < time.time():
        raise HTTPException(status_code=401, detail="Access token expired")
    return device


def require_admin(
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
) -> AdminToken:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    row = db.get(AdminToken, token)
    if not row:
        raise HTTPException(status_code=401, detail="Invalid admin token")
    if row.expires_at is None or row.expires_at < time.time():
        db.delete(row)
        db.commit()
        raise HTTPException(status_code=401, detail="Admin token expired")
    return row


def _assert_admin_device_access(db: Session, admin_device_id: str, device_id: str) -> None:
    if device_id == admin_device_id:
        return
    admin_device = db.get(Device, admin_device_id)
    target = db.get(Device, device_id)
    if not admin_device or not target or admin_device.account_id != target.account_id:
        raise HTTPException(status_code=403, detail="Not authorized for this device")


def _as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return None


def _validate_admin_command(command_type: str, payload: dict[str, Any]) -> dict[str, Any]:
    if command_type not in ALLOWED_ADMIN_COMMANDS:
        raise HTTPException(
            status_code=400,
            detail=f"Unknown command type. Allowed: {', '.join(sorted(ALLOWED_ADMIN_COMMANDS))}",
        )
    if command_type == "setAlarmEnabled":
        if "enabled" not in payload or not isinstance(payload["enabled"], bool):
            raise HTTPException(status_code=400, detail="setAlarmEnabled requires payload.enabled bool")
        return {"enabled": payload["enabled"]}
    if command_type in ("setBedtime", "setWakeTime"):
        hour = _as_int(payload.get("hour"))
        minute = _as_int(payload.get("minute"))
        if hour is None or minute is None:
            raise HTTPException(
                status_code=400,
                detail=f"{command_type} requires integer hour and minute",
            )
        if hour < 0 or hour > 23 or minute < 0 or minute > 59:
            raise HTTPException(
                status_code=400,
                detail=f"{command_type} hour 0-23, minute 0-59",
            )
        return {"hour": hour, "minute": minute}
    if command_type == "extendSleepTimer":
        minutes = _as_int(payload.get("minutes"))
        if minutes is None or minutes < 5 or minutes > 60:
            raise HTTPException(
                status_code=400,
                detail="extendSleepTimer requires payload.minutes integer 5-60",
            )
        return {"minutes": minutes}
    return {}


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict[str, Any]:
    """Liveness for Render/load balancers. Never expose pairing codes or tokens."""
    device_count = db.scalar(select(Device.id).limit(1))
    has_devices = device_count is not None
    db_url = (os.environ.get("DATABASE_URL") or "").strip()
    engine_kind = "postgres" if db_url.startswith(("postgres://", "postgresql://")) else "sqlite"
    return {
        "status": "ok",
        "hasDevices": has_devices,
        "database": engine_kind,
    }


@app.post("/v1/auth/register")
def auth_register(
    body: AuthRegisterBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _rate_limit(_client_key(request, "auth"), limit=AUTH_RATE_LIMIT)
    email = _normalize_email(body.email)
    if "@" not in email or len(email) < 3:
        raise HTTPException(status_code=400, detail="Invalid email")
    display_name = body.displayName.strip()
    if not display_name:
        raise HTTPException(status_code=400, detail="Display name is required")

    existing = db.scalar(select(Account).where(Account.email == email))
    if existing is not None:
        raise HTTPException(status_code=409, detail="Email already registered")

    account_id = str(uuid.uuid4())
    account = Account(
        id=account_id,
        email=email,
        password_hash=_hash_password(body.password),
        display_name=display_name,
    )
    db.add(account)
    device = _create_device_for_account(
        db,
        account_id=account_id,
        device_display_name=body.deviceDisplayName,
    )
    db.commit()
    db.refresh(device)
    db.refresh(account)
    return _device_auth_payload(device, account)


@app.post("/v1/auth/login")
def auth_login(
    body: AuthLoginBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _rate_limit(_client_key(request, "auth"), limit=AUTH_RATE_LIMIT)
    email = _normalize_email(body.email)
    account = db.scalar(select(Account).where(Account.email == email))
    if (
        account is None
        or not account.password_hash
        or not _verify_password(body.password, account.password_hash)
    ):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    device = _create_device_for_account(
        db,
        account_id=account.id,
        device_display_name=body.deviceDisplayName,
    )
    db.commit()
    db.refresh(device)
    return _device_auth_payload(device, account)


@app.get("/v1/auth/me")
def auth_me(
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    account = db.get(Account, device.account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="Account not found")
    return {
        "accountId": account.id,
        "email": account.email,
        "displayName": account.display_name,
    }


@app.patch("/v1/auth/me")
def auth_me_patch(
    body: AuthMePatchBody,
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    account = db.get(Account, device.account_id)
    if account is None:
        raise HTTPException(status_code=404, detail="Account not found")
    display_name = body.displayName.strip()
    if not display_name:
        raise HTTPException(status_code=400, detail="Display name is required")
    account.display_name = display_name
    db.commit()
    return {
        "accountId": account.id,
        "email": account.email,
        "displayName": account.display_name,
    }


@app.post("/v1/devices/register")
def register(body: RegisterBody, db: Session = Depends(get_db)) -> dict[str, Any]:
    account_id = str(uuid.uuid4())
    db.add(Account(id=account_id))
    device = _create_device_for_account(
        db,
        account_id=account_id,
        device_display_name=body.displayName,
    )
    db.commit()
    device = db.get(Device, device.id)
    assert device is not None
    return _device_auth_payload(device)


@app.post("/v1/devices/join")
def join_account(
    body: JoinAccountBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """Create a new device under an existing account (share sync via pairing code)."""
    _rate_limit(_client_key(request, "pair"), limit=PAIRING_RATE_LIMIT)
    code = _normalize_pairing_code(body.pairingCode)
    owner = db.scalar(select(Device).where(Device.pairing_code == code))
    if not owner:
        raise HTTPException(
            status_code=404,
            detail=(
                "Unknown pairing code. Use the 6-digit code from Settings → Sync / Admin "
                f"(not your PIN). Tried '{code}'."
            ),
        )
    device = _create_device_for_account(
        db,
        account_id=owner.account_id,
        device_display_name=body.displayName,
    )
    db.commit()
    db.refresh(device)
    return _device_auth_payload(device)


@app.post("/v1/devices/refresh")
def refresh(body: RefreshBody, db: Session = Depends(get_db)) -> dict[str, Any]:
    device = db.scalar(select(Device).where(Device.refresh_token == body.refreshToken))
    if not device:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    access, refresh_token, expires = _issue_tokens()
    device.access_token = access
    device.refresh_token = refresh_token
    device.access_expires_at = expires
    db.commit()
    return {
        "accessToken": access,
        "refreshToken": refresh_token,
        "expiresIn": TOKEN_TTL_SECONDS,
    }


@app.post("/v1/devices/check-in")
def check_in(
    body: CheckInBody,
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    status = body.deviceStatus.model_copy(update={"lastCheckIn": utcnow()})
    row = db.get(DeviceStatusRow, device.id)
    if not row:
        row = DeviceStatusRow(device_id=device.id)
        db.add(row)
    row.set_payload(status.model_dump(mode="json"))
    db.commit()
    return {"ok": True}


@app.post("/v1/admin/pair")
def admin_pair(
    body: PairBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _rate_limit(_client_key(request, "pair"), limit=PAIRING_RATE_LIMIT)
    code = _normalize_pairing_code(body.pairingCode)
    device = db.scalar(select(Device).where(Device.pairing_code == code))
    if not device:
        raise HTTPException(
            status_code=404,
            detail=(
                "Unknown pairing code. Use the 6-digit code from Flutter/iOS "
                "Settings → Admin after enabling sharing (not your PIN). "
                f"Tried '{code}'."
            ),
        )
    # Revoke prior guardian sessions for this device, then issue a fresh TTL'd token.
    db.execute(delete(AdminToken).where(AdminToken.device_id == device.id))
    token = secrets.token_urlsafe(32)
    expires_at = time.time() + ADMIN_TOKEN_TTL_SECONDS
    db.add(AdminToken(token=token, device_id=device.id, expires_at=expires_at))
    db.commit()
    return {
        "adminToken": token,
        "deviceId": device.id,
        "accountId": device.account_id,
        "expiresIn": ADMIN_TOKEN_TTL_SECONDS,
    }


@app.post("/v1/admin/logout")
def admin_logout(
    admin: AdminToken = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    db.delete(admin)
    db.commit()
    return {"ok": True}


@app.get("/v1/admin/devices")
def admin_list_devices(
    admin: AdminToken = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """List devices on the same account as the paired device (for guardian switcher)."""
    paired = db.get(Device, admin.device_id)
    if not paired:
        raise HTTPException(status_code=401, detail="Admin token device missing")
    devices = db.scalars(
        select(Device)
        .where(Device.account_id == paired.account_id)
        .order_by(Device.created_at.asc())
    ).all()
    out: list[dict[str, Any]] = []
    for device in devices:
        row = db.get(DeviceStatusRow, device.id)
        last_check_in: str | None = None
        if row:
            payload = row.get_payload()
            raw = payload.get("lastCheckIn")
            if isinstance(raw, str):
                last_check_in = raw
            elif row.updated_at is not None:
                last_check_in = row.updated_at.isoformat()
        out.append(
            {
                "deviceId": device.id,
                "displayName": device.display_name,
                "lastCheckIn": last_check_in,
                "hasStatus": row is not None,
            }
        )
    return {
        "accountId": paired.account_id,
        "pairedDeviceId": paired.id,
        "devices": out,
    }


@app.get("/v1/devices/{device_id}/status")
def device_status(
    device_id: str,
    admin: AdminToken = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _assert_admin_device_access(db, admin.device_id, device_id)
    row = db.get(DeviceStatusRow, device_id)
    if not row:
        raise HTTPException(status_code=404, detail="No status yet")
    return {"deviceStatus": row.get_payload()}


@app.post("/v1/devices/{device_id}/commands")
def enqueue_admin_command(
    device_id: str,
    body: AdminCommandBody,
    admin: AdminToken = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _assert_admin_device_access(db, admin.device_id, device_id)
    payload = _validate_admin_command(body.type, body.payload)
    cmd = AdminCommand(
        id=str(uuid.uuid4()),
        device_id=device_id,
        command_type=body.type,
    )
    cmd.set_payload(payload)
    db.add(cmd)
    db.commit()
    return {
        "id": cmd.id,
        "type": cmd.command_type,
        "payload": payload,
        "createdAt": cmd.created_at.isoformat(),
    }


@app.get("/v1/devices/commands/pending")
def pending_admin_commands(
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    rows = db.scalars(
        select(AdminCommand)
        .where(AdminCommand.device_id == device.id, AdminCommand.acked_at.is_(None))
        .order_by(AdminCommand.created_at.asc())
    ).all()
    return {
        "commands": [
            {
                "id": row.id,
                "type": row.command_type,
                "payload": row.get_payload(),
                "createdAt": row.created_at.isoformat(),
            }
            for row in rows
        ]
    }


@app.post("/v1/devices/commands/ack")
def ack_admin_commands(
    body: AckCommandsBody,
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    if not body.ids:
        return {"ok": True, "acked": 0}
    now = utcnow()
    rows = db.scalars(
        select(AdminCommand).where(
            AdminCommand.device_id == device.id,
            AdminCommand.id.in_(body.ids),
            AdminCommand.acked_at.is_(None),
        )
    ).all()
    for row in rows:
        row.acked_at = now
    db.commit()
    return {"ok": True, "acked": len(rows)}


@app.post("/v1/devices/revoke-admin-tokens")
def revoke_admin_tokens(
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, bool]:
    """Device-side: wipe all guardian sessions for this device (Disconnect remote)."""
    db.execute(delete(AdminToken).where(AdminToken.device_id == device.id))
    db.commit()
    return {"ok": True}


def _parse_since(since: str | None) -> datetime | None:
    if not since:
        return None
    try:
        value = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid since timestamp") from exc
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value


@app.get("/v1/sync")
def sync_pull(
    since: str | None = Query(default=None),
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    since_dt = _parse_since(since)
    stmt = select(SyncEntity).where(SyncEntity.account_id == device.account_id)
    if since_dt is not None:
        stmt = stmt.where(SyncEntity.updated_at > since_dt)
    stmt = stmt.order_by(SyncEntity.updated_at.asc())
    rows = db.scalars(stmt).all()
    server_time = utcnow()
    changes = [
        {
            "entityType": row.entity_type,
            "entityId": row.entity_id,
            "payload": row.get_payload(),
            "updatedAt": row.updated_at.isoformat(),
            "deleted": row.deleted,
            "writerDeviceId": row.writer_device_id,
        }
        for row in rows
    ]
    return {"serverTime": server_time.isoformat(), "changes": changes}


@app.post("/v1/sync")
def sync_push(
    body: SyncPushBody,
    device: Device = Depends(require_device),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    applied = 0
    rejected = 0
    for mutation in body.mutations:
        if mutation.entityType not in ALLOWED_ENTITY_TYPES:
            rejected += 1
            continue
        updated_at = mutation.updatedAt
        if updated_at.tzinfo is None:
            updated_at = updated_at.replace(tzinfo=timezone.utc)

        existing = db.scalar(
            select(SyncEntity).where(
                SyncEntity.account_id == device.account_id,
                SyncEntity.entity_type == mutation.entityType,
                SyncEntity.entity_id == mutation.entityId,
            )
        )
        if existing is not None:
            # Last-write-wins; tie-break prefers incoming when equal.
            if existing.updated_at > updated_at:
                rejected += 1
                continue
            if existing.updated_at == updated_at and existing.writer_device_id > device.id:
                rejected += 1
                continue
            existing.set_payload(mutation.payload)
            existing.updated_at = updated_at
            existing.deleted = mutation.deleted
            existing.writer_device_id = device.id
        else:
            row = SyncEntity(
                account_id=device.account_id,
                entity_type=mutation.entityType,
                entity_id=mutation.entityId,
                updated_at=updated_at,
                deleted=mutation.deleted,
                writer_device_id=device.id,
            )
            row.set_payload(mutation.payload)
            db.add(row)
        applied += 1
    db.commit()
    return {"ok": True, "applied": applied, "rejected": rejected, "serverTime": utcnow().isoformat()}


@app.get("/")
def dashboard() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8081"))
    host = os.environ.get("HOST", "127.0.0.1")
    uvicorn.run("main:app", host=host, port=port, reload=False)
