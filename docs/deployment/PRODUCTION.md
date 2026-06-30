# Deployment produksi — health-platform + SIKERJA + MCU

> **Panduan lengkap instalasi + migrasi:** [INSTALL-DAN-MIGRASI.md](./INSTALL-DAN-MIGRASI.md)  
> Dokumen ini detail **infra produksi**, backup, dan troubleshooting infra.

Panduan VM Linux (`10.15.101.117`) dengan **PostgreSQL bersama**, tanpa error migrasi, pgAdmin/MinIO/Redis aman (bind `127.0.0.1`).

Panduan lokal Windows: [SETUP-FROM-SCRATCH.md](./SETUP-FROM-SCRATCH.md)

---

## Arsitektur produksi

```
VM 10.15.101.117
├── health-platform (ppkp-data)
│   ├── ppkp-postgres     → sikerja_ppkp, mcu_monitor
│   ├── ppkp-pgadmin      → 127.0.0.1:5050 (SSH tunnel)
│   ├── ppkp-redis        → 127.0.0.1:6380
│   └── ppkp-minio        → 127.0.0.1:9200 (console)
├── dashboard-skrining    → :9006  (/sikerja/ via nginx host)
└── mcu-monitor           → :9003  (/mcuppkp/ via nginx host)
```

| URL publik | URL LAN Docker |
|------------|----------------|
| `https://puspelkes.jakarta.go.id/sikerja/` | `http://10.15.101.117:9006` |
| `https://puspelkes.jakarta.go.id/mcuppkp/` | `http://10.15.101.117:9003` |

Konvensi DB: [DATABASE-NAMING.md](./DATABASE-NAMING.md)

---

## Prasyarat VM

- Docker Engine + Compose plugin
- Git clone 3 repo (sibling atau path tetap)
- Port aplikasi terbuka ke LAN: **9006**, **9003**
- Port infra **tidak** perlu publik (bind localhost via `docker-compose.prod.yml`)
- Port host infra: lihat [PORTS.md](./PORTS.md) (`5435`, `6380`, `9100`/`9200`, …)
- `postgresql-client` di host (untuk `backup-all.sh`): `apt install postgresql-client`

---

## Cadangan penuh sebelum implementasi (wajib)

Jalankan **di VM produksi** (SSH) **sebelum** health-platform / migrasi PG. Tujuannya: bisa kembali ke kondisi MySQL + konfigurasi lama jika cutover gagal.

### 1. Clone health-platform (jika belum)

```bash
cd /opt   # atau path tetap
git clone <repo-health-platform> health-platform
cd health-platform
chmod +x infrastructure/backup/*.sh scripts/*.sh
```

### 2. Backup semua (database + .env + volume MySQL + nginx host)

```bash
cd /opt/health-platform
export DASHBOARD_ROOT=/var/www/html/dashboard-skrining
export MCU_ROOT=/var/www/html/mcu-monitor

./infrastructure/backup/backup-pre-cutover.sh
# atau simpan ke NAS:
# ./infrastructure/backup/backup-pre-cutover.sh --output /mnt/nas/ppkp-backup
```

Isi folder `pre-cutover-YYYYMMDD-HHMMSS/`:

| Subfolder | Isi |
|-----------|-----|
| `database/dashboard/` | dump MySQL SIKERJA (`.sql.gz` / `.gpg`) |
| `database/mcu/` | dump MySQL MCU |
| `config/` | salinan `.env`, git commit, nginx host |
| `volumes/` | arsip volume Docker `mysql_data` (opsional) |
| `meta/` | `docker ps`, daftar volume/network |
| `MANIFEST.txt` | ringkasan + perintah restore |

### 3. Salin arsip keluar VM (sangat disarankan)

```bash
# Dari laptop
scp -r user@10.15.101.117:/opt/health-platform/storage/backups/pre-cutover-* ./
```

### 4. Verifikasi backup (tanpa menulis ke DB)

```bash
cd /var/www/html/dashboard-skrining
./deploy/restore-database.sh --verify storage/backups/database/backup-*.sql.gz

cd /var/www/html/mcu-monitor
./deploy/restore-database.sh --verify storage/backups/database/backup-*.sql.gz
```

### 5. Rollback jika implementasi gagal

```bash
cd /opt/health-platform
export BACKUP_RESTORE_YES=1   # atau ketik 'ya' saat diminta
./infrastructure/backup/restore-pre-cutover.sh storage/backups/pre-cutover-YYYYMMDD-HHMMSS
```

Skrip restore akan: pulihkan `.env`, import MySQL dari dump, hentikan health-platform jika sudah terpasang, restart stack lama.

Restore volume Docker (hanya jika dump SQL tidak cukup):

```bash
RESTORE_VOLUMES=1 BACKUP_RESTORE_YES=1 \
  ./infrastructure/backup/restore-pre-cutover.sh storage/backups/pre-cutover-YYYYMMDD-HHMMSS
```

### 6. Maintenance window (disarankan)

1. Umumkan jadwal maintenance (± 1–2 jam)
2. Backup pre-cutover + salin ke NAS
3. Uji login SIKERJA + MCU, catat jumlah sesi/peserta
4. Baru jalankan Langkah 1–3 di bawah
5. Jika gagal → rollback (langkah 5) lalu investigasi

---

## Langkah 1 — health-platform (wajib pertama)

```bash
cd /opt/health-platform   # sesuaikan path
cp .env.production.example .env
# Edit: POSTGRES_SUPERUSER_PASSWORD, DASHBOARD_DB_PASSWORD, MCU_DB_PASSWORD,
#       PGADMIN_*, MINIO_*, GRAFANA_* (jika pakai monitoring)

chmod +x scripts/*.sh
./scripts/install-production.sh
```

Verifikasi:

```bash
docker ps --filter name=ppkp-
docker network inspect ppkp-data --format '{{.Name}}'
docker exec ppkp-postgres psql -U postgres -c "\l" | grep -E 'sikerja_ppkp|mcu_monitor'
```

Opsional monitoring:

```bash
./scripts/install-production.sh --monitoring
```

### pgAdmin (produksi)

- Bind: `INFRA_BIND_HOST` di `.env` (`127.0.0.1` atau `0.0.0.0`)
- **Login wajib** (`PGADMIN_CONFIG_SERVER_MODE=True`)
- LAN: http://10.15.101.117:5050 (dengan [FIREWALL.md](./FIREWALL.md))
- SSH tunnel (jika `127.0.0.1`): `ssh -L 5050:127.0.0.1:5050 user@10.15.101.117`
- Object Explorer: **Servers → Production → PPKP PostgreSQL (produksi)**
- Database: `sikerja_ppkp`, `mcu_monitor`

Regenerate config setelah ganti password:

```bash
./scripts/generate-pgadmin-config.sh
docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate pgadmin
```

### MinIO — arsip backup

- Console LAN: http://10.15.101.117:9200 (`INFRA_BIND_HOST=0.0.0.0` + firewall)
- API S3: port `9100` (skrip, bukan browser)
- SSH tunnel (jika `127.0.0.1`): `ssh -L 9200:127.0.0.1:9200 user@VM`
- Login: `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
- Bucket: `MINIO_BACKUP_BUCKET` (default `minio.sikerja`)

```bash
cd /opt/health-platform
# Backup PG + upload MinIO
./infrastructure/backup/backup-and-archive.sh

# Hanya upload folder yang sudah ada
./infrastructure/backup/upload-to-minio.sh storage/backups/2026-06-29
```

Cron harian (contoh jam 03:30 setelah backup PG):

```cron
30 3 * * * cd /opt/health-platform && ./infrastructure/backup/backup-and-archive.sh >> storage/logs/backup-minio.log 2>&1
```

### Backup PostgreSQL

```bash
# Butuh pg_dump di host + password superuser di .env
./infrastructure/backup/backup-all.sh
# Output: storage/backups/YYYY-MM-DD/*.dump
```

---

## Langkah 2 — Dashboard Skrining (SIKERJA)

### 2a. `.env` produksi

```bash
cd /opt/dashboard-skrining
cp .env.production.example .env
# Edit: APP_KEY, PGSQL_PASSWORD (= DASHBOARD_DB_PASSWORD), domain, proxy
```

Wajib PostgreSQL:

```env
DB_CONNECTION=pgsql
PGSQL_HOST=sikerja-postgres
PGSQL_DATABASE=sikerja_ppkp
PGSQL_USERNAME=sikerja
PGSQL_PASSWORD=<sama DASHBOARD_DB_PASSWORD>
```

### 2b. Install / update

```bash
chmod +x deploy/*.sh deploy/lib/*.sh
./deploy/install.sh
```

`install.sh` memeriksa network `ppkp-data` dan memakai `docker-compose.prod.yml`.

### 2c. Migrasi MySQL → PostgreSQL (sekali)

Jika masih ada data di MySQL lama:

```bash
# Sementara: aktifkan MySQL legacy sebagai sumber
docker compose --profile mysql-legacy up -d mysql

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan migrate --database=pgsql --force

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan sikerja:migrate-mysql-to-pgsql --fresh --verify
```

Cutover: pastikan `DB_CONNECTION=pgsql` di `.env`, lalu:

```bash
./deploy/update-production.sh
```

### 2d. Fresh install (DB kosong)

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan migrate --force

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan ckg:bootstrap-admin
```

### 2e. Nginx host

Pasang snippet: `deploy/nginx-sikerja-portal-snippet.conf` → proxy `/sikerja/` ke `127.0.0.1:9006`

---

## Langkah 3 — MCU Monitor

### 3a. `.env` produksi

```bash
cd /opt/mcu-monitor
cp .env.production.example .env
```

Wajib:

```env
DB_CONNECTION=pgsql
PGSQL_HOST=mcu-monitor-postgres
PGSQL_DATABASE=mcu_monitor
PGSQL_USERNAME=mcu_monitor
PGSQL_PASSWORD=<sama MCU_DB_PASSWORD>
```

Bridge (generate API key lewat UI CKG, bukan `.env`):

```env
CKG_API_BASE_URL=http://10.15.101.117:9006
CKG_BRIDGE_INTERNAL_HOST=10.15.101.117
CKG_BRIDGE_INTERNAL_PORT=9006
CKG_BRIDGE_DISABLE_PROXY=true
```

### 3b. Install

```bash
./deploy/install.sh
```

### 3c. Migrasi MySQL → PostgreSQL (sekali)

```bash
docker compose --profile mysql-legacy up -d mysql

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan migrate --database=pgsql --force

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan mcu:migrate-mysql-to-pgsql --fresh

docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan mcu:migrate-mysql-to-pgsql --verify
```

Setelah sukses, MySQL legacy bisa dihentikan:

```bash
docker compose --profile mysql-legacy stop mysql
```

### 3d. Bridge CKG ↔ MCU

1. CKG (super admin): **Bridging Monitoring MCU** → **Generate API key baru**
2. MCU: **Integrasi CKG** → tempel key → simpan → **Tes koneksi**

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app \
  php artisan ckg-bridge:verify
```

Panduan: `mcu-monitor/docs/BRIDGE-AFTER-PG-MIGRATION.md`

### 3e. Nginx host

`deploy/nginx-mcuppkp-portal-snippet.conf` → `/mcuppkp/` ke `127.0.0.1:9003`

---

## Deploy rutin & subdomain setelah migrasi PG

Workflow **`git pull` + `./deploy/update-production.sh`** tetap sama; migrasi database **tidak** mengubah nginx host atau subdomain.

**Panduan lengkap:** [PRODUCTION-DEPLOY-WORKFLOW.md](./PRODUCTION-DEPLOY-WORKFLOW.md)

Ringkas:

- Pertahankan `APP_URL`, `ASSET_URL`, `APP_SUBPATH`, `SESSION_PATH`, `APP_PORT`, `APP_KEY` di `.env` saat cutover
- `update-production.sh` **tidak** menimpa `.env`
- health-platform hanya setup sekali; deploy harian hanya di `dashboard-skrining` dan `mcu-monitor`

---

## Checklist produksi

- [ ] `ppkp-postgres` healthy, DB `sikerja_ppkp` + `mcu_monitor` ada
- [ ] Password `DASHBOARD_DB_PASSWORD` / `MCU_DB_PASSWORD` = `PGSQL_PASSWORD` app
- [ ] Dashboard `:9006` login OK (`DB_CONNECTION=pgsql`)
- [ ] MCU `:9003` dashboard OK (tanpa error `CURDATE()` / alias SQL)
- [ ] `sikerja:migrate-mysql-to-pgsql --verify` OK (jika migrasi)
- [ ] `mcu:migrate-mysql-to-pgsql --verify` OK (jika migrasi)
- [ ] Bridge `ckg-bridge:verify` OK
- [ ] pgAdmin via SSH tunnel OK
- [ ] Backup `backup-all.sh` jalan
- [ ] Infra port tidak expose ke `0.0.0.0` (cek `ss -lntp`)

---

## Sinkron password (ringkas)

| health-platform | dashboard-skrining | mcu-monitor |
|-----------------|-------------------|-------------|
| `DASHBOARD_DB_PASSWORD` | `PGSQL_PASSWORD` | — |
| `MCU_DB_PASSWORD` | — | `PGSQL_PASSWORD` |

---

## Troubleshooting

| Gejala | Penyebab | Solusi |
|--------|----------|--------|
| `network ppkp-data not found` | health-platform belum jalan | `./scripts/install-production.sh` |
| `.env: syntax error near (` | Nilai `.env` ada spasi/`()` tanpa kutip | Pakai `"..."` atau `git pull` + skrip terbaru (`load-env.sh`) |
| `address already in use` (Redis/pg) | Port host bentrok — merge port compose tanpa `!override` | `git pull` (fix `docker-compose.prod.yml`), lalu `compose down` + `up -d`; cek `ss -lntp` |
| `docker ps` hanya `5432/tcp` tanpa `127.0.0.1:5435->` | `ports: !reset` menghapus publish | Ganti ke `!override` di `docker-compose.prod.yml`, `compose up -d --force-recreate` |
| `password authentication failed` | Password tidak sinkron | Samakan `.env` + `ALTER USER` jika perlu |
| `function curdate() does not exist` | Query MySQL di MCU | Rebuild image MCU (`docker compose build app`) |
| `column "total_participants" does not exist` | HAVING alias di PG | Sudah diperbaiki di `QueryOptimizationService` — rebuild MCU |
| pgAdmin kosong / gagal login | pgpass CRLF atau config lama | `./scripts/generate-pgadmin-config.sh` + recreate pgadmin |
| pgAdmin `/browser/` tanpa login | `SERVER_MODE=False` (mode dev) | Pakai `docker-compose.prod.yml` (`SERVER_MODE=True`), recreate pgadmin |
| `/login` JSON `auth_source_manager` | Volume lama (desktop mode) + switch server mode | `./scripts/reset-pgadmin.sh` lalu login di `http://127.0.0.1:5050/` (incognito) |
| Migrasi gagal Spatie permission | Tabel tanpa kolom `id` | `mcu:migrate-mysql-to-pgsql` versi terbaru |
| Bridge 401 | API key / header | Generate di UI CKG, header `X-Mcu-Api-Key` |
| `APP_KEY` decrypt bridge gagal | Key lama | Generate ulang API key di UI |

---

## Urutan perintah ringkas (fresh PG)

```bash
# 1. Infra
cd /opt/health-platform && cp .env.production.example .env && ./scripts/install-production.sh

# 2. Dashboard
cd /opt/dashboard-skrining && cp .env.production.example .env
./deploy/install.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app php artisan migrate --force
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app php artisan ckg:bootstrap-admin

# 3. MCU
cd /opt/mcu-monitor && cp .env.production.example .env
./deploy/install.sh
docker compose -f docker-compose.yml -f docker-compose.prod.yml exec app php artisan migrate --force

# 4. Bridge — lewat UI (generate CKG → tempel MCU)
```

---

## Dokumen terkait

| Topik | File |
|-------|------|
| **Instalasi & migrasi lengkap** | [INSTALL-DAN-MIGRASI.md](./INSTALL-DAN-MIGRASI.md) |
| **Firewall & akses LAN** | [FIREWALL.md](./FIREWALL.md) |
| **Workflow deploy & subdomain (PG)** | [PRODUCTION-DEPLOY-WORKFLOW.md](./PRODUCTION-DEPLOY-WORKFLOW.md) |
| **Port infra (lokal vs produksi)** | [PORTS.md](./PORTS.md) |
| Penamaan DB | [DATABASE-NAMING.md](./DATABASE-NAMING.md) |
| Mapping env | [APP-ENV.md](./APP-ENV.md) |
| Dashboard deploy | `dashboard-skrining/docs/DEPLOY.md` |
| MCU deploy | `mcu-monitor/docs/DEPLOY.md` |
| Migrasi PG dashboard | `dashboard-skrining/docs/MIGRATE-MYSQL-TO-POSTGRESQL.md` |
| Migrasi PG MCU | `mcu-monitor/docs/MIGRATE-MYSQL-TO-POSTGRESQL.md` |
