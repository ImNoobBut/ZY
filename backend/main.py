"""
Sleeping Routine for Zy — Remote Admin backend (Phase 7).

Local demo server with JSON file persistence (swap to PostgreSQL for production).
Run:  pip install -r requirements.txt && python -m uvicorn main:app --host 127.0.0.1 --port 8081
Dashboard: http://127.0.0.1:8081/
"""

from __future__ import annotations

import json
import secrets
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
import uvicorn

APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
STORE_PATH = APP_DIR / "data" / "store.json"

app = FastAPI(title="Sleeping Routine for Zy — Admin API", version="0.7.1")

# Flutter web (Chrome) runs on another origin/port — allow local demo CORS.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

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


class RegisterBody(BaseModel):
    displayName: str = "Zy iPhone"


class CheckInBody(BaseModel):
    deviceStatus: DeviceStatus


class RefreshBody(BaseModel):
    refreshToken: str


class PairBody(BaseModel):
    pairingCode: str


class DeviceRecord(BaseModel):
    device_id: str
    display_name: str
    access_token: str
    refresh_token: str
    pairing_code: str
    access_expires_at: float
    status: DeviceStatus | None = None


devices_by_id: dict[str, DeviceRecord] = {}
devices_by_access: dict[str, str] = {}
devices_by_refresh: dict[str, str] = {}
devices_by_pairing: dict[str, str] = {}
admin_tokens: dict[str, str] = {}  # token -> device_id

TOKEN_TTL_SECONDS = 3600


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _new_pairing_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def _normalize_pairing_code(raw: str) -> str:
    """Accept '1234' or '001234' — always compare as zero-padded 6 digits."""
    digits = "".join(ch for ch in raw.strip() if ch.isdigit())
    if not digits:
        return raw.strip()
    if len(digits) > 6:
        return digits[-6:]
    return digits.zfill(6)


def _issue_tokens(device_id: str) -> tuple[str, str, float]:
    access = secrets.token_urlsafe(32)
    refresh = secrets.token_urlsafe(32)
    expires = time.time() + TOKEN_TTL_SECONDS
    devices_by_access[access] = device_id
    devices_by_refresh[refresh] = device_id
    return access, refresh, expires


def _save_store() -> None:
    STORE_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "devices": [record.model_dump(mode="json") for record in devices_by_id.values()],
        "admin_tokens": admin_tokens,
    }
    STORE_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _load_store() -> None:
    if not STORE_PATH.exists():
        return
    try:
        payload = json.loads(STORE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return

    devices_by_id.clear()
    devices_by_access.clear()
    devices_by_refresh.clear()
    devices_by_pairing.clear()
    admin_tokens.clear()

    for item in payload.get("devices", []):
        try:
            record = DeviceRecord.model_validate(item)
        except Exception:
            continue
        devices_by_id[record.device_id] = record
        devices_by_access[record.access_token] = record.device_id
        devices_by_refresh[record.refresh_token] = record.device_id
        devices_by_pairing[record.pairing_code] = record.device_id

    for token, device_id in (payload.get("admin_tokens") or {}).items():
        if device_id in devices_by_id:
            admin_tokens[token] = device_id


def require_device(authorization: str | None = Header(default=None)) -> DeviceRecord:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    device_id = devices_by_access.get(token)
    if not device_id:
        raise HTTPException(status_code=401, detail="Invalid access token")
    record = devices_by_id[device_id]
    if record.access_expires_at < time.time():
        raise HTTPException(status_code=401, detail="Access token expired")
    return record


def require_admin(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    device_id = admin_tokens.get(token)
    if not device_id:
        raise HTTPException(status_code=401, detail="Invalid admin token")
    return device_id


@app.on_event("startup")
def on_startup() -> None:
    _load_store()


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "devices": len(devices_by_id),
        "pairingCodes": sorted(devices_by_pairing.keys()),
    }


@app.post("/v1/devices/register")
def register(body: RegisterBody) -> dict[str, Any]:
    device_id = str(uuid.uuid4())
    pairing = _new_pairing_code()
    while pairing in devices_by_pairing:
        pairing = _new_pairing_code()
    access, refresh, expires = _issue_tokens(device_id)
    record = DeviceRecord(
        device_id=device_id,
        display_name=body.displayName,
        access_token=access,
        refresh_token=refresh,
        pairing_code=pairing,
        access_expires_at=expires,
    )
    devices_by_id[device_id] = record
    devices_by_pairing[pairing] = device_id
    _save_store()
    return {
        "deviceId": device_id,
        "accessToken": access,
        "refreshToken": refresh,
        "pairingCode": pairing,
        "expiresIn": TOKEN_TTL_SECONDS,
    }


@app.post("/v1/devices/refresh")
def refresh(body: RefreshBody) -> dict[str, Any]:
    device_id = devices_by_refresh.get(body.refreshToken)
    if not device_id:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    record = devices_by_id[device_id]
    devices_by_access.pop(record.access_token, None)
    devices_by_refresh.pop(record.refresh_token, None)
    access, refresh_token, expires = _issue_tokens(device_id)
    record.access_token = access
    record.refresh_token = refresh_token
    record.access_expires_at = expires
    _save_store()
    return {
        "accessToken": access,
        "refreshToken": refresh_token,
        "expiresIn": TOKEN_TTL_SECONDS,
    }


@app.post("/v1/devices/check-in")
def check_in(body: CheckInBody, record: DeviceRecord = Depends(require_device)) -> dict[str, bool]:
    status = body.deviceStatus
    status.lastCheckIn = _utcnow()
    record.status = status
    _save_store()
    return {"ok": True}


@app.post("/v1/admin/pair")
def admin_pair(body: PairBody) -> dict[str, Any]:
    code = _normalize_pairing_code(body.pairingCode)
    device_id = devices_by_pairing.get(code)
    if not device_id:
        raise HTTPException(
            status_code=404,
            detail=(
                "Unknown pairing code. Use the 6-digit code from Flutter/iOS "
                "Settings → Admin after enabling sharing (not your PIN). "
                f"Tried '{code}'."
            ),
        )
    token = secrets.token_urlsafe(32)
    admin_tokens[token] = device_id
    _save_store()
    return {
        "adminToken": token,
        "deviceId": device_id,
        "expiresIn": TOKEN_TTL_SECONDS * 24,
    }


@app.get("/v1/devices/{device_id}/status")
def device_status(device_id: str, admin_device_id: str = Depends(require_admin)) -> dict[str, Any]:
    if device_id != admin_device_id:
        raise HTTPException(status_code=403, detail="Not authorized for this device")
    record = devices_by_id.get(device_id)
    if not record or not record.status:
        raise HTTPException(status_code=404, detail="No status yet")
    return {"deviceStatus": record.status.model_dump(mode="json")}


@app.get("/")
def dashboard() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8081, reload=False)
