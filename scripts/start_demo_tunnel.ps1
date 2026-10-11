# Starts the local API and a temporary Cloudflare HTTPS tunnel in front of it.
#
# Quick tunnels get a new random hostname every time they start, so the URL is
# printed at the end. Paste that URL into the app's "Server address" dialog
# (demo builds only) — no APK rebuild required.
#
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\start_demo_tunnel.ps1

$ErrorActionPreference = "Stop"

$cloudflared = "C:\Program Files (x86)\cloudflared\cloudflared.exe"
if (-not (Test-Path $cloudflared)) {
    $cloudflared = "C:\Program Files\cloudflared\cloudflared.exe"
}
if (-not (Test-Path $cloudflared)) {
    Write-Error "cloudflared is not installed. Run: winget install Cloudflare.cloudflared"
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
$env:CORS_ORIGINS = if ($env:CORS_ORIGINS) { $env:CORS_ORIGINS } else { "*" }
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

# Kill any previous API on 8000 so the tunnel always hits this process.
Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }

$api = Start-Process -FilePath "py" `
    -ArgumentList "-m", "uvicorn", "app.main:app", "--host", "127.0.0.1", "--port", "8000" `
    -WorkingDirectory $backend `
    -PassThru `
    -WindowStyle Minimized

Start-Sleep -Seconds 2
try {
    $null = Invoke-WebRequest -Uri "http://127.0.0.1:8000/health" -UseBasicParsing -TimeoutSec 10
} catch {
    Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue
    Write-Error "API failed to start on port 8000."
}

Write-Host "API running locally on http://127.0.0.1:8000" -ForegroundColor Green
Write-Host "Starting Cloudflare quick tunnel..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop both the tunnel and the API." -ForegroundColor Yellow
Write-Host ""

try {
    & $cloudflared tunnel --url http://127.0.0.1:8000 --no-autoupdate
} finally {
    Write-Host "Stopping API..." -ForegroundColor Yellow
    Stop-Process -Id $api.Id -Force -ErrorAction SilentlyContinue
}
