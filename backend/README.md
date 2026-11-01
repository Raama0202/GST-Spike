# GST Expense Scanner API

FastAPI backend for the multi-tenant GST Expense Scanner SaaS. It serves the
Android and iOS employee apps, the Android and iOS admin apps, and the React
admin console. Data lives in MongoDB (Atlas in production).

## Local development

Needs Python 3.12 and a MongoDB on `127.0.0.1:27017`
(`docker run -d -p 27017:27017 mongo:8`, MongoDB Community, or an Atlas `MONGODB_URI`).

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env          # defaults are fine for local work
python -m app.seed            # indexes + plans + demo tenant (demo data is skipped when ENV=production)
uvicorn app.main:app --reload
```

On Windows, `scripts\start_dev_api.ps1` does all of this and starts a portable MongoDB
from `backend\.mongo` when one is unpacked there.

API: `http://localhost:8000/v1` · Docs: `http://localhost:8000/docs` (disabled in production) ·
Liveness: `/health` · Readiness (database, Redis, R2): `/ready`

Outside production every one-time code is `OTP_DEV_FIXED` (`123456`) and emails are printed
to the log (`EMAIL_PROVIDER=console`).

### Seed credentials (development only)

- Super admin: `admin@gstexpenses.app` / `ChangeMeNow!123`
- Demo company admin: `acme@demo.com` / `DemoAdmin!123`
- Demo employee: `9999999999` / OTP `123456`
- Demo activation code: `ACME-DEMO-2026`

None of these are created when `ENV=production`.

## Tests and load test

```bash
pytest -q        # needs MongoDB on 127.0.0.1:27017 (or TEST_MONGODB_URI); each test uses a throwaway database
locust -f loadtest/locustfile.py --host https://staging-api.example.com
```

See `loadtest/README.md` for load-test credentials and targets.

## Accounts and one-time codes

| Flow | Endpoints | Code delivery |
| --- | --- | --- |
| Firm sign-up | `GET /v1/admin/auth/register/options`, `POST /v1/admin/auth/register`, `/register/resend`, `/register/verify` | Email to the admin |
| Admin login | `POST /v1/admin/auth/login`, `/refresh` | Password |
| Password reset | `POST /v1/admin/auth/password/forgot`, `/password/reset` | Email |
| Employee login | `POST /v1/auth/otp/request`, `/otp/verify` | Email when the employee has one (`EMPLOYEE_OTP_CHANNEL=auto`), else SMS |

Email goes through `EMAIL_PROVIDER`, a fallback chain such as `brevo,resend` (both free and HTTPS,
which Render's free plan needs because it blocks SMTP). SMS (`msg91`, `twilio`) is optional and paid.
Codes are stored hashed, expire after `OTP_TTL_MINUTES`, and are rate-limited per address and per IP.

A verified sign-up creates the company, the admin user, a `SIGNUP_TRIAL_DAYS` trial, a
"Head Office" branch and the default expense categories.

## Production architecture

| Concern | How it is handled |
| --- | --- |
| Concurrency | gunicorn + uvicorn workers (`gunicorn.conf.py`); scale instances on Render |
| Database | MongoDB Atlas; indexes and plans are created on start (`python -m app.cli init-db` does the same); TTL indexes expire codes and sign-up requests |
| Shared state | Rate limits, login lockout and the 30 s auth cache in MongoDB (`CACHE_BACKEND=mongo`) or Redis; fail open on errors |
| Images | GridFS in the same Atlas database (free) or Cloudflare R2; private, served through short-lived signed URLs; uploads checked by magic bytes |
| Abuse limits | per-IP flood limit, per-user API limit, login limit + lockout, OTP limits per address and per IP, request body cap |
| Errors | every response has `X-Request-Id`; unhandled errors return JSON `{message, requestId}` with CORS headers; Sentry optional |
| Logs | one JSON object per line with `requestId`, method, path, status and duration |
| Big imports | GSTR files are parsed off the event loop; files above 3,000 rows finish in the background |
| Payments | Razorpay orders, checkout signature verification, signed and de-duplicated webhooks, idempotent subscription credit |

With `ENV=production` the API refuses to start when settings are unsafe (JWT secret, CORS,
`MONGODB_URI`, storage, email provider); the log lists each problem.

## Deploying

- **Free (MongoDB Atlas + Render + Brevo):** follow [docs/GO_LIVE.md](../docs/GO_LIVE.md) with the
  root [`render.yaml`](../render.yaml).
- **Always-on:** [`render.full-stack.yaml`](../render.full-stack.yaml) runs the API on a paid
  plan with auto-scaling, Cloudflare R2 for images and a nightly cleanup job.
- **Super admin:** `SUPER_ADMIN_PASSWORD='...' python -m app.cli create-super-admin --email you@company.com`
  (run it anywhere with `MONGODB_URI` pointing at the production database).
- **Razorpay:** set the three `RAZORPAY_*` values and add the webhook
  `https://<api-host>/v1/payments/razorpay/webhook` for `payment.captured`, `order.paid` and `payment.failed`.
- **Docker:** `docker build -t gst-api backend && docker run --env-file backend/.env -p 8000:8000 gst-api`.
  The image runs as a non-root user. `docker compose up --build` at the repo root starts MongoDB, seeds it, and runs the API.

## Tenant and upload behaviour

Company-scoped queries always use the authenticated token's `company_id`; a conflicting
`X-Company-Id` header is rejected. Employee access is also scoped by `employee_id`.
Stored images are never publicly listable. With R2, clients receive presigned URLs. With GridFS or
local storage, they receive `/v1/media/...` links signed with HMAC that expire after `SIGNED_URL_SECONDS`.

## AI invoice extraction

`POST /v1/invoices/extract` accepts a JPEG, PNG or WebP image (printed or handwritten) and returns
structured GST fields. Gemini reads the bill; the API then:

- picks the supplier: of the two companies on a GST bill, the one that is not the scanning firm
  (matched by its GSTINs, PAN, legal name and name aliases from company settings);
- repairs common OCR mistakes in GSTINs and checks their checksum;
- cross-checks the total against the amount in words and against the line items on handwritten
  bills, and lowers the confidence with a note when they disagree;
- retries busy models and falls back between Flash models.

Without `GEMINI_API_KEY`, `GET /v1/invoices/extract/status` reports `{"available": false}` and clients
fall back to on-device OCR.
