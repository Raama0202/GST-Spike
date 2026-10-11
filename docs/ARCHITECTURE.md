# Architecture Decisions — GST Expense Scanner

## Critical requirement review

The master prompt was reduced where complexity hurt reliability:

| Removed / deferred | Why |
|---|---|
| Custom OpenCV edge detection | Google ML Kit Document Scanner is production-hardened, maintained, and offline-capable. |
| Hard Firebase dependency | App must compile without `google-services.json`. Status notifications use API polling + local notifications. FCM is documented for production cutover. |
| Isar | Isar 3 is effectively unmaintained. **Hive CE** with AES encryption key in secure storage is the durable offline store. |
| Fancy analytics / charts / chat | Explicitly out of scope for the field employee client. |
| Multi-APK per tenant | Forbidden. One APK; tenant isolation via `X-Company-Id` + JWT claims. |

## Product principle applied to workflow

Primary path stays: **Login → Home → Scan → OCR → Review → Submit → Sync → Done**.

Improvements that increase reliability without adding screens:

1. **Submit never requires network.** Persist first, enqueue, then sync.
2. **OCR confidence gate.** Low confidence highlights fields; does not block submit.
3. **Duplicate warn-before-submit.** Local + server check; override requires explicit confirm.
4. **Session restore.** Refresh token rotation on cold start before any protected call.
5. **Config refresh on login and every successful sync.** Categories/branches never need a Play Store update.

## Layering

```
Presentation (Riverpod + Screens)
        ↓
Domain (entities, repository contracts, use cases)
        ↓
Data (API, Hive, file system)
        ↓
Core (Dio, security, theme, errors)
```

Feature-first folders under `lib/features/*`. Shared kernels under `lib/core` and `lib/shared`.

## Multi-tenant SaaS

- Single application ID: `com.gstexpenses.gst_expense_scanner`
- After OTP verify, tokens + `companyId` + employee profile are stored encrypted
- Every Dio request attaches `Authorization` and `X-Company-Id`
- Local Hive boxes are namespaced by `companyId` so device re-login to another tenant cannot leak prior rows

## Offline & sync

- Invoice rows live in Hive with `syncStatus`: pending | uploading | uploaded | failed
- Binary files: original / compressed / thumbnail under app documents, keyed by invoice local UUID
- Sync engine: connectivity listener + WorkManager periodic task + manual Sync button
- Idempotency key = local UUID (server dedupes)
- Interrupted uploads resume via multipart upload session id when server returns one; otherwise full retry with same idempotency key

## OCR

1. ML Kit Document Scanner → cropped page image
2. Image enhance (contrast, mild shadow lift) + blur score
3. ML Kit Text Recognizer (Latin script, on-device)
4. GST invoice field parser (regex + line heuristics for Indian GSTIN / tax lines)
5. Persist original OCR JSON + user edits separately for audit

## Security

- Tokens only in `flutter_secure_storage` (EncryptedSharedPreferences / Keystore)
- Hive encryption key (32 bytes) generated once, stored in secure storage
- No API secrets in source; base URL via `--dart-define=API_BASE_URL=...`
- Certificate pinning hook in `CertificatePinningAdapter` — pins empty until ops supplies SPKI hashes

## Performance budgets

- Cold start target < 2s on mid-range Android (deferred OCR/camera init)
- Upload image ≤ ~1 MB JPEG quality adaptive
- List screens use lazy builders; thumbnails only in lists
