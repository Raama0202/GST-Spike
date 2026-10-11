# GST Expense Admin

Production Flutter admin client for company administrators and SaaS super
administrators. Android and web use the same source and REST repositories.

## Requirements

- Flutter 3.38+ with Dart 3.12+
- A running GST Expense API
- Chrome for web development or an Android device/emulator

## Install

```powershell
cd "C:\CA project\gst_expense_scanner\admin"
flutter pub get
```

The API base URL is compiled into the app with `--dart-define`. The default is
`http://localhost:8000/v1`.

## Run on web

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000/v1
```

For a physical API host, replace localhost with an address reachable by the
browser. The API must allow the web origin through CORS.

## Run on Android

Android emulators reach the host machine at `10.0.2.2`:

```powershell
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

For a physical Android device, use the host machine's LAN address and ensure
the API port is reachable.

## Production builds

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com/v1
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com/v1
```

JWTs and role information are stored through `flutter_secure_storage`.
Authenticated requests include a bearer token and, for company administrators,
the `X-Company-Id` header.
