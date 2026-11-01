<#
  Builds every Windows-buildable deliverable into .\deploy:
    deploy\android\GST-Expense-Employee.apk   (employee scanner app)
    deploy\android\GST-Expense-Admin.apk      (company admin app)
    deploy\SuperAdminPortal\app\              (web console used by Start-Super-Admin-Portal.bat)

  iOS .ipa files need macOS + Xcode: see deploy\ios\README.md.

  First run creates a release signing key per app (android\upload-keystore.jks and
  admin\android\upload-keystore.jks, passwords in key.properties next to them).
  BACK THESE UP: every future update of the apps must be signed with the same key.

  Usage:  powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 [-ApiUrl https://api.example.com/v1] [-Only android|portal]
  Optional push config for the employee app: set FIREBASE_API_KEY, FIREBASE_PROJECT_ID,
  FIREBASE_SENDER_ID, FIREBASE_ANDROID_APP_ID (and FIREBASE_IOS_APP_ID) before running.
#>
param(
    [string]$ApiUrl = 'https://gst-expense-scanner.onrender.com/v1',
    [ValidateSet('all', 'android', 'portal')][string]$Only = 'all'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$deploy = Join-Path $repo 'deploy'
$ApiUrl = $ApiUrl.TrimEnd('/')

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Invoke-Checked([string]$what, [scriptblock]$block) {
    & $block
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit code $LASTEXITCODE)" }
}

function Find-Keytool {
    $candidates = @()
    $java = Get-Command java -ErrorAction SilentlyContinue
    if ($java) { $candidates += Join-Path (Split-Path $java.Source) 'keytool.exe' }
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
    $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw 'keytool not found. Install a JDK 17 (e.g. Eclipse Temurin) or Android Studio.'
}

function Ensure-SigningKey([string]$androidDir, [string]$label) {
    $props = Join-Path $androidDir 'key.properties'
    if (Test-Path $props) { return }
    $keystore = Join-Path $androidDir 'upload-keystore.jks'
    if (Test-Path $keystore) {
        throw "$keystore exists but $props is missing. Restore key.properties from your backup (never regenerate a released key)."
    }
    Step "Creating release signing key for the $label app"
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789'.ToCharArray()
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] 24
    $rng.GetBytes($bytes)
    $password = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
    $keytool = Find-Keytool
    Invoke-Checked 'keytool' {
        & $keytool -genkeypair -noprompt -keystore $keystore -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 `
            -alias upload -storepass $password -keypass $password -dname "CN=GST Expense $label, O=GST Expenses, C=IN" | Out-Null
    }
    $text = "storePassword=$password`nkeyPassword=$password`nkeyAlias=upload`nstoreFile=../upload-keystore.jks`n"
    [IO.File]::WriteAllText($props, $text, (New-Object Text.UTF8Encoding $false))
    Write-Host "    Saved $keystore and $props - back both up somewhere safe." -ForegroundColor Yellow
}

function Build-Apk([string]$projectDir, [string]$label, [string]$outName, [string[]]$extraDefines) {
    Ensure-SigningKey (Join-Path $projectDir 'android') $label
    Step "Building $label APK"
    Push-Location $projectDir
    try {
        Invoke-Checked 'flutter pub get' { flutter pub get }
        $defines = @("--dart-define=API_BASE_URL=$ApiUrl", '--dart-define=ENV=production') + $extraDefines
        Invoke-Checked "flutter build apk ($label)" { flutter build apk --release @defines }
    } finally { Pop-Location }
    $apk = Join-Path $projectDir 'build\app\outputs\flutter-apk\app-release.apk'
    $target = Join-Path $deploy "android\$outName"
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item $apk $target -Force
    Write-Host ("    {0} ({1:N1} MB)" -f $target, ((Get-Item $target).Length / 1MB)) -ForegroundColor Green
}

if ($Only -in 'all', 'android') {
    $firebase = @()
    foreach ($name in 'FIREBASE_API_KEY', 'FIREBASE_PROJECT_ID', 'FIREBASE_SENDER_ID', 'FIREBASE_ANDROID_APP_ID', 'FIREBASE_IOS_APP_ID') {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $firebase += "--dart-define=$name=$value" }
    }
    Build-Apk $repo 'Employee' 'GST-Expense-Employee.apk' $firebase
    Build-Apk (Join-Path $repo 'admin') 'Admin' 'GST-Expense-Admin.apk' @()
}

if ($Only -in 'all', 'portal') {
    Step 'Building the Super Admin Portal (web console)'
    $out = Join-Path $deploy 'SuperAdminPortal\app'
    Push-Location (Join-Path $repo 'web-admin')
    $previous = $env:VITE_API_BASE_URL
    try {
        if (-not (Test-Path node_modules) -and -not (Test-Path (Join-Path $repo 'node_modules\vite'))) {
            Invoke-Checked 'npm install' { npm install }
        }
        # The launcher forwards /v1 to the real API, so the console calls its own origin.
        $env:VITE_API_BASE_URL = 'same-origin'
        Invoke-Checked 'tsc' { npx tsc }
        Invoke-Checked 'vite build' { npx vite build --outDir $out --emptyOutDir }
    } finally {
        $env:VITE_API_BASE_URL = $previous
        Pop-Location
    }
    $apiOrigin = $ApiUrl -replace '/v1$', ''
    $config = Join-Path $deploy 'SuperAdminPortal\portal.config.json'
    [IO.File]::WriteAllText($config, "{`n  `"apiUrl`": `"$apiOrigin`",`n  `"port`": 5180`n}`n", (New-Object Text.UTF8Encoding $false))
    Write-Host "    $out" -ForegroundColor Green
}

Step 'Done'
Get-ChildItem $deploy -Recurse -File -Include *.apk, *.bat | ForEach-Object {
    Write-Host ("    {0}  {1:N1} MB" -f $_.FullName.Substring($repo.Length + 1), ($_.Length / 1MB))
}
