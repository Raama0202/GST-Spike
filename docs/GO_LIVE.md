# Go live — MongoDB Atlas + Render (+ free email OTP)

This puts the GST Expense Scanner online: the API and the web console on
Render, data on MongoDB Atlas, login codes by email through Brevo (Resend as a
fallback), and bill reading through Google Gemini. Every piece has a free tier.
Follow the steps in order; it takes about 30 minutes.

| Piece | Service | Free tier |
|---|---|---|
| Database + invoice images | MongoDB Atlas M0 | 512 MB |
| API + web console | Render | API sleeps after 15 min idle |
| Email codes (sign-up, password reset, employee login) | Brevo | 300 emails/day |
| Fallback email codes | Resend (optional) | 100/day, 3,000/month, needs your own domain |
| Bill reading (printed + handwritten) | Google Gemini | Free API key with daily limits |

SMS codes are optional and paid in India (DLT rules apply to every gateway,
and Firebase phone auth needs the paid Blaze plan). With email configured,
employees who have an email address get their login code by email; set an
email on each employee in **Employees**.

## 1. MongoDB Atlas

1. Sign up at [cloud.mongodb.com](https://cloud.mongodb.com) and create a free **M0** cluster
   (provider AWS, region **Mumbai (ap-south-1)** or Singapore).
2. **Database Access** → **Add New Database User** → password authentication.
   Use a generated password without `@ : / ? #` (or URL-encode it).
   Role: **Read and write to any database**.
3. **Network Access** → **Add IP Address** → **Allow access from anywhere** (`0.0.0.0/0`).
   Render's free plan has no fixed outbound IP; the database user's password protects the cluster.
4. **Database** → **Connect** → **Drivers** → copy the connection string and put the
   database name `gst_expenses` after the host:

   ```
   mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/gst_expenses?retryWrites=true&w=majority
   ```

   This is `MONGODB_URI`. Indexes and subscription plans are created automatically when the API starts.

## 2. Brevo (email codes)

1. Sign up at [brevo.com](https://www.brevo.com) (free plan).
2. **Senders, Domains & Dedicated IPs** → **Senders** → **Add a sender**. Use the address
   the codes should come from (a Gmail address works) and click the link Brevo emails to it.
   This address is `EMAIL_FROM`.
3. **SMTP & API** → **API Keys** → **Generate a new API key**. This is `BREVO_API_KEY`.

Optional fallback: sign up at [resend.com](https://resend.com), verify a domain you own,
and create an API key (`RESEND_API_KEY`). `EMAIL_FROM` must then be on that domain for
Resend to accept it. Leave it blank to use Brevo only.

Render's free plan blocks outgoing SMTP, so use these HTTPS providers rather than Gmail SMTP.

## 3. Gemini (bill reading)

Create a key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey). This is `GEMINI_API_KEY`.

An earlier key was shared in chat. Revoke it and create a new one. Keep keys only in
Render's environment settings; never commit them.

## 4. Deploy on Render

1. Push this repository to GitHub (private is fine).
2. In [dashboard.render.com](https://dashboard.render.com): **New** → **Blueprint** → choose the repo.
   Blueprint path: `render.yaml`.
3. Fill in the prompted values:

   | Variable | Value |
   |---|---|
   | `MONGODB_URI` | Step 1 |
   | `BREVO_API_KEY`, `EMAIL_FROM` | Step 2 |
   | `RESEND_API_KEY` | Step 2 (optional, blank is fine) |
   | `GEMINI_API_KEY` | Step 3 |
   | Everything else | Leave blank |

4. **Apply**. Render creates two services:
   - `gst-expense-scanner` — the API (`https://gst-expense-scanner.onrender.com`)
   - `gst-admin-console` — the web console (`https://gst-admin-console.onrender.com`)
5. Open `https://gst-expense-scanner.onrender.com/ready`. It should return `"status": "ok"` with `"database": "ok"`.

**If Render gave a service a different URL** (the name was taken), fix the links between them:

- API → **Environment**: set `CORS_ORIGINS` and `PUBLIC_WEB_URL` to the console URL.
- Console → **Environment**: set `VITE_API_BASE_URL` to `https://<api-url>/v1`.
- In `render.yaml`, replace `gst-expense-scanner.onrender.com` in the CSP header with the API host,
  push, and redeploy the console.

With `ENV=production` the API refuses to start when settings are unsafe (missing
`MONGODB_URI`, wildcard CORS, short `JWT_SECRET`, unknown email provider). The reason
is printed in the Render logs.

## 5. First accounts

**Register a firm.** Open the console → **Register your firm**. Enter the company name,
GSTIN, legal name, and the admin's name, email and password. A 6-digit code is emailed;
enter it to create the firm with a 14-day trial and land in the dashboard.

**Platform super admin** (optional, for managing all firms). Render's free plan has no shell,
so run this once from your computer against Atlas:

```powershell
cd backend
py -m pip install -r requirements.txt
$env:MONGODB_URI = "mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/gst_expenses?retryWrites=true&w=majority"
$env:SUPER_ADMIN_PASSWORD = "a-long-unique-password"
py -m app.cli create-super-admin --email you@example.com
```

## 6. Company identity (choosing the supplier on a bill)

A GST bill names two companies: the supplier and your firm (the buyer). The scanner picks
the one that is **not** your firm. It recognises your firm by:

- the GSTIN entered at registration, plus any **Additional GSTINs** (other states), and
- the company name, legal name, and any **Name aliases** (e.g. a short trading name).

Set these in the console under **Settings → Company identity**. When a bill shows only your
own firm, the supplier field is left empty for the employee to fill in.

## 7. Mobile apps

Rebuild the Android apps against the live API (PowerShell, repo root):

```powershell
$api = "https://gst-expense-scanner.onrender.com/v1"

# Employee app
flutter build apk --release --dart-define=API_BASE_URL=$api --dart-define=ENV=production

# Admin app
cd admin
flutter build apk --release --dart-define=API_BASE_URL=$api --dart-define=ENV=production
```

Employees sign in with their mobile number; the code goes to the email address on their
employee record. The employee app reads bills offline first and uses Gemini through the
API for the full extraction, including handwritten bills.

## 8. Before real customers

- [ ] `/ready` reports the database ok; Render logs show no configuration errors.
- [ ] Register a firm from the console; the code email arrives (check spam the first time).
- [ ] Sign out, sign in, and use **Forgot password** once.
- [ ] Add an employee with an email; sign in on the employee app; scan a printed bill and a handwritten bill.
- [ ] Confirm the supplier on the scanned bill is not your own firm.
- [ ] Approve the invoice in the console.
- [ ] Accept payments: follow section 9 and make one real ₹1 test purchase before announcing.

## 9. Accept payments (Razorpay)

Companies renew from **Billing** in the console (UPI, cards, net banking, wallets). A
successful payment extends the subscription instantly, issues a numbered GST invoice
(`GSTX/2026-27/00001`, printable from the payment history) and emails a receipt to the
admin who paid. Admins get renewal reminder emails 7, 3 and 1 days before expiry and on
the day it lapses (`RENEWAL_REMINDER_DAYS`).

**1. Fill in your business details** on the `gst-expense-api` service in Render. They are printed on every
invoice and on the public pages Razorpay reviews:

| Variable | Example |
|---|---|
| `BUSINESS_NAME` | `GST Expense` (brand shown in the console and checkout) |
| `BUSINESS_LEGAL_NAME` | `Expense Labs Private Limited` (as on your PAN / GST certificate) |
| `BUSINESS_GSTIN` | `29ABCDE1234F1Z5`. Leave empty if you are not GST-registered: no GST is charged and the document is titled "Invoice" |
| `BUSINESS_ADDRESS` | Registered address, one line |
| `BUSINESS_EMAIL`, `BUSINESS_PHONE` | Support contact shown on invoices and the Contact page |
| `BILLING_TAX_PERCENT` | `18` (charged only when `BUSINESS_GSTIN` is set) |
| `BILLING_SAC_CODE` | `997331` (licence to use software). Confirm with your CA |
| `BILLING_INVOICE_PREFIX` | `GSTX`, giving `GSTX/2026-27/00001`. Numbers restart every financial year |

Intra-state buyers (same state code as your GSTIN) are charged CGST + SGST; everyone else IGST.
The buyer's state comes from the GSTIN in their company settings.

**2. Public pages.** These need no login and are filled from the variables above. Use them in the
Razorpay activation form:

| Page | URL |
|---|---|
| Pricing | `https://gst-admin-console.onrender.com/#/pricing` |
| Contact us | `https://gst-admin-console.onrender.com/#/contact` |
| Terms & conditions | `https://gst-admin-console.onrender.com/#/terms` |
| Privacy policy | `https://gst-admin-console.onrender.com/#/privacy` |
| Refund & cancellation | `https://gst-admin-console.onrender.com/#/refund-policy` |
| Shipping / delivery | `https://gst-admin-console.onrender.com/#/shipping-policy` |

The texts are a sensible default for a prepaid B2B SaaS (7-day refund on a first purchase,
no auto-renewal). Read them once and edit `web-admin/src/pages/public/Public.tsx` if your
terms differ.

**3. Razorpay account.** Sign up at [dashboard.razorpay.com](https://dashboard.razorpay.com),
complete KYC (PAN, bank account, business proof) and submit the website URL above. Activation
usually takes 1–3 business days. Until then, you can test everything with test keys.

**4. Test mode first.** Dashboard → switch to **Test mode** → **Account & Settings → API keys →
Generate test key**. Set `RAZORPAY_KEY_ID` (`rzp_test_...`) and `RAZORPAY_KEY_SECRET` on the API.
Then **Account & Settings → Webhooks → Add new webhook**:

- URL: `https://gst-expense-scanner.onrender.com/v1/payments/razorpay/webhook`
- Secret: any long random string; put the same value in `RAZORPAY_WEBHOOK_SECRET`
- Active events: `payment.captured`, `payment.failed`, `order.paid`, `refund.processed`

Sign in as a company admin, open **Billing**, and pay with a
[test card](https://razorpay.com/docs/payments/payments/test-card-details/) or UPI ID
`success@razorpay`. Check: the subscription end date moves, the invoice opens and prints, the
receipt email arrives, and the payment shows under **Super admin → Payments**. The Billing page
shows a "Test mode" banner while test keys are set.

**5. Go live.** After activation, switch the dashboard to **Live mode**, generate live keys, add the
same webhook again in live mode (live and test webhooks are separate), and replace the three
variables with the live values. Render restarts the API automatically. The startup log stops
warning about test keys. Make one real small purchase (create a ₹1 plan under **Super admin →
Plans**, buy it, refund it from the Razorpay dashboard, then delete the plan) to see the whole loop,
including the refund appearing in **Payments**.

**Refunds** are made from the Razorpay dashboard (Payments → Refund). The webhook marks the
order "Refunded" (or shows the partial amount); the subscription is not shortened
automatically. Change its end date from the company page if needed.

**Safety built in:** payment signatures and webhook signatures are verified; a webhook whose
amount differs from the order is refused; each order credits the subscription exactly once even if
the checkout callback and webhook arrive together; and duplicate webhook deliveries are ignored.

### Launch-day checklist

- [ ] Render: API and console deployed, `/ready` OK, no "Configuration error" lines in the log.
- [ ] Atlas: IP access allows Render; backups configured (section 10, Backups).
- [ ] Email (Brevo) sends codes, receipts and reminders: `EMAIL_FROM` sender verified.
- [ ] `PUBLIC_WEB_URL` set to the console URL (links in receipts and reminders).
- [ ] Business variables filled in; the Contact page shows the right address and GSTIN.
- [ ] Plans and prices set under **Super admin → Plans** (`SIGNUP_TRIAL_DAYS` for the trial length).
- [ ] Razorpay live keys + live webhook set; one real purchase and refund done.
- [ ] Super admin password is strong and stored safely; the Gemini key from development rotated.
- [ ] Android APKs (`deploy/android/`) shared with customers, iOS builds via TestFlight.
- [ ] Your CA has confirmed the SAC code, GST rate and invoice format.

## 10. Optional services (add credentials when ready)

Every service below is already wired in. Each one stays off until its variables are set,
and the API logs a configuration warning at startup while it is off.

| Service | What it does | Where to set it |
|---|---|---|
| **Firebase Cloud Messaging** | Instant push alerts on the employee app (bill approved/returned, announcements) | API: `FCM_SERVICE_ACCOUNT_JSON`. Employee app build: Firebase `--dart-define`s (below) |
| **Sentry** | Error reports from the API and the web console | API: `SENTRY_DSN`. Console: `VITE_SENTRY_DSN` (rebuild the console) |
| **Backups** | Nightly logical backup of every collection to an S3-compatible bucket | GitHub secrets (workflow `backup.yml`) or the `gst-expense-backup` cron in `render.full-stack.yaml` |
| **Razorpay** | Online subscription payments, GST invoices, receipts (section 9) | API: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `BUSINESS_*` |
| **Cloudflare R2** | Invoice image storage beyond Atlas M0's 512 MB | API: `STORAGE_BACKEND=r2`, `R2_*` |
| **SMS OTP** | Login codes by SMS instead of email | API: `SMS_PROVIDER=msg91` or `twilio` and its keys |
| **Redis** | Shared rate limits and cache across several API instances | API: `REDIS_URL` |
| **GSTIN verification** | Live check of GSTINs against the GST portal (status, legal name, address) | API: `GSTIN_VERIFY_PROVIDER`, `GSTIN_VERIFY_API_KEY`, `GSTIN_VERIFY_API_SECRET` |

**GSTIN verification.** The GST portal (GSTN) does not hand out API keys to businesses; live
taxpayer search is only available through a GST Suvidha Provider (GSP). Pick one:

| Provider | Sign up | Variables |
|---|---|---|
| Sandbox (Zoop/Quicko group) | [developer.sandbox.co.in](https://developer.sandbox.co.in) → API keys | `GSTIN_VERIFY_PROVIDER=sandbox`, `GSTIN_VERIFY_API_KEY=key_live_...`, `GSTIN_VERIFY_API_SECRET=secret_live_...` |
| AppyFlow | [appyflow.in](https://appyflow.in) → GST verification API → key secret | `GSTIN_VERIFY_PROVIDER=appyflow`, `GSTIN_VERIFY_API_KEY=<key_secret>` |
| Any other GSP | Their dashboard | `GSTIN_VERIFY_PROVIDER=custom`, `GSTIN_VERIFY_BASE_URL=https://.../search?gstin={gstin}`, `GSTIN_VERIFY_API_KEY`, `GSTIN_VERIFY_KEY_HEADER` (default `x-api-key`) |

The custom provider must return the standard GSTN taxpayer fields (`lgnm`, `tradeNam`, `sts`,
`rgdt`, `pradr`…), which every GSP passes through. Results are cached for
`GSTIN_VERIFY_CACHE_HOURS` (24 hours; 1 hour for "not found") so repeat bills don't cost credits.

Once set:

- **Firm sign-up, company settings and super admin company forms** check the firm's GSTIN.
  A GSTIN the portal reports as cancelled or unknown is refused (set
  `GSTIN_VERIFY_ENFORCE_SIGNUP=false` to only warn). The legal name is filled in from the portal.
- **Every uploaded bill** has its supplier GSTIN checked in the background. Admins see the
  portal status and legal name on the bill, can filter the bill list by "GSTIN problem", and
  can re-check with **Verify with GST portal**. The export has a "Supplier GSTIN status" column.
- **The employee app** has a **Verify** button next to the GSTIN on the review screen.

Without a provider, everything still works: GSTINs are checked offline (format, state code and
checksum) and marked "Not verified".

**Firebase (push).**

1. In [console.firebase.google.com](https://console.firebase.google.com) create a project.
   Add an Android app with package `com.gstexpenses.gst_expense_scanner` (and an iOS app if you ship iOS).
2. **Project settings → Service accounts → Generate new private key**. Paste the whole JSON
   (or its base64) into the API's `FCM_SERVICE_ACCOUNT_JSON`.
3. Build the employee app with the app's Firebase values (Project settings → General):

   ```powershell
   flutter build apk --release --dart-define=API_BASE_URL=$api --dart-define=ENV=production `
     --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_PROJECT_ID=... `
     --dart-define=FIREBASE_SENDER_ID=... --dart-define=FIREBASE_ANDROID_APP_ID=... `
     --dart-define=FIREBASE_IOS_APP_ID=...
   ```

   Without these values the app still works and shows alerts when it next syncs.

**Backups.** Create a private bucket (R2 or any S3-compatible store), then add the GitHub
repository secrets `MONGODB_URI`, `BACKUP_BUCKET`, `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID` and
`R2_SECRET_ACCESS_KEY`. The `Backup` workflow runs nightly at 02:30 IST and keeps
`BACKUP_KEEP_DAYS` (14) days. Run it by hand from the **Actions** tab. To restore into an
empty database:

```powershell
cd backend
$env:MONGODB_URI = "mongodb+srv://..."
py -m app.cli restore --file backups\gst_expenses-YYYYMMDDTHHMMSSZ.tar.gz --yes
```

Add `--drop` only when you intend to replace existing data.

**Other settings worth knowing**

- `ENV` defaults to `production`. Local development needs `ENV=dev` in `backend/.env`
  (already in `.env.example`); otherwise the API enforces the production checks.
- `TRUSTED_PROXY_HOPS` (default `1`, correct for Render) is how many proxies sit in front of
  the API. Rate limits use the client address the outermost trusted proxy saw.
- `WEB_CONCURRENCY` sets the number of API worker processes (default 2).

## 11. Operating the platform

- **Super admin portal** (console, signed in as the platform admin): company list with plan,
  seats, usage and last activity; a company page to edit details, change plan, seats and end
  date, reset an admin's password, suspend or delete; revenue and signup metrics; and an
  audit log of every administrative action.
- **Company admins** can export bills to CSV or Excel, approve or return bills in bulk, edit
  extracted fields, and see who did what under **Activity**. **Settings → Delete company**
  permanently removes the firm and its data (required by the app stores).
- **CI** (`.github/workflows/ci.yml`) runs the API tests against MongoDB, builds the console,
  and analyses and tests both Flutter apps on every push and pull request.

## Limits of the free setup

- **Render free** sleeps after 15 minutes idle; the first request then takes about a minute.
  Change the API to `plan: starter` ($7/month) for always-on service.
- **Atlas M0** holds 512 MB, including invoice images (about 2,000–3,000 bills). For more,
  use Cloudflare R2 (10 GB free): set `STORAGE_BACKEND=r2` and the `R2_*` variables, then run
  `python -m app.cli migrate-uploads`. [`render.full-stack.yaml`](../render.full-stack.yaml)
  is the paid, always-on version with R2 and a nightly cleanup job.
- **Brevo free** sends 300 emails a day; add Resend or upgrade if you need more.
- **Gemini free** keys have per-minute and per-day limits; the API retries busy models and
  falls back between Flash models, but heavy use needs a billed key.

## GSTR-2A / 2B, reminders, GSP

- **GSTR import:** download the 2A/2B Excel from [gst.gov.in](https://www.gst.gov.in)
  (Returns → GSTR-2A/2B → Download) and import it under **ITC** in the console or admin app.
- **Reminders:** a supplier phone number opens WhatsApp (`wa.me`); otherwise an email draft opens,
  or the row goes to manual follow-up.
- **GSP:** set `GSP_BASE_URL`, `GSP_CLIENT_ID`, `GSP_CLIENT_SECRET` if you buy GSP access;
  Excel import keeps working as a fallback.
