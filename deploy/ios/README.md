# iOS apps

Apple only allows iOS apps to be built on a Mac with Xcode, and every app installed on an
iPhone must be signed by an Apple account. So the `.ipa` files are produced in one of
these ways, and land in this folder as `GST-Expense-Employee.ipa` and `GST-Expense-Admin.ipa`.

## Option A: GitHub Actions (no Mac needed)

1. Push this project to a GitHub repository.
2. **Actions → Release apps → Run workflow.**
3. Download the `ios-apps` artifact when it finishes (about 20 minutes). It also builds the
   two Android APKs (`android-apps`).

Without signing secrets you get `GST-Expense-Employee-unsigned.ipa` and
`GST-Expense-Admin-unsigned.ipa`. Install them with [Sideloadly](https://sideloadly.io) or
[AltStore](https://altstore.io) using any Apple ID. Apps installed with a free Apple ID
stop opening after 7 days and must be re-installed; with a paid developer account they
last a year.

For signed builds you can hand to staff (ad hoc) or upload to TestFlight/App Store, join the
[Apple Developer Program](https://developer.apple.com/programs/) (US$99/year), then add these
repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | What it is |
|---|---|
| `IOS_TEAM_ID` | Your 10-character Team ID (developer.apple.com → Membership) |
| `IOS_P12_BASE64` | Your "Apple Distribution" certificate exported from Keychain as .p12, base64-encoded |
| `IOS_P12_PASSWORD` | The password you gave the .p12 |
| `IOS_PROFILE_EMPLOYEE_BASE64` | Provisioning profile for bundle ID `com.gstexpenses.gstExpenseScanner`, base64 |
| `IOS_PROFILE_ADMIN_BASE64` | Provisioning profile for bundle ID `com.gstexpenses.gstExpenseAdmin`, base64 |

Create the two App IDs and profiles at developer.apple.com → Certificates, IDs & Profiles.
Use **Ad Hoc** profiles (with your staff's iPhone UDIDs registered) for direct installs,
or **App Store** profiles and run the workflow with `ios_export_method = app-store` for
TestFlight. To base64-encode a file on Windows:
`[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.p12")) | Set-Clipboard`.

## Option B: on a Mac

```bash
bash scripts/build_ios.sh                          # unsigned .ipa files
TEAM_ID=ABCDE12345 bash scripts/build_ios.sh       # signed (ad hoc) with Xcode automatic signing
TEAM_ID=ABCDE12345 EXPORT_METHOD=app-store bash scripts/build_ios.sh   # for TestFlight
```

For automatic signing, open Xcode once and sign in under **Settings → Accounts**.

## Installing a signed ad hoc .ipa

Send the file to the iPhone owner and install it with Apple Configurator, Finder (drag onto
the connected iPhone) or a distribution service such as Diawi. The phone's UDID must be in
the provisioning profile. For many users, TestFlight is easier: upload the app-store build
with Transporter and invite testers by email.
