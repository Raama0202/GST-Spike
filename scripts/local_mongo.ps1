# Dot-sourced by the dev scripts. Uses MONGODB_URI when set (e.g. an Atlas
# cluster); otherwise makes sure a MongoDB is listening on 127.0.0.1:27017,
# starting the portable server in backend\.mongo when one is unpacked there.

if ($env:MONGODB_URI) { return }

$env:MONGODB_URI = "mongodb://127.0.0.1:27017/gst_expenses?directConnection=true"

$listening = Get-NetTCPConnection -LocalPort 27017 -State Listen -ErrorAction SilentlyContinue
if ($listening) { return }

$mongoHome = Join-Path $PSScriptRoot "..\backend\.mongo"
$mongod = Get-ChildItem $mongoHome -Recurse -Filter mongod.exe -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $mongod) {
    Write-Error ("No MongoDB on 127.0.0.1:27017. Install MongoDB Community, run " +
        "'docker run -d -p 27017:27017 mongo:8', or set MONGODB_URI to an Atlas cluster.")
}

$data = Join-Path $mongoHome "data"
New-Item -ItemType Directory -Force -Path $data | Out-Null
Start-Process -FilePath $mongod.FullName -WindowStyle Hidden -ArgumentList @(
    "--dbpath", "`"$data`"", "--bind_ip", "127.0.0.1", "--port", "27017",
    "--logpath", "`"$(Join-Path $mongoHome 'mongod.log')`"", "--logappend"
)
foreach ($i in 1..20) {
    if (Get-NetTCPConnection -LocalPort 27017 -State Listen -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Milliseconds 500
}
Write-Host "Started local MongoDB ($($mongod.FullName))" -ForegroundColor Cyan
