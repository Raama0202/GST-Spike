#!/usr/bin/env bash
# Builds the iOS apps (employee + admin) into deploy/ios. Needs macOS with Xcode and Flutter.
#
#   bash scripts/build_ios.sh                      # unsigned .ipa files (install with Sideloadly/AltStore)
#   TEAM_ID=ABCDE12345 bash scripts/build_ios.sh   # signed with Xcode automatic signing (ad-hoc)
#
# Environment:
#   API_URL           API base URL (default https://gst-expense-scanner.onrender.com/v1)
#   TEAM_ID           Apple Developer Team ID; leave empty for unsigned builds
#   EXPORT_METHOD     ad-hoc (default) | app-store | development | enterprise
#   PROFILE_EMPLOYEE  provisioning profile *name* for manual signing (CI); otherwise automatic
#   PROFILE_ADMIN     same, for the admin app
#   APPS              "employee admin" (default) or just one of them
#   FIREBASE_API_KEY, FIREBASE_PROJECT_ID, FIREBASE_SENDER_ID, FIREBASE_IOS_APP_ID  (optional push)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
API_URL="${API_URL:-https://gst-expense-scanner.onrender.com/v1}"
OUT="${OUT:-$REPO/deploy/ios}"
TEAM_ID="${TEAM_ID:-}"
EXPORT_METHOD="${EXPORT_METHOD:-ad-hoc}"
APPS="${APPS:-employee admin}"
mkdir -p "$OUT"

restore() {
  for f in "$REPO/ios/Flutter/Release.xcconfig.bak" "$REPO/admin/ios/Flutter/Release.xcconfig.bak"; do
    if [[ -f "$f" ]]; then mv -f "$f" "${f%.bak}"; fi
  done
}
trap restore EXIT

defines=(--dart-define=API_BASE_URL="$API_URL" --dart-define=ENV=production)
for name in FIREBASE_API_KEY FIREBASE_PROJECT_ID FIREBASE_SENDER_ID FIREBASE_IOS_APP_ID; do
  if [[ -n "${!name:-}" ]]; then defines+=(--dart-define="$name=${!name}"); fi
done

build_app() {
  local dir name bundle profile
  case "$1" in
    employee) dir="$REPO"; name="GST-Expense-Employee"; bundle="com.gstexpenses.gstExpenseScanner"; profile="${PROFILE_EMPLOYEE:-}" ;;
    admin) dir="$REPO/admin"; name="GST-Expense-Admin"; bundle="com.gstexpenses.gstExpenseAdmin"; profile="${PROFILE_ADMIN:-}" ;;
    *) echo "Unknown app '$1' (use employee or admin)" >&2; exit 2 ;;
  esac

  echo "==> Building $name"
  cd "$dir"
  flutter pub get

  if [[ -z "$TEAM_ID" ]]; then
    flutter build ios --release --no-codesign "${defines[@]}"
    rm -rf build/ipa-unsigned && mkdir -p build/ipa-unsigned/Payload
    cp -R build/ios/iphoneos/Runner.app build/ipa-unsigned/Payload/
    rm -f "$OUT/$name-unsigned.ipa"
    (cd build/ipa-unsigned && zip -qry "$OUT/$name-unsigned.ipa" Payload)
    echo "    $OUT/$name-unsigned.ipa"
    return
  fi

  local identity="Apple Distribution"
  [[ "$EXPORT_METHOD" == "development" ]] && identity="Apple Development"
  local xcconfig="ios/Flutter/Release.xcconfig"
  cp "$xcconfig" "$xcconfig.bak"
  {
    echo ""
    echo "DEVELOPMENT_TEAM=$TEAM_ID"
    if [[ -n "$profile" ]]; then
      echo "CODE_SIGN_STYLE=Manual"
      echo "CODE_SIGN_IDENTITY=$identity"
      echo "PROVISIONING_PROFILE_SPECIFIER=$profile"
    else
      echo "CODE_SIGN_STYLE=Automatic"
    fi
  } >> "$xcconfig"

  mkdir -p build
  local plist="build/ExportOptions.plist"
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    echo "  <key>method</key><string>$EXPORT_METHOD</string>"
    echo "  <key>teamID</key><string>$TEAM_ID</string>"
    if [[ -n "$profile" ]]; then
      echo '  <key>signingStyle</key><string>manual</string>'
      echo "  <key>signingCertificate</key><string>$identity</string>"
      echo "  <key>provisioningProfiles</key><dict><key>$bundle</key><string>$profile</string></dict>"
    else
      echo '  <key>signingStyle</key><string>automatic</string>'
    fi
    echo '  <key>compileBitcode</key><false/>'
    echo '</dict></plist>'
  } > "$plist"

  rm -rf build/ios/ipa
  flutter build ipa --release --export-options-plist="$plist" "${defines[@]}"
  mv -f "$xcconfig.bak" "$xcconfig"
  local ipa
  ipa="$(ls build/ios/ipa/*.ipa | head -n 1)"
  cp -f "$ipa" "$OUT/$name.ipa"
  echo "    $OUT/$name.ipa"
}

for app in $APPS; do build_app "$app"; done
echo "==> Done. Files in $OUT"
