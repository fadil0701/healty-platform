# Upload arsip backup ke MinIO (Windows / PowerShell).
# Usage:
#   .\scripts\archive-backups-to-minio.ps1
#   .\scripts\archive-backups-to-minio.ps1 -BackupDir storage\backups\2026-06-29
param(
    [string]$BackupDir = "",
    [string]$Date = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not (Test-Path ".env")) {
    Write-Error "File .env tidak ditemukan di $Root"
}

if ([string]::IsNullOrWhiteSpace($Date)) {
    $Date = Get-Date -Format "yyyy-MM-dd"
}

if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $BackupDir = Join-Path $Root "storage\backups\$Date"
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
if (-not $bash) {
    Write-Error "Git Bash (bash) diperlukan. Pasang Git for Windows atau jalankan upload-to-minio.sh dari WSL."
}

$unixPath = ($BackupDir -replace '\\', '/')
if ($unixPath -notmatch '^[A-Za-z]:') {
    $unixPath = ($BackupDir -replace '\\', '/').TrimStart('/')
}

Write-Host "==> Upload backup ke MinIO"
Write-Host "    Folder: $BackupDir"

& bash "$Root/infrastructure/backup/upload-to-minio.sh" $unixPath

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Selesai. MinIO Console: http://127.0.0.1:9001"
