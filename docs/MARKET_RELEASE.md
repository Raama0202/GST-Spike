# Market Release Guide — GST Expense Scanner SaaS

## What you are shipping

1. **Employee APK** — Google Play (`com.gstexpenses.gst_expense_scanner`)
2. **Admin Web** — Flutter web hosted on HTTPS (Cloudflare / Firebase Hosting / Nginx)
3. **Admin APK** (optional) — same Flutter admin project for Android tablets
4. **API + PostgreSQL** — Docker Compose or managed Postgres (RDS / Cloud SQL)

## Subscription packaging (suggested)

| Plan | Seats | Positioning |
|---|---|---|
| Starter | 10 | Small sites / single branch |
| Growth | 50 | Multi-site construction / aqua / F&B |
| Enterprise | Unlimited | Custom SLA, SSO later |

Billing can start as invoice-based (manual Super Admin extend) then add Razorpay/Stripe webhooks without changing the mobile apps.

## Pre-flight

- [ ] Rotate all seed passwords
- [ ] Set strong `JWT_SECRET`
- [ ] Disable `OTP_DEV_FIXED`; integrate SMS OTP (MSG91 / Twilio)
- [ ] Object storage (S3/GCS) if multi-node — swap `storage.py` backend
- [ ] TLS certificates on API + admin web
- [ ] Certificate pins for employee app (`CERT_PINS_SHA256`)
- [ ] Play Console Data Safety form (camera, photos, location optional)
- [ ] Backup Postgres daily
- [ ] Staged Play rollout 10% → 100%

## Build commands

### Employee AAB

```bash
flutter build appbundle --release ^
  --dart-define=API_BASE_URL=https://api.yourdomain.com/v1 ^
  --dart-define=ENV=production
```

### Admin Web

```bash
cd admin
flutter build web --release ^
  --dart-define=API_BASE_URL=https://api.yourdomain.com/v1
# Deploy build/web to CDN
```

### Admin Android (optional)

```bash
cd admin
flutter build appbundle --release ^
  --dart-define=API_BASE_URL=https://api.yourdomain.com/v1
```

### API

```bash
docker compose up -d --build
# or push backend image to your registry
```

## Go-live smoke test (30 minutes)

1. Super Admin creates company + plan → copy activation code  
2. Activate company  
3. Company Admin adds employee mobile  
4. Employee OTP login on phone  
5. Scan Vijayawada-style bill → review fields → submit  
6. Offline: airplane mode submit → sync when online  
7. Admin web: open invoice image, approve  
8. Employee: notification + Approved status  

## Support model

- Employees never contact Super Admin — Company Admin manages users  
- One APK forever — tenant config is server-driven  

## Legal / compliance notes

- Store invoice images for the retention period your customers require  
- GST data is sensitive financial data — encrypt at rest (disk / Postgres TDE)  
- Provide DPA for B2B customers  
