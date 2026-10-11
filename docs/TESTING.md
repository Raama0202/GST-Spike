# Testing Guide

## Commands

```bash
flutter test
flutter analyze
flutter test test/unit
flutter test test/widget
```

## Coverage map

| Area | Location |
|---|---|
| GST OCR parser | `test/unit/gst_invoice_parser_test.dart` |
| Invoice audit model | `test/unit/invoice_entity_test.dart` |
| Upload queue JSON | `test/unit/upload_queue_test.dart` |
| Offline recovery | `test/unit/offline_recovery_test.dart` |
| Auth contract | `test/unit/auth_repository_contract_test.dart` |
| Login UI smoke | `test/widget/login_screen_test.dart` |

## Manual device checklist

1. OTP login with remember-me; kill app; cold start restores session  
2. Airplane mode → scan → submit → pending count increments  
3. Restore network → Sync → status becomes Uploaded  
4. Kill mid-upload → reopen → queue recovers  
5. Blurry photo → blur warning → retake  
6. Duplicate invoice → warning → override submit  
7. Low OCR confidence → fields highlighted, submit still allowed  
8. Logout clears session; tenant boxes isolated on next login  

## CI

GitHub Actions workflow `.github/workflows/ci.yml` runs analyze, test, and Android APK build on push/PR.
