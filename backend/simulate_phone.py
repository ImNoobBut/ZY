"""Simulate Zy iPhone Admin check-in against the local backend."""
from __future__ import annotations

import json
import urllib.request

BASE = "http://127.0.0.1:8081"


def req(method: str, path: str, body=None, token=None):
    data = None if body is None else json.dumps(body).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request) as resp:
        return json.load(resp)


def main() -> None:
    print("=== Simulating Zy iPhone app ===")
    print("1) Health:", req("GET", "/health"))

    print("2) Register device (Settings > Admin > opt-in)")
    reg = req("POST", "/v1/devices/register", {"displayName": "Zy iPhone"})
    print("   deviceId:", reg["deviceId"][:8] + "...")
    print("   pairingCode:", reg["pairingCode"])

    print("3) Check-in status (app foreground)")
    status = {
        "batteryLevel": 0.82,
        "isCharging": True,
        "routineActive": True,
        "routineStartedAt": "2026-09-24T16:00:00Z",
        "sleepTimerEndsAt": "2026-09-24T16:30:00Z",
        "spotifyConnected": True,
        "alarmEnabled": True,
        "nextAlarm": "2026-09-25T07:00:00+08:00",
        "isPlayingOwnAudio": False,
        "lastCheckIn": "2026-09-24T16:05:00Z",
        "preferredBedtime": "22:00",
        "currentStreak": 3,
    }
    req("POST", "/v1/devices/check-in", {"deviceStatus": status}, token=reg["accessToken"])
    print("   check-in OK")

    print("4) Guardian pairs with code", reg["pairingCode"])
    pair = req("POST", "/v1/admin/pair", {"pairingCode": reg["pairingCode"]})
    print("   admin token issued")

    print("5) Guardian reads status")
    view = req(
        "GET",
        f"/v1/devices/{reg['deviceId']}/status",
        token=pair["adminToken"],
    )
    s = view["deviceStatus"]
    print("   routineActive:", s["routineActive"])
    print("   preferredBedtime:", s.get("preferredBedtime"))
    print("   currentStreak:", s.get("currentStreak"))
    print("   batteryLevel:", s.get("batteryLevel"))
    print("   spotifyConnected:", s["spotifyConnected"])
    print("   alarmEnabled:", s["alarmEnabled"])
    print()
    print("PAIRING_CODE=" + reg["pairingCode"])
    print("DASHBOARD=http://127.0.0.1:8081/")
    print("Open the dashboard and enter the pairing code above.")


if __name__ == "__main__":
    main()
