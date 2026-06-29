# Backup PostgreSQL + upload ke MinIO (Windows PowerShell, tanpa Git Bash).
param(
    [string]$Date = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if (-not (Test-Path ".env")) {
    Write-Error "File .env tidak ditemukan di $Root"
}

Get-Content ".env" | ForEach-Object {
    if ($_ -match '^\s*([^#=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim().Trim('"').Trim("'")
        Set-Item -Path "env:$name" -Value $value
    }
}

if ([string]::IsNullOrWhiteSpace($Date)) {
    $Date = Get-Date -Format "yyyy-MM-dd"
}

$backupDir = Join-Path $Root "storage\backups\$Date"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

if (-not (docker ps --format "{{.Names}}" | Select-String -Pattern "^ppkp-postgres$" -Quiet)) {
    Write-Error "Container ppkp-postgres tidak berjalan."
}

Write-Host "==> pg_dump sikerja_ppkp + mcu_monitor"
foreach ($db in @("sikerja_ppkp", "mcu_monitor")) {
    $tmp = "/tmp/$db.dump"
    $local = Join-Path $backupDir "$db.dump"
    docker exec ppkp-postgres pg_dump -U postgres -Fc $db -f $tmp
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    docker cp "ppkp-postgres:${tmp}" $local
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    $size = (Get-Item $local).Length
    Write-Host "    $db.dump ($size bytes)"
}

$bucket = if ($env:MINIO_BACKUP_BUCKET) { $env:MINIO_BACKUP_BUCKET } else { "minio.sikerja" }
$prefix = if ($env:MINIO_BACKUP_PREFIX) { $env:MINIO_BACKUP_PREFIX } else { "pg-backups" }
$remotePrefix = "$prefix/$Date"
$network = docker inspect ppkp-minio --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}'

if (-not (docker ps --format "{{.Names}}" | Select-String -Pattern "^ppkp-minio$" -Quiet)) {
    Write-Error "Container ppkp-minio tidak berjalan."
}

$unixDir = ($backupDir -replace '\\', '/')
if ($backupDir -match '^[A-Za-z]:') {
    $drive = $backupDir.Substring(0, 1).ToLower()
    $rest = $backupDir.Substring(2) -replace '\\', '/'
    $unixDir = "/$drive$rest"
}

Write-Host "==> Upload ke MinIO bucket $bucket/$remotePrefix"

docker run --rm --network $network --entrypoint /bin/sh `
    -v "${unixDir}:/backup:ro" `
    -e "MINIO_ROOT_USER=$($env:MINIO_ROOT_USER)" `
    -e "MINIO_ROOT_PASSWORD=$($env:MINIO_ROOT_PASSWORD)" `
    -e "MINIO_BACKUP_BUCKET=$bucket" `
    -e "REMOTE_PREFIX=$remotePrefix" `
    minio/mc:latest -ec @'
mc alias set ppkp http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "ppkp/${MINIO_BACKUP_BUCKET}"
mc cp --recursive /backup/ "ppkp/${MINIO_BACKUP_BUCKET}/${REMOTE_PREFIX}/"
mc ls --recursive "ppkp/${MINIO_BACKUP_BUCKET}/${REMOTE_PREFIX}/"
'@

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Selesai."
Write-Host "  Lokal : $backupDir"
Write-Host "  MinIO : bucket $bucket → $remotePrefix/"
Write-Host "  Console: http://127.0.0.1:$($env:MINIO_CONSOLE_PORT)/browser/$bucket"
