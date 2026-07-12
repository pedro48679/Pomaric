<#
.SYNOPSIS
  Mata os servicos de background arrancados por start_all.ps1 (ws_server, mlops_server, cnn5_watcher).
  So e preciso se start_all.ps1 nao tiver conseguido limpar sozinho (ex: terminal fechado a bruta).
#>
$pidFile = Join-Path $PSScriptRoot "logs\start_all.pids"

if (-not (Test-Path $pidFile)) {
    Write-Host "Nenhum PID guardado em $pidFile - nada a parar." -ForegroundColor Yellow
    exit 0
}

Get-Content $pidFile | ForEach-Object {
    $procId = $_.Trim()
    if ($procId) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "Parado PID $procId" -ForegroundColor Green
        } catch {
            Write-Host "PID $procId ja nao estava a correr" -ForegroundColor DarkGray
        }
    }
}

Remove-Item -Path $pidFile -ErrorAction SilentlyContinue
