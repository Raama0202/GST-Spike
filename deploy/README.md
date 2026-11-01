# GST Expense: ready-to-install files

| File | Who uses it | Install |
|---|---|---|
| `android/GST-Expense-Employee.apk` | Employees (scan and submit bills) | Copy to the phone, open it, allow "Install unknown apps" when asked |
| `android/GST-Expense-Admin.apk` | Company admins (review bills, employees, reports) | Same as above |
| `ios/GST-Expense-Employee.ipa` | Employees on iPhone | See `ios/README.md` (built on a Mac or GitHub Actions) |
| `ios/GST-Expense-Admin.ipa` | Company admins on iPhone | See `ios/README.md` |
| `SuperAdminPortal/Start-Super-Admin-Portal.bat` | You (platform owner) and company admins on a PC | Double-click it |

All apps connect to the API at `https://gst-expense-scanner.onrender.com/v1`. Deploy the
backend first (see `docs/GO_LIVE.md`). On the free Render plan the first request after
15 idle minutes takes up to a minute while the server wakes.

## Android

- Works on Android 7.0 and newer. One APK covers all phones (ARM and x86).
- Employees sign in with their mobile number and a one-time code (sent by SMS, or by email
  when SMS isn't configured). Admins add employees in the console first. Admins sign in
  with the email and password created at firm registration (or by the super admin).
- The APKs are signed with this project's release keys (`android/upload-keystore.jks` and
  `admin/android/upload-keystore.jks`, passwords in the `key.properties` next to each).
  **Back up those four files.** Every future update must be signed with the same keys, or
  phones will refuse to install it over the old version. They are also what you use for
  Google Play (as the upload key).

## Super Admin Portal (Windows)

1. Copy the whole `SuperAdminPortal` folder anywhere (it needs nothing else installed).
2. Double-click `Start-Super-Admin-Portal.bat`. Your browser opens `http://localhost:5180`.
3. Sign in with the super admin account. Create it once with
   `py -m app.cli create-super-admin --email you@example.com` (section 5 of `docs/GO_LIVE.md`).
   Company admins can use the same portal with their own login.
4. Keep the black window open while you work; close it to stop the portal.

To point the portal at a different API (your own domain, or a local backend at
`http://localhost:8000`), edit `apiUrl` in `SuperAdminPortal/portal.config.json`.

The same console is also deployed on Render at `https://gst-admin-console.onrender.com`.

## Rebuilding

```powershell
# Android APKs + portal (Windows, needs Flutter, JDK 17, Android SDK, Node.js)
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
# Use your own API domain:
powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -ApiUrl https://api.yourdomain.com/v1
```

```bash
# iOS (macOS with Xcode + Flutter)
bash scripts/build_ios.sh
```

Or run the **Release apps** workflow on GitHub (Actions tab) to build all four app files in the cloud.
