# Sleeping Routine for Zy — Remote Admin + Sync Backend

FastAPI service for guardian Remote Admin and offline-first full sync.

## Persistence

| Env | Store |
|-----|--------|
| `DATABASE_URL` unset | SQLite at `backend/data/app.db` (local demo) |
| `DATABASE_URL=postgresql://...` | Neon / Render / any Postgres |

## Run locally

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

- API health: http://127.0.0.1:8081/health
- Guardian dashboard: http://127.0.0.1:8081/

## Deploy (Render free + Neon free)

1. Create a Neon project and copy the Postgres connection string.
2. Push this repo and create a Render Web Service from [`render.yaml`](../render.yaml) (Docker context `backend/`).
3. Set Render env vars:
   - `DATABASE_URL` — Neon URL (`postgres://` is auto-normalized)
   - `CORS_ORIGINS` — your Cloudflare Pages origin, e.g. `https://your-app.pages.dev`
4. Note the HTTPS service URL — that becomes Flutter `BACKEND_BASE_URL`.

Optional: `docker build -t srz-api ./backend && docker run -p 8081:8081 -e PORT=8081 srz-api`

## Endpoints

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/v1/auth/register` | none | Email/password signup + device; returns tokens + profile |
| POST | `/v1/auth/login` | none | Email/password login; new device on account |
| GET | `/v1/auth/me` | Bearer device | Current account email + display name |
| PATCH | `/v1/auth/me` | Bearer device | Update display name |
| POST | `/v1/devices/register` | none | New anonymous account + device; returns tokens + pairing code |
| POST | `/v1/devices/join` | none | New device on an existing account (pairing code) |
| POST | `/v1/devices/refresh` | refresh token body | Rotate access token |
| POST | `/v1/devices/check-in` | Bearer device | Upload opted-in `deviceStatus` |
| POST | `/v1/admin/pair` | none | Exchange pairing code for admin token |
| GET | `/v1/devices/{id}/status` | Bearer admin | Read latest status |
| GET | `/v1/sync?since=` | Bearer device | Pull account sync changes |
| POST | `/v1/sync` | Bearer device | Push LWW mutations (preferences, alarm, session, routine) |

## Sync model

- Documents are scoped to an **account** (all devices that share a pairing-code join).
- Entity types: `preferences`, `alarm`, `session`, `routine`.
- Conflict rule: **last-write-wins** on `updatedAt`, then `writerDeviceId` tie-break.

## Production notes

- Prefer Neon/Postgres over SQLite on free PaaS (ephemeral disks).
- Terminate TLS at the platform edge (Render does this).
- Set `CORS_ORIGINS` to the exact Pages URL(s).
- `/health` is liveness-only — it must never return pairing codes or tokens.
- Admin dashboard tokens expire after 24h; re-pair to rotate. Auth and pairing routes are rate-limited per client IP.
- Pairing codes are 6-digit secrets: treat them like one-time PINs and do not log them.
- After deploy, restart once so `ensure_admin_token_expiry_column` adds `expires_at` on existing DBs.
