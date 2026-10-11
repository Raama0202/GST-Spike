# Starts the API on this machine's Wi-Fi address so phones on the same network
# can reach it. Uses SQLite so PostgreSQL is not required for device testing.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\start_dev_api.ps1

$ErrorActionPreference = "Stop"

# The address baked into the LAN test APKs. If your Wi-Fi address changes, the
# APKs must be rebuilt with the new value (see dist/apk/README.md).
$ExpectedIp = "192.168.29.21"

$lanIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.PrefixOrigin -eq "Dhcp" -and $_.IPAddress -notlike "169.254.*" } |
    Select-Object -First 1).IPAddress

if (-not $lanIp) {
    Write-Warning "No DHCP IPv4 address found. Connect to Wi-Fi and retry."
    exit 1
}

Write-Host "This machine: $lanIp" -ForegroundColor Cyan
if ($lanIp -ne $ExpectedIp) {
    Write-Warning "APKs expect $ExpectedIp but this machine is $lanIp."
    Write-Warning "Rebuild the APKs with --dart-define=API_BASE_URL=http://$lanIp`:8000/v1"
    Write-Warning "and add $lanIp to android/app/src/main/res/xml/network_security_config.xml."
}

$backend = Join-Path $PSScriptRoot "..\backend"
Set-Location $backend

# Load optional .env (GEMINI_API_KEY, etc.) without overriding already-set vars.
$envFile = Join-Path $backend ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
        $name, $value = $_.Split('=', 2)
        $name = $name.Trim()
        $value = $value.Trim().Trim('"').Trim("'")
        if ($name -and -not [Environment]::GetEnvironmentVariable($name)) {
            Set-Item -Path "Env:$name" -Value $value
        }
    }
}

$env:DATABASE_URL = if ($env:DATABASE_URL) { $env:DATABASE_URL } else { "sqlite+aiosqlite:///./dev.db" }
$env:STORAGE_PATH = if ($env:STORAGE_PATH) { $env:STORAGE_PATH } else { "./uploads" }
$env:ENV = if ($env:ENV) { $env:ENV } else { "dev" }
$env:OTP_DEV_FIXED = if ($env:OTP_DEV_FIXED) { $env:OTP_DEV_FIXED } else { "123456" }
$env:JWT_SECRET = if ($env:JWT_SECRET) { $env:JWT_SECRET } else { "local-dev-secret-key-not-for-production-use" }
$env:CORS_ORIGINS = if ($env:CORS_ORIGINS) { $env:CORS_ORIGINS } else { "http://localhost:8080,http://$lanIp`:8080" }
$env:GEMINI_MODEL = if ($env:GEMINI_MODEL) { $env:GEMINI_MODEL } else { "gemini-3.5-flash" }

if (-not $env:GEMINI_API_KEY) {
    Write-Warning "GEMINI_API_KEY is not set. Invoice AI extraction will be unavailable."
    Write-Warning "Create a free key at https://aistudio.google.com/apikey and put it in backend\.env"
} else {
    Write-Host "Gemini AI extraction enabled ($env:GEMINI_MODEL)" -ForegroundColor Green
}

if (-not (Test-Path "./dev.db")) {
    Write-Host "Creating database and seed data..." -ForegroundColor Cyan
    py dev_init.py
}

# Inbound rule for the phone; requires an elevated shell the first time.
if (-not (Get-NetFirewallRule -DisplayName "GST API 8000" -ErrorAction SilentlyContinue)) {
    try {
        New-NetFirewallRule -DisplayName "GST API 8000" -Direction Inbound `
            -LocalPort 8000 -Protocol TCP -Action Allow | Out-Null
        Write-Host "Firewall rule added for port 8000." -ForegroundColor Green
    } catch {
        Write-Warning "Could not add firewall rule. Run this script as Administrator once."
    }
}

Write-Host ""
Write-Host "API      http://$lanIp`:8000/v1"  -ForegroundColor Green
Write-Host "Docs     http://$lanIp`:8000/docs" -ForegroundColor Green
Write-Host "Health   http://$lanIp`:8000/health" -ForegroundColor Green
Write-Host ""

py -m uvicorn app.main:app --host 0.0.0.0 --port 8000
