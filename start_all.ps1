<#
.SYNOPSIS
  Arranca num único comando: ws_server, mlops_server, cnn5_watcher (background) + dashboard Flutter (foreground).

.DESCRIPTION
  Os serviços do Raspberry Pi NÃO são arrancados por este script (correm sozinhos
  via systemd no boot do Pi). Este script cobre só o lado do PC.

.EXAMPLE
  ./start_all.ps1
  ./start_all.ps1 -Device chrome

.NOTES
  Requer as variáveis de ambiente SUPABASE_URL, SUPABASE_ANON_KEY e
  SUPABASE_SERVICE_KEY — a anon key vai para o Flutter via --dart-define, a
  service_role key é usada por cnn5_watcher.py/shadow_runner.py para
  escrever na BD. Podem vir da sessão, ou (mais cómodo) de um ficheiro
  secrets.local.ps1 na raiz do repo, carregado automaticamente se existir
  (nunca commitado: o .gitignore é whitelist e não o inclui).
#>
param(
    [string]$Device = "windows",
    [string]$ImageDir = "C:\auditoria_logs\Imagens",
    [string]$JsonDir = "C:\auditoria_logs\Jsonn"
)

$ErrorActionPreference = "Stop"

# Carrega segredos locais se o ficheiro existir (define $env:SUPABASE_*).
# Variáveis já definidas na sessão têm precedência sobre o ficheiro.
$secretsFile = Join-Path $PSScriptRoot "secrets.local.ps1"
if (Test-Path $secretsFile) {
    $preUrl = $env:SUPABASE_URL; $preAnon = $env:SUPABASE_ANON_KEY; $preService = $env:SUPABASE_SERVICE_KEY
    . $secretsFile
    if ($preUrl) { $env:SUPABASE_URL = $preUrl }
    if ($preAnon) { $env:SUPABASE_ANON_KEY = $preAnon }
    if ($preService) { $env:SUPABASE_SERVICE_KEY = $preService }
    Write-Host "Segredos carregados de secrets.local.ps1" -ForegroundColor DarkGray
}

# Placeholders por preencher contam como não definidos
foreach ($name in 'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_KEY') {
    $val = [Environment]::GetEnvironmentVariable($name)
    if ($val -and $val.StartsWith('<')) { [Environment]::SetEnvironmentVariable($name, $null) }
}

if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_ANON_KEY -or -not $env:SUPABASE_SERVICE_KEY) {
    Write-Host "SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_KEY não definidos." -ForegroundColor Red
    Write-Host "Preenche o ficheiro secrets.local.ps1 na raiz do repo (recomendado)," -ForegroundColor Yellow
    Write-Host "ou define-os na sessão antes de correr este script, ex:" -ForegroundColor Yellow
    Write-Host '  $env:SUPABASE_URL = "https://<projeto>.supabase.co"' -ForegroundColor Yellow
    Write-Host '  $env:SUPABASE_ANON_KEY = "<anon-key>"' -ForegroundColor Yellow
    Write-Host '  $env:SUPABASE_SERVICE_KEY = "<service-role-key>"' -ForegroundColor Yellow
    exit 1
}

$venvPython = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    $venvPython = "python"
}

$onxxDir = Join-Path $PSScriptRoot "ONXX"
$dashboardDir = Join-Path $PSScriptRoot "dashboard"
$logsDir = Join-Path $PSScriptRoot "logs"
$pidFile = Join-Path $logsDir "start_all.pids"

New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
New-Item -ItemType Directory -Force -Path $ImageDir | Out-Null
New-Item -ItemType Directory -Force -Path $JsonDir | Out-Null

$processes = @()

function Start-BackgroundService {
    param([string]$Name, [string]$ScriptPath, [string[]]$Arguments)

    $outLog = Join-Path $logsDir "$Name.log"
    Write-Host "A iniciar $Name..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath $venvPython `
        -ArgumentList (@($ScriptPath) + $Arguments) `
        -WorkingDirectory $onxxDir `
        -RedirectStandardOutput $outLog `
        -RedirectStandardError "$outLog.err" `
        -PassThru -WindowStyle Hidden
    return $proc
}

$wsServer = Start-BackgroundService -Name "ws_server" -ScriptPath "ws_server.py" -Arguments @(
    "--image-dir", $ImageDir, "--json-dir", $JsonDir
)
$processes += $wsServer

$mlopsServer = Start-BackgroundService -Name "mlops_server" -ScriptPath "mlops_server.py" -Arguments @()
$processes += $mlopsServer

$cnn5Watcher = Start-BackgroundService -Name "cnn5_watcher" -ScriptPath "cnn5_watcher.py" -Arguments @(
    "--json-dir", $JsonDir
)
$processes += $cnn5Watcher

$processes.Id | Set-Content -Path $pidFile
Write-Host "PIDs guardados em $pidFile" -ForegroundColor DarkGray

Start-Sleep -Seconds 3

try {
    Invoke-WebRequest -Uri "http://localhost:8766/heartbeat" -UseBasicParsing -TimeoutSec 3 | Out-Null
    Write-Host "ws_server: OK (porta 8766)" -ForegroundColor Green
} catch {
    Write-Host "ws_server: sem resposta em 8766 (ver logs\ws_server.log)" -ForegroundColor Yellow
}

try {
    Invoke-WebRequest -Uri "http://localhost:8767/status" -UseBasicParsing -TimeoutSec 3 | Out-Null
    Write-Host "mlops_server: OK (porta 8767)" -ForegroundColor Green
} catch {
    Write-Host "mlops_server: sem resposta em 8767 (ver logs\mlops_server.log)" -ForegroundColor Yellow
}

Write-Host "cnn5_watcher: a correr em background (ver logs\cnn5_watcher.log)" -ForegroundColor Green
Write-Host ""
Write-Host "A lançar a dashboard Flutter (Ctrl+C aqui termina tudo)..." -ForegroundColor Cyan

try {
    Push-Location $dashboardDir
    flutter run -d $Device `
        --dart-define=SUPABASE_URL=$env:SUPABASE_URL `
        --dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY
} finally {
    Pop-Location
    Write-Host ""
    Write-Host "A terminar os serviços de background..." -ForegroundColor Cyan
    foreach ($p in $processes) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host "  parado PID $($p.Id)" -ForegroundColor DarkGray
        } catch {
            # já tinha terminado
        }
    }
    Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
}
