# GST Expense Scanner API

FastAPI backend for the multi-tenant GST Expense Scanner SaaS. It serves the
Android and iOS employee apps, the Android and iOS admin apps, and the React
admin console.

## Local development

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
cp .env.example .env          # defaults are fine for local work
alembic upgrade head
python -m app.seed            # plans + demo tenant (demo data is skipped when ENV=production)
uvicorn app.main:app --reload
```

API: `http://localhost:8000/v1` · Docs: `http://localhost:8000/docs` (disabled in production) ·
Liveness: `/health` · Readiness (DB, Redis, R2): `/ready`

### Seed credentials (development only)

- Super admin: `admin@gstexpenses.app` / `ChangeMeNow!123`
- Demo company admin: `acme@demo.com` / `DemoAdmin!123`
- Demo employee: `9999999999` / OTP `123456`
- Demo activation code: `ACME-DEMO-2026`

None of these are created when `ENV=production`.

## Tests and load test

```bash
pytest -q                                    # SQLite, no Postgres/Redis needed
locust -f loadtest/locustfile.py --host https://staging-api.example.com
```

See `loadtest/README.md` for load-test credentials and targets.

## Production architecture

| Concern | How it is handled |
| --- | --- |
| Concurrency | gunicorn + uvicorn workers (`gunicorn.conf.py`), Render auto-scaling 2→4 instances |
| Database | Postgres with pooled connections, 15 s statement timeout, composite indexes for list/dashboard queries |
| Shared state | Redis (Render Key Value) for rate limits, login lockout and the 30 s auth/subscription cache; fails open if Redis blips |
| Images | Cloudflare R2, private bucket, 15-minute presigned URLs; uploads are checked by magic bytes (JPEG/PNG/WebP, 15 MB) |
| Abuse limits | per-IP flood limit, per-user API limit, login limit + lockout, OTP limits per number and per IP, request body cap |
| Errors | every response has `X-Request-Id`; unhandled errors return JSON `{message, requestId}` with CORS headers; Sentry optional |
| Logs | one JSON object per line with `requestId`, method, path, status and duration |
| Big imports | GSTR files are parsed off the event loop; files above 3,000 rows finish in the background |
| Payments | Razorpay orders, checkout signature verification, signed and de-duplicated webhooks, idempotent subscription credit |

## Production deploy checklist

1. **Create R2 storage.** In Cloudflare, go to R2 and create a private bucket. Then create an API token with Object Read & Write access to that bucket. Note the account ID, access key, secret and bucket name.
2. **Apply the Render blueprint.** In Render, go to **New → Blueprint**, choose this repository, set **Blueprint Path** to `render.full-stack.yaml`, and apply it. It creates the Postgres database, Key Value (Redis), the API, the static admin console, and the cleanup cron.
3. **Fill in the prompted variables**:
   - `CORS_ORIGINS`: the console URL, e.g. `https://gst-admin-console.onrender.com` plus your custom domain.
   - The four `R2_*` values.
   - `SENTRY_DSN`: recommended.
   - `GEMINI_API_KEY`.
   - `SMS_PROVIDER` and its keys, when chosen.
   - The three `RAZORPAY_*` values, when ready.
4. **First deploy.** `preDeployCommand` runs the migrations and seeds the plans. The API refuses to boot if the JWT secret, CORS, R2 or Redis settings are unsafe; the deploy log lists exactly which ones.
5. **Create the super admin.** Open a Render shell on the API service and run:
   ```bash
   SUPER_ADMIN_PASSWORD='a-long-unique-password' python -m app.cli create-super-admin --email you@company.com
   ```
6. **Move existing images (only when migrating an old disk-based deploy).** With the `R2_*` values set, run `python -m app.cli migrate-uploads`.
7. **Set up SMS for employee OTP.** Choose MSG91 (India, DLT template) or Twilio, then set the matching variables. Until then, `POST /v1/auth/otp/request` returns 503 with a clear message.
8. **Set up Razorpay**:
   - Set `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` and `RAZORPAY_WEBHOOK_SECRET`.
   - In the Razorpay dashboard, add the webhook `https://<api-host>/v1/payments/razorpay/webhook` with the events `payment.captured`, `order.paid` and `payment.failed`.
   - Test with `rzp_test_` keys first.
9. **Point the mobile apps at production.** Build them with the production API URL (see each app's README). Android release builds need `android/key.properties` (see `android/key.properties.example`).
10. **Verify the deploy**:
    - `GET /ready` returns `{"status":"ok"}`.
    - Sign in on the console.
    - Upload a bill from a phone and confirm the image loads; it should come from an `r2.cloudflarestorage.com` URL.
    - Run a short Locust test against staging.

### Running outside Render

`docker build -t gst-api backend && docker run --env-file backend/.env -p 8000:8000 gst-api`. The image runs as a non-root user and does not migrate on start. Run `docker run --env-file backend/.env gst-api alembic upgrade head` once per release.

## Tenant and upload behaviour

Company-scoped queries always use the authenticated token's `company_id`; a conflicting
`X-Company-Id` header is rejected. Employee access is also scoped by `employee_id`.
Stored images are never publicly listable. With R2, clients receive presigned URLs. With local
storage (development only), they receive `/v1/media/...` links signed with HMAC that expire
after `SIGNED_URL_SECONDS`.

## AI invoice extraction

`POST /v1/invoices/extract` accepts a JPEG, PNG or WebP image and returns structured GST fields. Without
`GEMINI_API_KEY`, `GET /v1/invoices/extract/status` reports `{"available": false}` and clients fall back
to on-device OCR.
