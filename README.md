# GST-APP-IOS-ANDROID-WEB

Employee scanner (Android + iOS), company admin (Android + iOS), and the web super admin console, all on one FastAPI backend.

# GST Expense Scanner — Production SaaS Platform

One product. Three surfaces. Shared API. Subscription multi-tenant SaaS.

| Surface | Path | Audience |
|---|---|---|
| **Employee Android app** | `/` (Flutter) | Field staff — scan, OCR, submit |
| **Admin Android + Website** | `/admin` (Flutter Android/Web) | Company admin + Super admin |
| **API + Database** | `/backend` (FastAPI + PostgreSQL) | Source of truth |

## Verified

- OCR on real Vijayawada tax invoice (SRI VIJAYALAKSHMI ENTERPRISES) extracts vendor, GSTIN, invoice #, date, taxable, CGST/SGST, net amount
- Employee OTP → upload → admin approve → employee notification (backend e2e)
- Idempotent invoice upload (same key → same server id)
- Client unit/widget tests, admin tests, backend pytest — all green

## Quick start (local)

### 1. API + Postgres

```bash
# Preferred
docker compose up --build

# Or API only with SQLite for demos
cd backend
py -m pip install -r requirements.txt
set DATABASE_URL=sqlite+aiosqlite:///./dev.db
set OTP_DEV_FIXED=123456
set ENV=dev
py -m app.seed
uvicorn app.main:app --reload --port 8000
```

API docs: http://localhost:8000/docs  
Base URL for apps: `http://localhost:8000/v1`

### 2. Employee app

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
# Android emulator uses 10.0.2.2 to reach host localhost
```

Demo employee mobile: `9999999999` — OTP: `123456` (dev only)

### 3. Admin website

```bash
cd admin
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
```

### 4. Admin Android

```bash
cd admin
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

| Role | Login |
|---|---|
| Super admin | `admin@gstexpenses.app` / `ChangeMeNow!123` |
| Company admin | `acme@demo.com` / `DemoAdmin!123` |

**Change these passwords before any production deploy.**

## Subscription model

1. Super Admin creates a **plan** (Starter / Growth / Enterprise)
2. Super Admin creates a **company** → receives **activation code**
3. Company activates (or Super Admin activates) → subscription starts
4. Company Admin adds **employees** (mobile numbers)
5. Employees login via OTP on the single Play Store APK
6. Company config (categories, branches, theme) downloads automatically

Suspended / expired subscription blocks employee OTP and uploads.

## Sync path (client ↔ admin)

```
Employee Submit
   → local Hive queue (offline-safe)
   → POST /v1/invoices/upload (idempotencyKey)
   → Admin Dashboard pending count
   → Admin Approve/Reject/Return
   → Notification to employee
   → My Uploads status refresh
```

## Production release checklist

See [docs/MARKET_RELEASE.md](docs/MARKET_RELEASE.md).

Critical env vars:

```
DATABASE_URL=postgresql+asyncpg://...
JWT_SECRET=<32+ random bytes>
OTP_DEV_FIXED=          # empty in production — use SMS provider
CORS_ORIGINS=https://admin.yourdomain.com
STORAGE_PATH=/var/gst/uploads
ENV=production
```

## Tests

```bash
# Employee client
flutter test

# Admin
cd admin && flutter test

# API
cd backend && py -m pytest -q
```

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [API Contract](docs/API_CONTRACT.md)
- [Deployment](docs/DEPLOYMENT.md)
- [Testing](docs/TESTING.md)
- [Product decisions](docs/PRODUCT.md)
- [Backend README](backend/README.md)
- [Admin README](admin/README.md)
