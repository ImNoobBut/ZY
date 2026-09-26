#!/usr/bin/env python3
"""Phase 9 — automated device-matrix subset (no physical phones required).

Checks:
  1) Static contracts in source (AlarmKit / Android exact / web best-effort / Spotify URIs)
  2) Backend API smoke (register → pair → check-in → status → sync → health hygiene)

Usage (from repo root):
  backend\\.venv\\Scripts\\python.exe scripts\\phase9_matrix.py
"""

from __future__ import annotations

import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
PASS = 0
FAIL = 0
SKIP = 0


def record(ok: bool, name: str, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}" + (f" — {detail}" if detail else ""))
    else:
        FAIL += 1
        print(f"  FAIL  {name}" + (f" — {detail}" if detail else ""))


def skip(name: str, detail: str) -> None:
    global SKIP
    SKIP += 1
    print(f"  SKIP  {name} — {detail}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def check_static_contracts() -> None:
    print("\n== Static platform contracts ==")

    manifest = ROOT / "flutter_app/android/app/src/main/AndroidManifest.xml"
    text = read(manifest)
    record("SCHEDULE_EXACT_ALARM" in text, "Android SCHEDULE_EXACT_ALARM permission")
    record("POST_NOTIFICATIONS" in text, "Android POST_NOTIFICATIONS permission")
    record("RECEIVE_BOOT_COMPLETED" in text, "Android RECEIVE_BOOT_COMPLETED permission")

    io_sched = read(ROOT / "flutter_app/lib/core/services/alarm_scheduler_io.dart")
    record(
        "exactAllowWhileIdle" in io_sched,
        "Android exactAllowWhileIdle schedule mode",
    )
    record(
        "scheduleExactAlarm" in io_sched,
        "Android exact-alarm permission request",
    )

    web_sched = read(ROOT / "flutter_app/lib/core/services/alarm_scheduler_web.dart")
    record("isBestEffortOnly" in web_sched and "true" in web_sched, "Web scheduler best-effort flag")
    record(
        "tab stays open" in web_sched.lower() or "while this tab" in web_sched.lower(),
        "Web alarm limitation copy present",
    )

    factory = read(ROOT / "flutter_app/lib/core/services/alarm_scheduler_factory.dart")
    record("dart.library.html" in factory and "dart.library.io" in factory, "Alarm factory conditional exports")

    alarmkit = ROOT / "SleepingRoutineForZy/Core/Services/AlarmSchedulerAlarmKit.swift"
    ak = read(alarmkit)
    record("AlarmKit" in ak and "iOS 26" in ak, "iOS AlarmKit scheduler (iOS 26+)")
    record("AlarmSchedulerLive" in ak or "AlarmSchedulerLive" in read(
        ROOT / "SleepingRoutineForZy/Core/Services/AlarmScheduler.swift"
    ), "iOS notification fallback scheduler")

    info = read(ROOT / "SleepingRoutineForZy/Resources/Info.plist")
    record("NSAlarmKitUsageDescription" in info, "Info.plist AlarmKit usage string")
    record(
        "CFBundleURLSchemes" not in info and "sleepingroutineforzy" not in info,
        "iOS custom Spotify URL scheme removed (HTTPS Universal Links)",
    )
    entitlements = read(ROOT / "SleepingRoutineForZy/SleepingRoutineForZy.entitlements")
    record(
        "applinks:sleeping-routine-for-zy.pages.dev" in entitlements,
        "iOS Associated Domains entitlement for Pages callback",
    )
    shared = read(ROOT / "Config/Shared.xcconfig")
    record(
        "sleeping-routine-for-zy.pages.dev/callback" in shared,
        "Shared.xcconfig Spotify redirect is Pages HTTPS",
    )
    assetlinks = read(ROOT / "flutter_app/web/.well-known/assetlinks.json")
    record(
        "com.zy.sleepingroutine.sleeping_routine_for_zy" in assetlinks,
        "Android Digital Asset Links package present",
    )

    readme = read(ROOT / "README.md")
    for uri in (
        "https://sleeping-routine-for-zy.pages.dev/callback",
        "http://127.0.0.1:7357/callback",
        "pages.dev/callback",
    ):
        record(uri in readme, f"README documents Spotify redirect ({uri})")

    health = read(BACKEND / "main.py")
    record("pairingCodes" not in health or "Never expose pairing" in health, "Health endpoint must not leak pairing codes")
    # Stronger: health handler body shouldn't return pairingCodes
    m = re.search(r'@app\.get\("/health"\)[\s\S]*?return \{([\s\S]*?)\}', health)
    if m:
        record("pairingCodes" not in m.group(1), "Health return payload omits pairingCodes")
    else:
        record(False, "Locate /health handler")


def api(method: str, path: str, body: dict | None = None, token: str | None = None) -> tuple[int, dict | str]:
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:8081{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            raw = resp.read().decode()
            try:
                return resp.status, json.loads(raw)
            except json.JSONDecodeError:
                return resp.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, raw
    except OSError as e:
        return 0, str(e)


def check_api_smoke() -> None:
    print("\n== Backend API smoke (localhost:8081) ==")
    status, health = api("GET", "/health")
    if status == 0:
        skip("API smoke suite", f"backend not reachable ({health}). Start with: cd backend && python main.py")
        return

    record(status == 200 and isinstance(health, dict), "GET /health", str(health)[:120])
    if isinstance(health, dict):
        record("pairingCodes" not in health, "Health response has no pairingCodes")
        record(health.get("status") == "ok", "Health status ok")

    status, reg = api("POST", "/v1/devices/register", {"displayName": "Phase9 Matrix"})
    record(status == 200 and isinstance(reg, dict) and "pairingCode" in reg, "POST /v1/devices/register")
    if not isinstance(reg, dict):
        return
    access = reg["accessToken"]
    pairing = reg["pairingCode"]
    device_id = reg["deviceId"]

    status, pair = api("POST", "/v1/admin/pair", {"pairingCode": pairing})
    record(status == 200 and isinstance(pair, dict) and "adminToken" in pair, "POST /v1/admin/pair")
    if not isinstance(pair, dict):
        return
    admin = pair["adminToken"]
    record(pair.get("expiresIn", 0) > 0, "Admin token advertises expiresIn")

    from datetime import datetime, timezone

    payload = {
        "deviceStatus": {
            "batteryLevel": 0.8,
            "isCharging": True,
            "routineActive": False,
            "routineStartedAt": None,
            "sleepTimerEndsAt": None,
            "spotifyConnected": False,
            "alarmEnabled": True,
            "nextAlarm": None,
            "isPlayingOwnAudio": False,
            "lastCheckIn": datetime.now(timezone.utc).isoformat(),
            "preferredBedtime": "22:30",
            "currentStreak": 1,
        }
    }
    status, cin = api("POST", "/v1/devices/check-in", payload, token=access)
    record(status == 200, "POST /v1/devices/check-in (device bearer)")

    status, st = api("GET", f"/v1/devices/{device_id}/status", token=admin)
    record(status == 200 and isinstance(st, dict) and "deviceStatus" in st, "GET device status (admin bearer)")

    status, devices = api("GET", "/v1/admin/devices", token=admin)
    record(
        status == 200
        and isinstance(devices, dict)
        and devices.get("pairedDeviceId") == device_id
        and isinstance(devices.get("devices"), list)
        and any(d.get("deviceId") == device_id for d in devices["devices"]),
        "GET /v1/admin/devices lists paired device",
    )

    status, cmd = api(
        "POST",
        f"/v1/devices/{device_id}/commands",
        {"type": "setWakeTime", "payload": {"hour": 7, "minute": 15}},
        token=admin,
    )
    record(
        status == 200 and isinstance(cmd, dict) and cmd.get("type") == "setWakeTime",
        "POST admin command setWakeTime",
    )
    status, cmd_bad = api(
        "POST",
        f"/v1/devices/{device_id}/commands",
        {"type": "extendSleepTimer", "payload": {"minutes": 2}},
        token=admin,
    )
    record(status == 400, "extendSleepTimer rejects minutes < 5")

    # Second device on same account — admin can list both and command the other.
    status, joined = api(
        "POST",
        "/v1/devices/join",
        {"pairingCode": pairing, "displayName": "Phase9 Matrix Phone 2"},
    )
    if status == 200 and isinstance(joined, dict) and "deviceId" in joined:
        other_id = joined["deviceId"]
        status, devices2 = api("GET", "/v1/admin/devices", token=admin)
        ids = {d.get("deviceId") for d in (devices2.get("devices") or [])} if isinstance(devices2, dict) else set()
        record(
            status == 200 and device_id in ids and other_id in ids,
            "GET /v1/admin/devices lists same-account devices",
        )
        status, cmd_other = api(
            "POST",
            f"/v1/devices/{other_id}/commands",
            {"type": "startQuietAudio", "payload": {}},
            token=admin,
        )
        record(
            status == 200 and isinstance(cmd_other, dict) and cmd_other.get("type") == "startQuietAudio",
            "Admin can command another same-account device",
        )
    else:
        skip("Multi-device admin list", f"join failed ({status})")

    # Re-pair must revoke old admin token
    status, pair2 = api("POST", "/v1/admin/pair", {"pairingCode": pairing})
    record(status == 200, "Re-pair issues new admin token")
    status, revoked = api("GET", f"/v1/devices/{device_id}/status", token=admin)
    record(status == 401, "Old admin token revoked after re-pair")

    mut = {
        "mutations": [
            {
                "entityType": "preferences",
                "entityId": "prefs",
                "payload": {"remoteMonitoringOptIn": False},
                "updatedAt": datetime.now(timezone.utc).isoformat(),
                "deleted": False,
            }
        ]
    }
    status, sync = api("POST", "/v1/sync", mut, token=access)
    record(status == 200 and isinstance(sync, dict) and sync.get("ok") is True, "POST /v1/sync push")
    status, pull = api("GET", "/v1/sync", token=access)
    record(status == 200 and isinstance(pull, dict) and "changes" in pull, "GET /v1/sync pull")


def main() -> int:
    print("Phase 9 device-matrix automated subset")
    print(f"Repo: {ROOT}")
    check_static_contracts()
    check_api_smoke()
    print(f"\nSummary: {PASS} pass, {FAIL} fail, {SKIP} skip")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
