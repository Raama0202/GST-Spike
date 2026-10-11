# Ready-to-install APKs

| File | App | Size | Use when |
|---|---|---|---|
| `GST_Expense_Scanner_Client_Live.apk` | Employee | ~56 MB | After Neon+Render go-live (or paste server URL) |
| `GST_Expense_Admin_Live.apk` | Admin | ~19 MB | After Neon+Render go-live (includes ITC screen) |
| `GST_Expense_Scanner_Client_Demo.apk` | Employee | ~56 MB | Demo over Cloudflare tunnel |
| `GST_Expense_Admin_Demo.apk` | Admin | ~19 MB | Demo over Cloudflare tunnel |
| `GST_Expense_Scanner_Client_LAN.apk` | Employee | ~56 MB | Same Wi-Fi as this PC only |
| `GST_Expense_Admin_LAN.apk` | Admin | ~19 MB | Same Wi-Fi as this PC only |
| `GST_Expense_Scanner_Client.apk` | Employee | ~56 MB | Production domain is live |
| `GST_Expense_Admin.apk` | Admin | ~19 MB | Production domain is live |

## Demo over the internet (recommended for client demos)

1. Start the API and tunnel on this PC:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start_demo_tunnel.ps1
```

2. Copy the `https://….trycloudflare.com` URL that cloudflared prints.
3. Install `GST_Expense_Scanner_Client_Demo.apk` (or the Admin Demo APK).
4. On the login screen, tap **Server: …**, paste the tunnel URL, and Save.
   The dialog accepts a bare host; the app adds `https://` and `/v1`.
5. Log in with the credentials below.

The Demo builds ship with `ALLOW_SERVER_OVERRIDE=true`, so a new tunnel URL does
not require rebuilding the APK. Quick tunnels get a fresh hostname every restart —
always paste the new one into the Server dialog.

**Caveat:** Cloudflare quick tunnels have no uptime guarantee and the hostname
changes on every restart. Use them for demos, not for paying customers.

## Live hosting (Neon + Render)

Step-by-step: [`docs/GO_LIVE.md`](../../docs/GO_LIVE.md)

After Render gives you `https://YOUR-SERVICE.onrender.com`, rebuild:

```powershell
$api = "https://gst-expense-scanner.onrender.com/v1"
flutter build apk --release --target-platform=android-arm64 --no-tree-shake-icons `
  --dart-define=API_BASE_URL=$api --dart-define=ALLOW_SERVER_OVERRIDE=true
```

Current Live APKs target **https://gst-expense-scanner.onrender.com/v1**.

## ITC (Admin)

Admin → **ITC**: import GSTR-2A/2B Excel from gst.gov.in, match scanned bills, remind suppliers via WhatsApp/email, or queue manual follow-up.

## Demo logins (API must be running)

| App | Login |
|---|---|
| Client | Mobile `9999999999` / OTP `123456` |
| Admin | `acme@demo.com` / `DemoAdmin!123` |
| Super Admin | `admin@gstexpenses.app` / `ChangeMeNow!123` |
| Activation code | `ACME-DEMO-2026` |

Add your own mobile as a demo employee:

```powershell
cd backend
$env:DATABASE_URL = "sqlite+aiosqlite:///./dev.db"
py add_employee.py YOUR_10_DIGIT_MOBILE --name "Your Name"
```

Then request an OTP in the app; the API console prints the development OTP.

## LAN-only testing

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start_dev_api.ps1
```

Phone and PC must be on the same Wi-Fi. Confirm
`http://192.168.29.21:8000/health` opens in the phone's browser before installing
the `_LAN` APKs.

## Production builds

Point DNS at a real host with TLS, then rebuild:

```bash
flutter build apk --release --target-platform=android-arm64 --no-tree-shake-icons \
  --dart-define=API_BASE_URL=https://api.YOURDOMAIN/v1 \
  --dart-define=ENV=production
```

Do **not** pass `ALLOW_SERVER_OVERRIDE=true` for Play Store builds.

## Notes

- Signed with the **debug keystore** for sideloading. Replace before Play Store.
- arm64 covers virtually all modern Android phones (2017+).
- Remove LAN cleartext entries from `network_security_config.xml` before publishing.
