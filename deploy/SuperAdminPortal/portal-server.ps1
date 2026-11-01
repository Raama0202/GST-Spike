<#
  GST Expense - Super Admin Portal launcher (Windows PowerShell 5.1+, no other installs).

  Serves the prebuilt web console from .\app on http://localhost:<port> and forwards
  /v1/* and /health to the API in portal.config.json, so the browser only ever talks to
  localhost (no CORS changes needed on the server).
#>
param([switch]$NoBrowser)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$appDir = Join-Path $root 'app'
$configPath = Join-Path $root 'portal.config.json'

function Write-Info($text, $color = 'Gray') { Write-Host $text -ForegroundColor $color }

if (-not (Test-Path (Join-Path $appDir 'index.html'))) {
    Write-Info "The portal files are missing (expected $appDir\index.html)." Red
    Write-Info "Re-copy the whole SuperAdminPortal folder, or rebuild it with scripts\build_release.ps1." Red
    exit 1
}

$config = @{ apiUrl = 'https://gst-expense-scanner.onrender.com'; port = 5180 }
if (Test-Path $configPath) {
    try {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($json.apiUrl) { $config.apiUrl = [string]$json.apiUrl }
        if ($json.port) { $config.port = [int]$json.port }
    } catch {
        Write-Info "portal.config.json is not valid JSON; using defaults. ($($_.Exception.Message))" Yellow
    }
}
# Accept either https://host or https://host/v1 in the config.
$apiBase = ($config.apiUrl.Trim() -replace '/+$', '') -replace '/v1$', ''
if ($apiBase -notmatch '^https?://') {
    Write-Info "apiUrl in portal.config.json must start with http:// or https:// (got '$apiBase')." Red
    exit 1
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11
Add-Type -AssemblyName System.Net.Http
$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AllowAutoRedirect = $false
$handler.UseCookies = $false
$handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
$client = New-Object System.Net.Http.HttpClient($handler)
# Free Render instances can take about a minute to wake; exports can be large.
$client.Timeout = [TimeSpan]::FromMinutes(5)

$listener = $null
$port = $config.port
for ($attempt = 0; $attempt -lt 20; $attempt++) {
    $candidate = New-Object System.Net.HttpListener
    $candidate.Prefixes.Add("http://localhost:$port/")
    try { $candidate.Start(); $listener = $candidate; break }
    catch { $candidate.Close(); $port++ }
}
if (-not $listener) {
    Write-Info "Could not open a local port between $($config.port) and $port. Close other apps or change 'port' in portal.config.json." Red
    exit 1
}
$url = "http://localhost:$port/"

Write-Info ''
Write-Info '  GST Expense - Super Admin Portal' Cyan
Write-Info '  --------------------------------' Cyan
Write-Info "  Portal : $url" White
Write-Info "  API    : $apiBase" White
Write-Info ''

try {
    Write-Info '  Checking the API (a sleeping free server can take up to a minute)...'
    $probe = $client.GetAsync("$apiBase/health").GetAwaiter().GetResult()
    if ($probe.IsSuccessStatusCode) { Write-Info '  API is online.' Green }
    else { Write-Info "  API answered $([int]$probe.StatusCode); the portal may show errors until it is healthy." Yellow }
    $probe.Dispose()
} catch {
    Write-Info "  API not reachable right now ($($_.Exception.GetBaseException().Message))." Yellow
    Write-Info '  The portal will keep retrying; check your internet connection or apiUrl in portal.config.json.' Yellow
}
Write-Info ''
Write-Info '  Keep this window open while you use the portal. Close it (or press Ctrl+C) to stop.' DarkGray
Write-Info ''

if (-not $NoBrowser) { Start-Process $url }

$requestHandler = {
    param($context, $client, $apiBase, $appDir)

    $mime = @{
        '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.mjs' = 'text/javascript; charset=utf-8'
        '.css' = 'text/css; charset=utf-8'; '.json' = 'application/json'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'
        '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'; '.webp' = 'image/webp'; '.ico' = 'image/x-icon'
        '.woff' = 'font/woff'; '.woff2' = 'font/woff2'; '.ttf' = 'font/ttf'; '.txt' = 'text/plain; charset=utf-8'
        '.webmanifest' = 'application/manifest+json'; '.map' = 'application/json'
    }
    $skipRequest = @('Host', 'Connection', 'Content-Length', 'Origin', 'Referer', 'Accept-Encoding', 'Expect', 'Keep-Alive', 'Transfer-Encoding')
    $skipResponse = @('Content-Length', 'Transfer-Encoding', 'Connection', 'Content-Encoding', 'Keep-Alive', 'Server', 'Date', 'Strict-Transport-Security', 'Access-Control-Allow-Origin', 'Access-Control-Allow-Credentials')

    $request = $context.Request
    $response = $context.Response
    try {
        $path = $request.Url.AbsolutePath
        if ($path -eq '/health' -or $path -eq '/v1' -or $path.StartsWith('/v1/')) {
            $message = New-Object System.Net.Http.HttpRequestMessage((New-Object System.Net.Http.HttpMethod($request.HttpMethod)), ($apiBase + $request.Url.PathAndQuery))
            if ($request.HasEntityBody) {
                $buffer = New-Object System.IO.MemoryStream
                $request.InputStream.CopyTo($buffer)
                $message.Content = New-Object System.Net.Http.ByteArrayContent(, $buffer.ToArray())
                if ($request.ContentType) { [void]$message.Content.Headers.TryAddWithoutValidation('Content-Type', $request.ContentType) }
            }
            foreach ($name in $request.Headers.AllKeys) {
                if ($skipRequest -contains $name -or $name -eq 'Content-Type') { continue }
                [void]$message.Headers.TryAddWithoutValidation($name, $request.Headers[$name])
            }
            try {
                $upstream = $client.SendAsync($message, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            } catch {
                $response.StatusCode = 502
                $response.ContentType = 'application/json'
                $body = [Text.Encoding]::UTF8.GetBytes('{"message":"The portal could not reach the API server. Check your internet connection and try again.","code":"API_UNREACHABLE"}')
                $response.OutputStream.Write($body, 0, $body.Length)
                return
            }
            $response.StatusCode = [int]$upstream.StatusCode
            $headers = @($upstream.Headers) + @($upstream.Content.Headers)
            foreach ($header in $headers) {
                if ($skipResponse -contains $header.Key) { continue }
                $value = [string]::Join(', ', [string[]]$header.Value)
                if ($header.Key -eq 'Content-Type') { $response.ContentType = $value; continue }
                if ($header.Key -eq 'Location' -and $value.StartsWith($apiBase)) { $value = $value.Substring($apiBase.Length) }
                try { $response.Headers.Add($header.Key, $value) } catch { }
            }
            $stream = $upstream.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $stream.CopyTo($response.OutputStream)
            $stream.Dispose()
            $upstream.Dispose()
            return
        }

        if ($request.HttpMethod -ne 'GET' -and $request.HttpMethod -ne 'HEAD') { $response.StatusCode = 405; return }
        $relative = [Uri]::UnescapeDataString($path.TrimStart('/')).Replace('/', '\')
        if (-not $relative) { $relative = 'index.html' }
        $file = [IO.Path]::GetFullPath((Join-Path $appDir $relative))
        if (-not $file.StartsWith($appDir, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path $file -PathType Leaf)) {
            # Hash routing means unknown paths are just the app shell.
            $file = Join-Path $appDir 'index.html'
        }
        $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
        $response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
        if ($file -like '*\assets\*') { $response.Headers.Add('Cache-Control', 'public, max-age=31536000, immutable') }
        else { $response.Headers.Add('Cache-Control', 'no-cache') }
        $response.Headers.Add('X-Content-Type-Options', 'nosniff')
        $bytes = [IO.File]::ReadAllBytes($file)
        $response.ContentLength64 = $bytes.Length
        if ($request.HttpMethod -eq 'GET') { $response.OutputStream.Write($bytes, 0, $bytes.Length) }
    } catch {
        try { $response.StatusCode = 500 } catch { }
    } finally {
        try { $response.OutputStream.Close() } catch { }
        try { $response.Close() } catch { }
    }
}

$appDirFull = [IO.Path]::GetFullPath($appDir)
$pool = [RunspaceFactory]::CreateRunspacePool(1, 24)
$pool.Open()
$jobs = New-Object System.Collections.ArrayList
try {
    while ($listener.IsListening) {
        $pending = $listener.GetContextAsync()
        while (-not $pending.Wait(500)) {
            # Wake up regularly so Ctrl+C is honoured and finished workers are released.
            for ($i = $jobs.Count - 1; $i -ge 0; $i--) {
                if ($jobs[$i].Handle.IsCompleted) {
                    try { $jobs[$i].Shell.EndInvoke($jobs[$i].Handle) } catch { }
                    $jobs[$i].Shell.Dispose(); $jobs.RemoveAt($i)
                }
            }
        }
        $shell = [PowerShell]::Create()
        $shell.RunspacePool = $pool
        [void]$shell.AddScript($requestHandler).AddArgument($pending.Result).AddArgument($client).AddArgument($apiBase).AddArgument($appDirFull)
        [void]$jobs.Add([pscustomobject]@{ Shell = $shell; Handle = $shell.BeginInvoke() })
    }
} finally {
    $listener.Stop()
    $listener.Close()
    $pool.Close()
    $client.Dispose()
}
