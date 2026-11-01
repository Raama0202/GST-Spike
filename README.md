# GST Spike — GST Expense Scanner

A multi-tenant SaaS for Indian businesses to capture GST bills in the field, approve them in one
place, and claim the right input tax credit.

Employees photograph a bill (printed or handwritten) on their phone. AI reads the supplier,
GSTIN, invoice number, date, taxable value, CGST/SGST/IGST and invoice value. The bill syncs to
the company's admins, who review, correct, approve and export it, and match it against
GSTR-2A/2B. The platform owner runs everything from a super admin console and sells subscriptions
through Razorpay with automatic GST tax invoices.

| Surface | Folder | Built with | Who uses it |
|---|---|---|---|
| Employee app (Android + iOS) | [`/`](lib) | Flutter | Field staff: scan, review, submit, track |
| Admin app (Android + iOS) | [`/admin`](admin) | Flutter | Company admins on the go |
| Web console + super admin portal | [`/web-admin`](web-admin) | React + Vite + TypeScript | Firm sign-up, company admins, platform owner |
| API | [`/backend`](backend) | FastAPI + MongoDB | Single source of truth for every surface |
| Native iOS (experimental) | [`/ios-native`](ios-native) | SwiftUI | Optional native alternative to the Flutter apps |

---

## Features

**Employees (mobile)**
- Sign in with a one-time code by email or SMS. No passwords.
- Scan with edge detection; AI extraction handles printed and handwritten bills.
- On two-company bills, the supplier is picked automatically; your own firm is never recorded as the supplier.
- Works offline: bills queue on the device (encrypted) and sync with retries and back-off.
- Duplicate detection, live GSTIN verification, edit and resubmit returned bills.
- Push notifications when a bill is approved, rejected or returned.

**Company admins (web + mobile)**
- Dashboard with totals, trends, top categories and seat usage.
- Invoice queue with filters, search, sorting, bulk approve/reject/return, field correction and history.
- CSV / Excel export for accountants.
- GSTR-2A/2B import and ITC matching, with supplier reminders by WhatsApp or email.
- Employees, branches, categories, announcements, company identity (GSTINs, legal name, aliases).
- Activity log, billing and renewal, delete company.

**Platform owner (super admin)**
- Companies: create, activate, edit, change plan/seats, extend, suspend, reset admin passwords, delete.
- Plans and pricing, revenue and signup metrics, platform-wide audit log.
- Payments with filters, totals, refunds, CSV export and GST invoices.

**Billing (Razorpay)**
- UPI, cards, net banking and wallets. Signature-verified checkout and webhooks; each order credits once.
- Numbered GST tax invoices (`GSTX/2026-27/00001`), CGST+SGST or IGST by place of supply, emailed receipts.
- Refund tracking, renewal reminder emails (7, 3, 1 days before and on expiry).
- Public Pricing, Contact, Terms, Privacy, Refund and Delivery pages for Razorpay activation.

**Production basics**
- Rate limiting, login lockout, hashed passwords, rotating refresh tokens, signed media URLs.
- Structured logs, Sentry hooks, health and readiness checks, nightly backups.
- Every external service is optional and stays off until its credentials are set.

---

## Architecture

```
 Employee app ─┐                         ┌─ MongoDB Atlas (data, GridFS images)
 Admin app ────┼──► FastAPI  /v1  ───────┼─ Cloudflare R2 (optional image storage)
 Web console ──┘    (Render)             ├─ Gemini (bill reading)
                                         ├─ Brevo / Resend (email codes, receipts)
                                         ├─ MSG91 / Twilio (optional SMS)
                                         ├─ Razorpay (payments + webhooks)
                                         ├─ GSP provider (live GSTIN check)
                                         └─ Firebase Cloud Messaging (push)
```

Bill flow: **scan → on-device queue → `POST /v1/invoices/upload` (idempotent) → admin review →
notification → status on the employee's phone.**

More detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/API_CONTRACT.md](docs/API_CONTRACT.md)

---

## Repository layout

```
├── lib/, android/, ios/, test/     Employee Flutter app
├── admin/                          Admin Flutter app
├── web-admin/                      React web console (company admin + super admin)
├── backend/                        FastAPI API, tests, CLI (seed, backups, reminders)
├── ios-native/                     SwiftUI apps (experimental)
├── deploy/                         Ready-to-ship outputs (APKs, iOS, Super Admin Portal launcher)
├── scripts/                        Build, release and local-dev scripts
├── docs/                           Go-live, deployment, architecture, API, testing
├── render.yaml                     Render blueprint (API + static console)
├── render.full-stack.yaml          Render blueprint incl. backup cron
└── docker-compose.yml              Local MongoDB + API
```

---

## Quick start (local)

Requirements: Python 3.12+, Node 20+, Flutter stable with Dart 3.12+, MongoDB 7 (or Docker).

**1. API**

```bash
docker compose up --build            # MongoDB + seed + API on http://localhost:8000

# or, with MongoDB already running on 127.0.0.1:27017
cd backend
cp .env.example .env                 # ENV=dev for local work
python -m pip install -r requirements.txt
python -m app.seed
python -m uvicorn app.main:app --reload --port 8000
```

On Windows, `scripts\start_dev_api.ps1` starts MongoDB, seeds, and serves the API on your Wi-Fi
address so phones can reach it. API docs (dev only): http://localhost:8000/docs

**2. Web console**

```bash
cd web-admin
npm ci
npm run dev                          # http://localhost:5173 → http://localhost:8000/v1
```

**3. Employee app**

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1   # Android emulator → host
```

**4. Admin app**

```bash
cd admin
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

Development seed data (only when `ENV=dev`): super admin `admin@gstexpenses.app` / `ChangeMeNow!123`,
company admin `acme@demo.com` / `DemoAdmin!123`, employee mobile `9999999999`, one-time code `123456`.

---

## Deploy to production

Follow **[docs/GO_LIVE.md](docs/GO_LIVE.md)**. In short:

1. **MongoDB Atlas**: create a cluster and copy the connection string.
2. **Render**: create a Blueprint from this repo (`render.yaml`). It deploys the API and the web console.
3. **Set environment variables** on the API (full list in [`backend/.env.example`](backend/.env.example)):

   ```
   ENV=production
   MONGODB_URI=mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/gst_expenses
   JWT_SECRET=<32+ random characters>
   CORS_ORIGINS=https://<your-console>.onrender.com
   PUBLIC_WEB_URL=https://<your-console>.onrender.com
   EMAIL_PROVIDER=brevo            BREVO_API_KEY=...   EMAIL_FROM=...
   GEMINI_API_KEY=...
   RAZORPAY_KEY_ID=...             RAZORPAY_KEY_SECRET=...   RAZORPAY_WEBHOOK_SECRET=...
   BUSINESS_LEGAL_NAME=...         BUSINESS_GSTIN=...        BUSINESS_ADDRESS=...
   BUSINESS_EMAIL=...              BUSINESS_PHONE=...
   ```

4. **Create the super admin**: `python -m app.cli create-super-admin --email you@company.com`
   (password from `SUPER_ADMIN_PASSWORD`).
5. **Razorpay**: complete KYC, add the webhook
   `https://<api-host>/v1/payments/razorpay/webhook` (events `payment.captured`, `payment.failed`,
   `order.paid`, `refund.processed`), test with test keys, then switch to live keys.
   See section 9 of the go-live guide.

The API refuses to start in production with unsafe settings (default JWT secret, localhost
database, wildcard CORS) and logs a warning for each optional service that is still off.

---

## Ready-made builds

```powershell
# Android APKs (employee + admin) and the Super Admin Portal, pointed at your API
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ApiUrl https://<api-host>
```

| Output | Location |
|---|---|
| Employee app APK | `deploy/android/GST-Expense-Employee.apk` |
| Admin app APK | `deploy/android/GST-Expense-Admin.apk` |
| Super Admin Portal (double-click to run on Windows) | `deploy/SuperAdminPortal/Start-Super-Admin-Portal.bat` |
| iOS apps (needs a Mac) | `scripts/build_ios.sh` → `deploy/ios/` |

Build outputs and signing keys are not committed. The release script creates upload keystores
on first run (`android/upload-keystore.jks`, `admin/android/upload-keystore.jks`). **Back them up**:
Play Store updates must be signed with the same key. Install guides: [deploy/README.md](deploy/README.md).

---

## Optional services

Each one is already integrated and switches on when its variables are set:

| Service | Purpose | Variables |
|---|---|---|
| Razorpay | Subscription payments, GST invoices | `RAZORPAY_*`, `BUSINESS_*` |
| Gemini | AI bill reading (printed + handwritten) | `GEMINI_API_KEY` |
| Brevo / Resend | Email codes, receipts, reminders | `EMAIL_PROVIDER`, `BREVO_API_KEY`, `RESEND_API_KEY` |
| MSG91 / Twilio | SMS codes | `SMS_PROVIDER` + keys |
| GSP (Sandbox, AppyFlow, custom) | Live GSTIN verification | `GSTIN_VERIFY_*` |
| Firebase | Push notifications | `FCM_SERVICE_ACCOUNT_JSON` + app `--dart-define`s |
| Cloudflare R2 | Image storage beyond Atlas free tier | `STORAGE_BACKEND=r2`, `R2_*` |
| Redis | Shared cache / rate limits across instances | `REDIS_URL` |
| Sentry | Error reporting | `SENTRY_DSN`, `VITE_SENTRY_DSN` |
| Backups | Nightly dump to S3-compatible storage | `BACKUP_*`, `R2_*` |

---

## Tests

```bash
cd backend && python -m pytest -q     # API: 78 tests (needs MongoDB on 127.0.0.1:27017)
flutter test                          # Employee app
cd admin && flutter test              # Admin app
cd web-admin && npm run build         # Web console type-check + build
```

---

## Documentation

- [Go live: Atlas + Render + Razorpay](docs/GO_LIVE.md)
- [Deployment details](docs/DEPLOYMENT.md)
- [Architecture](docs/ARCHITECTURE.md)
- [API contract](docs/API_CONTRACT.md)
- [Testing](docs/TESTING.md)
- [Market release (Play Store / App Store)](docs/MARKET_RELEASE.md)
- [Product decisions](docs/PRODUCT.md)
- [Install the ready-made builds](deploy/README.md)
- [Backend](backend/README.md) · [Admin app](admin/README.md) · [Native iOS](ios-native/README.md)

## Security

Never commit `.env` files, keystores, `key.properties`, `google-services.json` or API keys; they
are git-ignored. Rotate any credential that has been shared in chat or email. Report security
issues privately to the repository owner.
