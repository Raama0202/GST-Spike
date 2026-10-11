# Deployment Guide

## 1. Backend

Deploy an API that implements [API_CONTRACT.md](API_CONTRACT.md).

Checklist:

- [ ] OTP SMS provider configured
- [ ] JWT access + refresh rotation
- [ ] Multi-tenant row filters on every query (`company_id`)
- [ ] Object storage for original / compressed / thumbnail
- [ ] Idempotent upload by `idempotencyKey`
- [ ] Admin dashboard can view images + OCR vs edited audit fields

## 2. Android signing

1. Create upload keystore (keep offline backup).
2. Create `android/key.properties` (gitignored):

```properties
storePassword=***
keyPassword=***
keyAlias=gst_upload
storeFile=C:/secure/gst-upload.jks
```

3. Wire signing in `android/app/build.gradle.kts` release config (replace debug signing).

## 3. Build App Bundle

```bash
flutter clean
flutter pub get
flutter build appbundle --release ^
  --dart-define=API_BASE_URL=https://api.yourdomain.com/v1 ^
  --dart-define=ENV=production
```

Output: `build/app/outputs/bundle/release/app-release.aab`

## 4. Play Console

1. Create application **GST Expense Scanner**
2. Package: `com.gstexpenses.gst_expense_scanner`
3. Content rating, Data safety (camera, photos, location optional, encrypted local storage)
4. Upload AAB to internal testing → closed → production
5. Required permissions rationale: Camera (scan bills), Notifications (approval status), Location (optional GPS)

## 5. Environments

| Env | API_BASE_URL | Notes |
|---|---|---|
| staging | `https://staging-api.../v1` | Enable network logging |
| production | `https://api.../v1` | Pins optional via `CERT_PINS_SHA256` |

CI builds should inject defines as secrets — never hardcode.

## 6. Optional FCM cutover

Local notifications + API polling ship by default.

To add FCM later:

1. Add Firebase Android app / `google-services.json`
2. Add `firebase_messaging` dependency
3. Send `fcmToken` in `/devices/register`
4. Keep existing notification types unchanged

## 7. Ops monitoring

Watch:

- Upload failure rate / queue depth per tenant
- OCR confidence distribution
- OTP success rate
- 401 refresh failures (token rotation bugs)

## 8. Rollback

Play Console staged rollout (10% → 50% → 100%). Keep previous AAB active for emergency halt.
