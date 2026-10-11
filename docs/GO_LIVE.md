# Go live — Neon (free Postgres) + Render (free HTTPS API)

This turns the GST Expense Scanner into a public SaaS backend so any phone
can use the Client and Admin apps. Follow the steps in order.

## 1. Create a free Neon database

1. Open [https://console.neon.tech](https://console.neon.tech) and sign up.
2. Create a project (region closest to India, e.g. Singapore/Mumbai if offered).
3. Open **Connection details** → copy the **pooled** connection string.
4. It looks like:
   `postgresql://user:pass@ep-xxxxx.aws.neon.tech/neondb?sslmode=require`
5. Convert it for this app by ensuring the scheme is async-friendly later — paste
   the original URL into Render as `DATABASE_URL`. The API auto-rewrites
   `postgresql://` → `postgresql+asyncpg://`.

## 2. Rotate your Gemini key (important)

You previously shared an API key in chat. Revoke it in Google AI Studio / Cloud
Console, create a new key, and keep it only for Render env vars — never commit it.

## 3. Deploy the API on Render

### Option A — Blueprint (recommended)

1. Push this repository to GitHub (private is fine).
2. Open [https://dashboard.render.com](https://dashboard.render.com) → **New** → **Blueprint**.
3. Connect the repo and set **Blueprint Path** to [`render.full-stack.yaml`](../render.full-stack.yaml). (The default `render.yaml` only deploys the free web console static site.)
4. When prompted, set:
   - `DATABASE_URL` = Neon connection string from step 1
   - `GEMINI_API_KEY` = your new Gemini key
5. Deploy. Wait until the service is **Live**.
6. Copy the service URL, e.g. `https://gst-expense-api.onrender.com`.

### Option B — Manual Web Service

1. **New** → **Web Service** → connect repo.
2. Root directory: `backend`
3. Build: `pip install -r requirements.txt`
4. Start: `alembic upgrade head && python -m app.seed && uvicorn app.main:app --host 0.0.0.0 --port $PORT`
5. Add the same env vars as in `render.full-stack.yaml`.
6. Attach a small persistent disk at `/var/data` if you want invoice images to survive restarts (free plan disk is limited).

Health check: open `https://YOUR-SERVICE.onrender.com/health` → `{"status":"ok"}`.

## 4. Demo logins (after seed)

| Role | Login |
|---|---|
| Employee (client app) | Mobile `9999999999` / OTP `123456` (dev OTP while `OTP_DEV_FIXED` is set) |
| Company admin | `acme@demo.com` / `DemoAdmin!123` |
| Super admin | `admin@gstexpenses.app` / `ChangeMeNow!123` |

**Before real customers:** change passwords, remove `OTP_DEV_FIXED`, and set a long random `JWT_SECRET`.

## 5. Rebuild Android APKs against the live URL

From the repo root (PowerShell):

```powershell
$api = "https://YOUR-SERVICE.onrender.com/v1"

# Client
flutter build apk --release --target-platform=android-arm64 --no-tree-shake-icons `
  --dart-define=API_BASE_URL=$api `
  --dart-define=ENV=production `
  --dart-define=ALLOW_SERVER_OVERRIDE=true
Copy-Item build\app\outputs\flutter-apk\app-release.apk dist\apk\GST_Expense_Scanner_Client_Live.apk -Force

# Admin
cd admin
flutter build apk --release --target-platform=android-arm64 --no-tree-shake-icons `
  --dart-define=API_BASE_URL=$api `
  --dart-define=ENV=production `
  --dart-define=ALLOW_SERVER_OVERRIDE=true
Copy-Item build\app\outputs\flutter-apk\app-release.apk ..\dist\apk\GST_Expense_Admin_Live.apk -Force
```

Install the `*_Live.apk` files on phones. Client and Admin share the same Neon database, so scans sync to the admin invoice list automatically.

Free Render services spin down after idle time — the first request after sleep can take ~30–60s.

## 6. Download GSTR-2A / 2B Excel from GST portal

1. Login to [https://www.gst.gov.in](https://www.gst.gov.in) as the taxpayer / CA.
2. Go to **Returns** → **GSTR-2A** or **GSTR-2B** for the month.
3. Use **Download** / **Excel** (or CSV if offered).
4. In **Admin app → ITC**, set period `YYYY-MM`, choose 2A or 2B, tap **Import Excel/CSV**.
5. Review match cards: **Missing in 2B** = chase supplier; **Missing in books** = scan the missing bill.

## 7. Reminders (free path)

- If the bill has a phone number (from AI extract), **Remind** opens WhatsApp via `wa.me` — you tap Send.
- If only email exists, a `mailto:` draft opens.
- If neither exists, the row goes to **Manual follow-up** for a phone call.

Fully automatic WhatsApp blasts need a paid Meta Business / BSP account — not included in the free tier.

## 8. Optional SMTP (real outbound email)

Add to Render env:

```
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=you@gmail.com
SMTP_PASSWORD=app-password
SMTP_FROM=you@gmail.com
```

Create a Gmail [App Password](https://myaccount.google.com/apppasswords). Without SMTP, email reminders still work via the device `mailto:` link.

## 9. Optional paid GSP later

When you buy WhiteBooks / Sandbox / another GSP:

```
GSP_BASE_URL=https://api.your-gsp.example
GSP_CLIENT_ID=...
GSP_CLIENT_SECRET=...
```

The API exposes `GET /v1/admin/itc/status` → `portalApiConfigured: true`. Excel upload remains available as fallback.

## 10. Smoke test checklist

- [ ] `/health` returns ok
- [ ] Client login with demo mobile + OTP
- [ ] Scan a bill → AI extract → submit
- [ ] Admin sees invoice → approve
- [ ] Admin ITC import sample 2B CSV → match counts update
- [ ] Remind on a missing-in-2B row opens WhatsApp or lands in manual queue
