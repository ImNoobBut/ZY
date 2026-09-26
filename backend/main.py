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

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session
import uvicorn

from db import (
    Account,
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

app = FastAPI(title="Sleeping Routine for Zy — Admin + Sync API", version="0.9.0")


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


class SyncMutation(BaseModel):
    entityType: str = Field(description="preferences | alarm | session | routine")
    entityId: str
    payload: dict[str, Any] = Field(default_factory=dict)
    updatedAt: datetime
    deleted: bool = False


class SyncPushBody(BaseModel):
    mutations: list[SyncMutation]


ALLOWED_ENTITY_TYPES = frozenset({"preferences", "alarm", "session", "routine"})


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


def _device_auth_payload(device: Device) -> dict[str, Any]:
    return {
        "deviceId": device.id,
        "accountId": device.account_id,
        "accessToken": device.access_token,
        "refreshToken": device.refresh_token,
        "pairingCode": device.pairing_code,
        "expiresIn": TOKEN_TTL_SECONDS,
    }


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
) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    row = db.get(AdminToken, token)
    if not row:
        raise HTTPException(status_code=401, detail="Invalid admin token")
    return row.device_id


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict[str, Any]:
    devices = list(db.scalars(select(Device)).all())
    db_url = (os.environ.get("DATABASE_URL") or "").strip()
    engine_kind = "postgres" if db_url.startswith(("postgres://", "postgresql://")) else "sqlite"
    return {
        "status": "ok",
        "devices": len(devices),
        "pairingCodes": sorted(d.pairing_code for d in devices),
        "database": engine_kind,
    }


@app.post("/v1/devices/register")
def register(body: RegisterBody, db: Session = Depends(get_db)) -> dict[str, Any]:
    account_id = str(uuid.uuid4())
    device_id = str(uuid.uuid4())
    pairing = _new_pairing_code(db)
    access, refresh, expires = _issue_tokens()
    db.add(Account(id=account_id))
    db.add(
        Device(
            id=device_id,
            account_id=account_id,
            display_name=body.displayName,
            access_token=access,
            refresh_token=refresh,
            pairing_code=pairing,
            access_expires_at=expires,
        )
    )
    db.commit()
    device = db.get(Device, device_id)
    assert device is not None
    return _device_auth_payload(device)


@app.post("/v1/devices/join")
def join_account(body: JoinAccountBody, db: Session = Depends(get_db)) -> dict[str, Any]:
    """Create a new device under an existing account (share sync via pairing code)."""
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
    device_id = str(uuid.uuid4())
    pairing = _new_pairing_code(db)
    access, refresh, expires = _issue_tokens()
    device = Device(
        id=device_id,
        account_id=owner.account_id,
        display_name=body.displayName,
        access_token=access,
        refresh_token=refresh,
        pairing_code=pairing,
        access_expires_at=expires,
    )
    db.add(device)
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
def admin_pair(body: PairBody, db: Session = Depends(get_db)) -> dict[str, Any]:
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
    token = secrets.token_urlsafe(32)
    db.add(AdminToken(token=token, device_id=device.id))
    db.commit()
    return {
        "adminToken": token,
        "deviceId": device.id,
        "accountId": device.account_id,
        "expiresIn": TOKEN_TTL_SECONDS * 24,
    }


@app.get("/v1/devices/{device_id}/status")
def device_status(
    device_id: str,
    admin_device_id: str = Depends(require_admin),
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    if device_id != admin_device_id:
        # Allow admin to read any device on the same account
        admin_device = db.get(Device, admin_device_id)
        target = db.get(Device, device_id)
        if not admin_device or not target or admin_device.account_id != target.account_id:
            raise HTTPException(status_code=403, detail="Not authorized for this device")
    row = db.get(DeviceStatusRow, device_id)
    if not row:
        raise HTTPException(status_code=404, detail="No status yet")
    return {"deviceStatus": row.get_payload()}


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
