# Sleeping Routine for Zy — Remote Admin Backend

Phase 7 local/demo API. Production should use PostgreSQL, TLS, and hosted secrets.

## Run on Windows / Mac / Linux

```bash
cd backend
python -m venv .venv

# Windows
.venv\Scripts\activate
# macOS / Linux
# source .venv/bin/activate

pip install -r requirements.txt
python main.py
```

Open:

- API health: http://127.0.0.1:8080/health
- Guardian dashboard: http://127.0.0.1:8080/

## iPhone / Simulator config

Set in `Config/Secrets.xcconfig` (or Shared):

```
BACKEND_BASE_URL = http://127.0.0.1:8080
```

- **Simulator on same Mac as backend:** `127.0.0.1` works.
- **Physical iPhone:** use your PC/Mac LAN IP, e.g. `http://192.168.1.20:8080`, and allow local networking / firewall.

The iOS app allows local networking via `NSAllowsLocalNetworking`.

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/v1/devices/register` | none | Register Zy’s phone; returns tokens + pairing code |
| POST | `/v1/devices/refresh` | refresh token body | Rotate access token |
| POST | `/v1/devices/check-in` | Bearer device access | Upload opted-in `deviceStatus` |
| POST | `/v1/admin/pair` | none | Exchange pairing code for admin token |
| GET | `/v1/devices/{id}/status` | Bearer admin token | Read latest status |

## Production notes

- Replace in-memory dicts with PostgreSQL.
- Terminate TLS at a reverse proxy.
- Add rate limits, audit logs, and shorter pairing-code TTL.
- Never trust device ID alone — always require bearer tokens (as implemented).
