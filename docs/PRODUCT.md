# Product decisions (critical review)

## Kept (business value)

| Feature | Why |
|---|---|
| OTP + JWT + refresh | Field staff cannot manage passwords; Admin provisions users |
| Scan → OCR → Review → Submit | Core value: <30s invoice capture |
| Offline queue + durable Hive | Sites have poor connectivity; never lose bills |
| Dynamic categories/config | Multi-industry SaaS without APK forks |
| Duplicate warn + override | Prevents double entry; override for legitimate repeats |
| OCR + edited audit pair | Accounting disputes need both originals |
| Single APK + companyId | Play Store operable SaaS |

## Removed / deferred for reliability

| Item | Decision |
|---|---|
| Custom OpenCV edge detect | Use ML Kit Document Scanner |
| Firebase hard dependency | Local notifications + API polling first; FCM documented |
| Isar | Hive CE encrypted (maintained) |
| Analytics / chat / ERP | Admin dashboard only |
| Mandatory GPS | Optional; never blocks submit |
| Fancy animations | Productivity UI only |

## Workflow improvement

Submit **always** persists locally first, then syncs. Network is never on the critical path for “done” from the employee’s perspective. Pending count on Home makes offline state visible without a complex dashboard.
