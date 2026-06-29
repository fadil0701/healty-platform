param([switch]$Down, [switch]$Monitoring)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $Root "..")

if (-not (Test-Path ".env")) {
    throw "Salin .env.example ke .env lalu isi password."
}

function Read-Env([string]$Key) {
    $line = (Select-String -Path ".env" -Pattern "^$Key=" | Select-Object -First 1).Line
    if (-not $line) { return "" }
    return $line.Substring($Key.Length + 1).Trim().Trim('"').Trim("'")
}

$pgPass = Join-Path $Root "..\infrastructure\pgadmin\pgpass"
$serversGenerated = Join-Path $Root "..\infrastructure\pgadmin\servers.generated.json"
$superPass = Read-Env "POSTGRES_SUPERUSER_PASSWORD"
$superUser = Read-Env "POSTGRES_SUPERUSER"
if ($superUser -eq "") { $superUser = "postgres" }
$pgAdminEmail = Read-Env "PGADMIN_EMAIL"
if ($pgAdminEmail -eq "") { $pgAdminEmail = "admin@local.test" }
$pgAdminGroup = Read-Env "PGADMIN_SERVER_GROUP"
if ($pgAdminGroup -eq "") { $pgAdminGroup = "Development" }
$pgAdminServerName = Read-Env "PGADMIN_SERVER_NAME"
if ($pgAdminServerName -eq "") { $pgAdminServerName = "PPKP PostgreSQL (lokal)" }

if ($superPass -eq "") {
    throw "POSTGRES_SUPERUSER_PASSWORD belum diisi di .env"
}

# LF only — CRLF di pgpass membuat libpq/pgAdmin gagal baca password
$pgPassContent = @"
sikerja-postgres:5432:*:${superUser}:$superPass
sikerja-postgres:5432:*:ppkp_dba_readonly:$superPass
ppkp-postgres:5432:*:${superUser}:$superPass
ppkp-postgres:5432:*:ppkp_dba_readonly:$superPass
"@
[System.IO.File]::WriteAllText($pgPass, $pgPassContent.TrimEnd() + "`n")

$superPassJson = ($superPass -replace '\\', '\\\\' -replace '"', '\"')
$serversJson = @"
{
  "Servers": {
    "1": {
      "Name": "$pgAdminServerName",
      "Group": "$pgAdminGroup",
      "Host": "sikerja-postgres",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "ppkp_dba_readonly",
      "Password": "$superPassJson",
      "PassFile": "/var/lib/pgadmin/.pgpass",
      "SSLMode": "prefer",
      "Comment": "sikerja_ppkp (dashboard-skrining), mcu_monitor (mcu-monitor)"
    }
  }
}
"@
[System.IO.File]::WriteAllText($serversGenerated, $serversJson.TrimEnd() + "`n")

$args = @("compose", "--env-file", ".env")
if ($Monitoring) { $args += "--profile"; $args += "monitoring" }

if ($Down) {
    docker @args down
    Write-Host "health-platform dihentikan."
    exit 0
}

Write-Host "Menjalankan health-platform..."
docker @args up -d

Write-Host ""
Write-Host "  PostgreSQL : localhost:$(Read-Env 'POSTGRES_PUBLISH_PORT')  (ppkp-postgres)"
Write-Host "    - sikerja_ppkp           (sikerja) - dashboard-skrining"
Write-Host "    - mcu_monitor            (mcu_monitor) - mcu-monitor"
Write-Host "  pgAdmin    : http://127.0.0.1:$(Read-Env 'PGADMIN_PORT')/"
Write-Host "    Login UI : $(Read-Env 'PGADMIN_EMAIL') / PGADMIN_PASSWORD di .env"
Write-Host "    Server PG: ppkp_dba_readonly / POSTGRES_SUPERUSER_PASSWORD di .env"
Write-Host "  Redis      : localhost:$(Read-Env 'REDIS_PUBLISH_PORT')"
Write-Host ""
Write-Host "Lalu jalankan aplikasi - lihat services/*/README.md"
