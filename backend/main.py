"""
Sleeping Routine for Zy — Remote Admin + sync API.

Persistence: Postgres when DATABASE_URL is set, else SQLite (backend/data/app.db).
Run locally:  pip install -r requirements.txt && python main.py
Dashboard: http://127.0.0.1:8081/
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import secrets
import smtplib
import time
import uuid
import urllib.error
import urllib.request
from datetime import datetime, timezone
from email.message import EmailMessage
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
    PasswordReset,
    SyncEntity,
    get_db,
    init_db,
    utcnow,
)

log = logging.getLogger("srz.auth")

APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
TOKEN_TTL_SECONDS = 3600
ADMIN_TOKEN_TTL_SECONDS = TOKEN_TTL_SECONDS * 24
PAIRING_RATE_LIMIT = 20
AUTH_RATE_LIMIT = 15
RESET_RATE_LIMIT = 5
RATE_WINDOW_SECONDS = 60.0
RESET_CODE_TTL_SECONDS = 15 * 60
RESET_CODE_PEPPER = (os.environ.get("RESET_CODE_PEPPER") or "zy-sleep-reset").strip()

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


class AuthForgotPasswordBody(BaseModel):
    email: str


class AuthResetPasswordBody(BaseModel):
    email: str
    code: str = Field(min_length=4, max_length=12)
    password: str = Field(min_length=8, max_length=72)


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


def _email_looks_valid(email: str) -> bool:
    if "@" not in email or len(email) < 5 or len(email) > 320:
        return False
    local, _, domain = email.partition("@")
    return bool(local) and "." in domain and " " not in email


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, password_hash: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), password_hash.encode("utf-8"))
    except ValueError:
        return False


def _hash_reset_code(account_id: str, code: str) -> str:
    raw = f"{account_id}:{code.strip()}:{RESET_CODE_PEPPER}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _reset_email_body(*, code: str, display_name: str | None) -> tuple[str, str]:
    """Return (subject, plain text body)."""
    app_name = (os.environ.get("APP_DISPLAY_NAME") or "Zy Sleep").strip()
    greeting = (display_name or "").strip() or "there"
    subject = f"{app_name} password reset code"
    body = (
        f"Hi {greeting},\n\n"
        f"Your {app_name} password reset code is: {code}\n\n"
        f"It expires in 15 minutes. If you did not request this, you can ignore this email.\n"
    )
    return subject, body


def _http_json(
    url: str,
    *,
    headers: dict[str, str],
    payload: dict[str, Any],
) -> tuple[bool, str]:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            raw = res.read().decode("utf-8", errors="replace")
            return 200 <= res.status < 300, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace")
        return False, f"HTTP {e.code}: {raw}"
    except Exception as e:
        return False, str(e)


def _send_via_resend(*, to_email: str, subject: str, body: str) -> bool:
    """HTTPS API — works on Render free (SMTP ports are blocked)."""
    key = (os.environ.get("RESEND_API_KEY") or "").strip()
    if not key:
        return False
    from_addr = (
        (os.environ.get("EMAIL_FROM") or os.environ.get("SMTP_FROM") or "").strip()
        or "Zy Sleep <onboarding@resend.dev>"
    )
    ok, detail = _http_json(
        "https://api.resend.com/emails",
        headers={"Authorization": f"Bearer {key}"},
        payload={"from": from_addr, "to": [to_email], "subject": subject, "text": body},
    )
    if not ok:
        log.error("Resend email failed for %s: %s", to_email, detail)
    return ok


def _send_via_brevo(*, to_email: str, subject: str, body: str) -> bool:
    """HTTPS API (Brevo / Sendinblue) — verify a Gmail sender in their dashboard."""
    key = (os.environ.get("BREVO_API_KEY") or "").strip()
    if not key:
        return False
    from_email = (
        (os.environ.get("EMAIL_FROM") or os.environ.get("SMTP_FROM") or "").strip()
        or (os.environ.get("SMTP_USER") or "").strip()
    )
    if not from_email:
        log.error("Brevo configured but EMAIL_FROM / SMTP_FROM is missing")
        return False
    # Allow "Name <email@x.com>" or bare email.
    name = (os.environ.get("APP_DISPLAY_NAME") or "Zy Sleep").strip()
    if "<" in from_email and ">" in from_email:
        display, _, rest = from_email.partition("<")
        email_only = rest.rstrip(">").strip()
        name = display.strip() or name
    else:
        email_only = from_email
    ok, detail = _http_json(
        "https://api.brevo.com/v3/smtp/email",
        headers={"api-key": key, "accept": "application/json"},
        payload={
            "sender": {"name": name, "email": email_only},
            "to": [{"email": to_email}],
            "subject": subject,
            "textContent": body,
        },
    )
    if not ok:
        log.error("Brevo email failed for %s: %s", to_email, detail)
    return ok


def _send_via_smtp(*, to_email: str, subject: str, body: str) -> bool:
    """Direct SMTP — fine locally; often blocked on Render free (errno 101)."""
    host = (os.environ.get("SMTP_HOST") or "").strip()
    if not host:
        return False
    port = int((os.environ.get("SMTP_PORT") or "587").strip() or "587")
    user = (os.environ.get("SMTP_USER") or "").strip()
    password = os.environ.get("SMTP_PASSWORD") or ""
    from_addr = (os.environ.get("SMTP_FROM") or user or "noreply@localhost").strip()

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = to_email
    msg.set_content(body)

    try:
        with smtplib.SMTP(host, port, timeout=20) as smtp:
            smtp.ehlo()
            if (os.environ.get("SMTP_STARTTLS") or "1").strip() not in ("0", "false", "False"):
                smtp.starttls()
                smtp.ehlo()
            if user:
                smtp.login(user, password)
            smtp.send_message(msg)
        return True
    except OSError as e:
        log.error(
            "SMTP unreachable for %s (%s). "
            "Render free blocks outbound SMTP — use RESEND_API_KEY or BREVO_API_KEY instead.",
            to_email,
            e,
        )
        return False
    except Exception:
        log.exception("Failed to send password reset email via SMTP to %s", to_email)
        return False


def _send_reset_email(*, to_email: str, code: str, display_name: str | None) -> bool:
    """Prefer HTTPS providers (Resend/Brevo); fall back to SMTP for local/dev."""
    subject, body = _reset_email_body(code=code, display_name=display_name)
    if _send_via_resend(to_email=to_email, subject=subject, body=body):
        return True
    if _send_via_brevo(to_email=to_email, subject=subject, body=body):
        return True
    if _send_via_smtp(to_email=to_email, subject=subject, body=body):
        return True
    return False


def _dev_expose_reset_code() -> bool:
    flag = (os.environ.get("AUTH_DEV_EXPOSE_RESET_CODE") or "").strip().lower()
    return flag in ("1", "true", "yes", "on")


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
    if not _email_looks_valid(email):
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


@app.post("/v1/auth/forgot-password")
def auth_forgot_password(
    body: AuthForgotPasswordBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    """Always returns a generic success message to avoid email enumeration."""
    _rate_limit(_client_key(request, "reset"), limit=RESET_RATE_LIMIT)
    email = _normalize_email(body.email)
    generic = {
        "ok": True,
        "message": (
            "If an account exists for that email, a reset code has been sent. "
            "It expires in 15 minutes."
        ),
    }
    if not _email_looks_valid(email):
        return generic

    account = db.scalar(select(Account).where(Account.email == email))
    if account is None or not account.password_hash:
        return generic

    # Invalidate prior unused codes for this account.
    now = time.time()
    prior = db.scalars(
        select(PasswordReset).where(
            PasswordReset.account_id == account.id,
            PasswordReset.used_at.is_(None),
        )
    ).all()
    for row in prior:
        row.used_at = utcnow()

    code = f"{secrets.randbelow(1_000_000):06d}"
    reset = PasswordReset(
        id=str(uuid.uuid4()),
        account_id=account.id,
        code_hash=_hash_reset_code(account.id, code),
        expires_at=now + RESET_CODE_TTL_SECONDS,
    )
    db.add(reset)
    db.commit()

    sent = _send_reset_email(
        to_email=email,
        code=code,
        display_name=account.display_name,
    )
    if not sent:
        log.warning(
            "Password reset code for %s (email not sent — set RESEND_API_KEY or "
            "BREVO_API_KEY on Render; SMTP is often blocked): %s",
            email,
            code,
        )

    if _dev_expose_reset_code():
        generic = {
            **generic,
            "devResetCode": code,
            "emailDelivery": "sent" if sent else "log",
        }
    return generic


@app.post("/v1/auth/reset-password")
def auth_reset_password(
    body: AuthResetPasswordBody,
    request: Request,
    db: Session = Depends(get_db),
) -> dict[str, Any]:
    _rate_limit(_client_key(request, "reset"), limit=RESET_RATE_LIMIT)
    email = _normalize_email(body.email)
    code = "".join(ch for ch in body.code.strip() if ch.isdigit())
    if not _email_looks_valid(email) or len(code) != 6:
        raise HTTPException(status_code=400, detail="Invalid email or reset code")

    account = db.scalar(select(Account).where(Account.email == email))
    if account is None or not account.password_hash:
        raise HTTPException(status_code=400, detail="Invalid email or reset code")

    now = time.time()
    candidates = db.scalars(
        select(PasswordReset)
        .where(
            PasswordReset.account_id == account.id,
            PasswordReset.used_at.is_(None),
            PasswordReset.expires_at >= now,
        )
        .order_by(PasswordReset.created_at.desc())
    ).all()

    match: PasswordReset | None = None
    expected = _hash_reset_code(account.id, code)
    for row in candidates:
        if secrets.compare_digest(row.code_hash, expected):
            match = row
            break

    if match is None:
        raise HTTPException(status_code=400, detail="Invalid or expired reset code")

    account.password_hash = _hash_password(body.password)
    match.used_at = utcnow()
    # Burn any other outstanding codes.
    for row in candidates:
        if row.id != match.id:
            row.used_at = utcnow()
    db.commit()
    return {"ok": True, "message": "Password updated. You can sign in with your new password."}


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


def _as_utc(value: datetime) -> datetime:
    """Normalize DB/client timestamps for comparison (SQLite often returns naive UTC)."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _parse_since(since: str | None) -> datetime | None:
    if not since:
        return None
    try:
        value = datetime.fromisoformat(since.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="Invalid since timestamp") from exc
    return _as_utc(value)


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
            "updatedAt": _as_utc(row.updated_at).isoformat(),
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
        updated_at = _as_utc(mutation.updatedAt)

        existing = db.scalar(
            select(SyncEntity).where(
                SyncEntity.account_id == device.account_id,
                SyncEntity.entity_type == mutation.entityType,
                SyncEntity.entity_id == mutation.entityId,
            )
        )
        if existing is not None:
            # Last-write-wins; tie-break prefers incoming when equal.
            existing_updated_at = _as_utc(existing.updated_at)
            if existing_updated_at > updated_at:
                rejected += 1
                continue
            if existing_updated_at == updated_at and existing.writer_device_id > device.id:
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
