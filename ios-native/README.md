# GST Expense — native iOS apps

Two native SwiftUI apps that mirror the two Flutter Android apps and talk to the
**same FastAPI backend (`/v1`)** that powers the super-admin web dashboard.
Nothing in `android/`, `admin/`, `backend/` or the dashboard was changed.

| iOS target   | Mirrors (Android)          | Bundle ID                            | Who uses it                     |
|--------------|----------------------------|--------------------------------------|---------------------------------|
| `GSTScanner` | `lib/` employee scanner    | `com.gstexpenses.gstexpensescanner`  | Employees (OTP login)           |
| `GSTAdmin`   | `admin/` admin app         | `com.gstexpenses.gstexpenseadmin`    | Company admins                  |

Super admin (companies, plans, subscriptions) lives only in the web dashboard (`web-admin/`);
both admin apps refuse super admin accounts.

All four apps (2 × Android, 2 × iOS) share one backend, one tenant model and one
dashboard. An invoice scanned on iOS appears in the dashboard and in both admin
apps exactly like one from Android — the multipart payload is byte-compatible.

## Requirements

- Xcode 16 or later (the project uses synchronized folders), iOS 17+ deployment
- An Apple developer team for device builds (set in *Signing & Capabilities*)

## Open & run

```
open ios-native/GSTExpense.xcodeproj
```

1. Select the **GSTScanner** or **GSTAdmin** scheme.
2. Set your Team for each target (Signing & Capabilities).
3. Run on a device (the document scanner needs a real camera; the simulator
   falls back to the photo picker).

Alternatively regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
`cd ios-native && xcodegen generate`.

### Backend URL

`API_BASE_URL` is a build setting (default `https://gst-expense-scanner.onrender.com/v1`)
injected into `Info.plist`. In **Debug** builds `ALLOW_SERVER_OVERRIDE = YES`, so the
login and profile screens show a server sheet where you can point the app at a
local backend (`http://192.168.x.x:8000` → `/v1` is appended automatically).
Release builds hide the override.

Dev demo login (seeded backend): mobile `9999999999`, OTP `123456`.

## Architecture

Same layering as the Flutter apps (Riverpod + Dio + Hive → Observation + URLSession + Keychain/files):

```
ios-native/
├── Shared/                    compiled into both apps
│   ├── Core/                  APIClient (bearer, X-Company-Id, X-Device-Id, single-flight refresh on 401),
│   │                          APIError, JSONValue, tolerant decoding, multipart, Keychain, ServerConfig
│   └── DesignSystem/          glassmorphism UI kit (see below)
├── EmployeeApp/
│   ├── App/                   @main, dependency container, floating tab shell
│   ├── Models/                InvoiceFields (same JSON keys as Android), LocalInvoice, Employee, config
│   ├── Data/                  SessionStore, InvoiceStore (offline queue), SyncEngine, TenantStorage,
│   │                          CompanyConfigModel, NotificationsModel, BackgroundSync, LocationProvider
│   ├── Scanner/               VisionKit scanner, CoreImage pipeline, Vision OCR, GST parser port, AI extract
│   └── Features/              Splash, Login/OTP, Home, Scan, Review, Uploads, Detail, Alerts, Profile
├── AdminApp/
│   ├── App/                   @main, AdminSession (company admins only), shell
│   ├── Data/                  AdminAPI (real backend routes), models, Keychain session store
│   └── Features/              Dashboard, Invoices + review, ITC, Team, Catalog, Announcements,
│                              Settings, Account
└── Config/                    Info.plists
```

### Employee app parity with Android

- OTP login (`/auth/otp/request`, `/auth/otp/verify`), "remember me", refresh-token rotation.
- Document scanner (edge detection + crop) → enhance → blur check → original / ≤1 MB compressed / 320 px thumbnail.
- Extraction: server AI (`/invoices/extract`) when available, otherwise on-device Vision OCR + the GST
  regex parser ported from Dart. Confidence = 0.45 × OCR + 0.55 × field score (same formula).
- Review form highlights fields OCR could not read, warns below the company's `minOcrConfidenceWarn`,
  checks duplicates locally and via `/invoices/duplicate-check`, captures GPS when `requiresGps`.
- **Submit never needs network**: the invoice is stored per tenant and queued. The sync engine uploads with
  the same idempotency key, retries with exponential backoff (2 s × 2ⁿ, max 8), runs every 15 s in the
  foreground and via `BGAppRefreshTask` in the background.
- Approval status, admin remarks and notifications are pulled from the dashboard
  (`/invoices/mine`, `/notifications`) and surfaced as local notifications + badge.
- Devices register with `platform: "ios"` (already accepted by the backend).

### Admin app

Signs in with email + password at `/admin/auth/login`. Only `company_admin` accounts are accepted;
a super admin gets a message pointing to the web dashboard.

- **Company admin** — Overview (Swift Charts donut, KPIs), invoice review (approve / reject / return with
  remarks; employees are notified on both platforms), ITC reconciliation (GSTR-2A/2B import, reconcile,
  WhatsApp / email reminders, manual follow-ups, CSV export), team CRUD, categories & branches,
  announcements with read counts, company settings (brand colour, GPS, duplicate check, OCR threshold,
  feature flags — pushed to every employee device on next sync).
- "Activate a new company" on the login screen calls the public `/super/companies/activate`.

## Glassmorphism design system

`Shared/DesignSystem` is the visual core of both apps:

- `GlassBackground` — slowly drifting blurred colour orbs over a light/dark gradient.
- `.glassCard()` — `ultraThinMaterial` surface, glossy diagonal sheen, gradient hairline border, soft shadow,
  optional colour tint.
- `FloatingTabBar` — frosted capsule tab bar with a matched-geometry selection pill and a raised
  gradient scan button.
- `GlassTextField`, `GlassChip`, `GlassToggleRow`, `StatusPill`, `StatTile`, `IconBadge`,
  `EmptyStateView`, `ErrorBanner`, shimmer skeletons and haptic toasts.
- The employee app re-tints itself with the tenant's `primaryColorHex`.

Every surface adapts to Light and Dark Mode.

## Before shipping

- Add 1024 × 1024 app icons to each `Resources/Assets.xcassets/AppIcon.appiconset`.
- Set `DEVELOPMENT_TEAM` and, if desired, a production `API_BASE_URL` per configuration.
- Push notifications: like Android, status updates use API polling + local notifications. APNs can be added
  later by sending the token in `fcmToken` on `/devices/register` (no API change needed).

## Notes on the existing Flutter admin app (not modified)

While mapping the backend contract, three paths in `admin/lib/core/constants.dart` were found not to match
the FastAPI routes. The iOS admin app uses the real routes; the Flutter app was left untouched as requested:

| Flutter constant | Flutter path            | Backend route                          |
|------------------|-------------------------|----------------------------------------|
| `categories`     | `/admin/categories`     | `/admin/company/categories`            |
| `branches`       | `/admin/branches`       | `/admin/company/branches`              |
| `announcements`  | `/admin/announcements`  | `/admin/notifications/announcements`   |
