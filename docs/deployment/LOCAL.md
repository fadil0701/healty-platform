# Deployment lokal (Laragon + Docker Desktop)

**Panduan lengkap dari nol:** [SETUP-FROM-SCRATCH.md](./SETUP-FROM-SCRATCH.md)  
**Produksi VM Linux:** [PRODUCTION.md](./PRODUCTION.md)

## Urutan singkat

1. `health-platform` — infrastruktur (`ppkp-postgres`, `ppkp-pgadmin`, `ppkp-redis`, …)
2. `dashboard-skrining` — port 9006
3. `mcu-monitor` — port 9003
4. Bridge CKG ↔ MCU (HTTP API)

## Perintah cepat

```powershell
# 1. Infrastruktur
cd E:\laragon\www\health-platform
Copy-Item .env.example .env   # isi password
.\scripts\install-local.ps1

# 2. Dashboard
cd E:\laragon\www\dashboard-skrining
.\deploy\install-local.ps1 -InitEnv   # sekali
.\deploy\install-local.ps1
docker compose exec app php artisan ckg:bootstrap-admin

# 3. MCU (+ migrasi PG)
cd E:\laragon\www\mcu-monitor
.\deploy\install-migrate-pgsql.ps1
```

Migrasi MySQL→PG dashboard: lihat [SETUP-FROM-SCRATCH.md](./SETUP-FROM-SCRATCH.md) langkah 2c–2d.

## URL

### MinIO — arsip backup

- Console: http://127.0.0.1:9001 (lokal) atau SSH tunnel produksi
- Login: `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` dari `health-platform/.env`
- Bucket disarankan: **`minio.sikerja`** (`MINIO_BACKUP_BUCKET`)

**Backup PG + upload ke MinIO (satu perintah):**

```powershell
cd E:\laragon\www\health-platform
.\scripts\backup-and-archive.ps1
```

**Hanya upload folder backup yang sudah ada:**

```powershell
.\scripts\archive-backups-to-minio.ps1
# atau tanggal tertentu:
.\scripts\archive-backups-to-minio.ps1 -Date 2026-06-29
```

Git Bash / Linux:

```bash
./infrastructure/backup/backup-and-archive.sh
./infrastructure/backup/upload-to-minio.sh storage/backups/2026-06-29
```

Struktur di bucket: `minio.sikerja/pg-backups/YYYY-MM-DD/*.dump`

| Layanan | URL |
|---------|-----|
| Dashboard Skrining | http://127.0.0.1:9006 |
| MCU Monitor | http://127.0.0.1:9003 |
| pgAdmin | http://127.0.0.1:5050 |
| MinIO Console | http://127.0.0.1:9001 |
| Grafana (profile monitoring) | http://127.0.0.1:3000 |

## Dokumen terkait

| Topik | File |
|-------|------|
| **Port infra (lokal vs produksi)** | [PORTS.md](./PORTS.md) |
| **Produksi VM** | [PRODUCTION.md](./PRODUCTION.md) |
| **Deploy rutin & subdomain (PG)** | [PRODUCTION-DEPLOY-WORKFLOW.md](./PRODUCTION-DEPLOY-WORKFLOW.md) |
| Setup lengkap | [SETUP-FROM-SCRATCH.md](./SETUP-FROM-SCRATCH.md) |
| Penamaan DB | [DATABASE-NAMING.md](./DATABASE-NAMING.md) |
| Mapping `.env` | [APP-ENV.md](./APP-ENV.md) |
| Dashboard PG | `dashboard-skrining/docs/POSTGRESQL-SELF-HOSTED.md` |
| MCU migrasi | `mcu-monitor/docs/MIGRATE-MYSQL-TO-POSTGRESQL.md` |
| Bridge | `mcu-monitor/docs/BRIDGE-AFTER-PG-MIGRATION.md` |
