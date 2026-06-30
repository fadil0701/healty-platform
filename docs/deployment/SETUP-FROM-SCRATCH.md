# Setup dari awal — health-platform + Dashboard Skrining + MCU Monitor

> **Panduan lengkap (produksi + migrasi):** [INSTALL-DAN-MIGRASI.md](./INSTALL-DAN-MIGRASI.md)  
> Dokumen ini fokus **setup lokal Windows** (ringkas).

Panduan urutan instalasi lokal (Windows + Docker Desktop) untuk stack PPKP DKI.

## Prasyarat

| Item | Keterangan |
|------|------------|
| Docker Desktop | Aktif, context `desktop-linux` |
| Repo sibling | Semua di folder yang sama, mis. `E:\laragon\www\` |
| Port bebas | Lokal: `5432`, `6379`, `9000`/`9001` — Produksi VM: [PORTS.md](./PORTS.md) (`5435`, `6380`, `9100`/`9200`) |

Struktur folder:

```
E:\laragon\www\
├── health-platform\      ← infrastruktur (PostgreSQL, pgAdmin, Redis, …)
├── dashboard-skrining\   ← SIKERJA / CKG, port 9006
└── mcu-monitor\          ← Monitoring MCU, port 9003
```

---

## Diagram alur

```
Langkah 1  health-platform     ppkp-postgres + network ppkp-data
              │
Langkah 2  dashboard-skrining  → sikerja_ppkp / user sikerja
              │
Langkah 3  mcu-monitor         → mcu_monitor / user mcu_monitor
              │
Langkah 4  Bridge CKG↔MCU      HTTP API (bukan shared DB)
```

Konvensi penamaan: [DATABASE-NAMING.md](./DATABASE-NAMING.md)  
Mapping `.env`: [APP-ENV.md](./APP-ENV.md)

---

## Langkah 0 — Sinkronkan password (sekali)

Password **harus sama** antara `health-platform/.env` dan `.env` masing-masing aplikasi.

| health-platform | dashboard-skrining | mcu-monitor |
|-----------------|-------------------|-------------|
| `DASHBOARD_DB_PASSWORD` | `PGSQL_PASSWORD` | — |
| `MCU_DB_PASSWORD` | — | `PGSQL_PASSWORD` |

Contoh (ganti sesuai kebijakan Anda):

```env
# health-platform/.env
DASHBOARD_DB_PASSWORD=Ppkp-Dev-2026!
MCU_DB_PASSWORD=Ppkp-Dev-2026!
```

```env
# dashboard-skrining/.env
PGSQL_HOST=sikerja-postgres
PGSQL_DATABASE=sikerja_ppkp
PGSQL_USERNAME=sikerja
PGSQL_PASSWORD=Ppkp-Dev-2026!

# mcu-monitor/.env
PGSQL_HOST=mcu-monitor-postgres
PGSQL_DATABASE=mcu_monitor
PGSQL_USERNAME=mcu_monitor
PGSQL_PASSWORD=Ppkp-Dev-2026!
```

> **Jangan** pakai superuser (`ppkp-dki` / `postgres`) di `PGSQL_USERNAME` aplikasi Laravel.

---

## Langkah 1 — Infrastruktur (`health-platform`)

```powershell
cd E:\laragon\www\health-platform
Copy-Item .env.example .env
# Edit .env: POSTGRES_SUPERUSER_PASSWORD, DASHBOARD_DB_PASSWORD, MCU_DB_PASSWORD, PGADMIN_*
.\scripts\install-local.ps1
```

Verifikasi:

```powershell
docker ps --filter name=ppkp-
docker network ls | findstr ppkp-data
```

| Layanan | URL / host |
|---------|------------|
| PostgreSQL | `localhost:5432` (container `ppkp-postgres`) |
| pgAdmin | http://127.0.0.1:5050 |
| Redis | `localhost:6379` |
| MinIO Console | http://127.0.0.1:9001 |

Dari container aplikasi, host PG memakai **alias Docker** (bukan `localhost`):

- Dashboard → `sikerja-postgres`
- MCU → `mcu-monitor-postgres`

---

## Langkah 2 — Dashboard Skrining (`dashboard-skrining`)

### 2a. Install stack (MySQL + app)

```powershell
cd E:\laragon\www\dashboard-skrining
.\deploy\install-local.ps1 -InitEnv    # buat .env dari template (sekali)
# Edit .env: sesuaikan PGSQL_* (lihat Langkah 0)
.\deploy\install-local.ps1             # build frontend + docker compose up
```

### 2b. Admin pertama

```powershell
docker compose exec app php artisan ckg:bootstrap-admin
```

### 2c. Migrasi MySQL → PostgreSQL

Pastikan MySQL container jalan (`docker compose ps`). Di `.env` tetap `DB_CONNECTION=mysql` sampai cutover.

```powershell
docker compose exec app php artisan migrate --database=pgsql --force
docker compose exec app php artisan sikerja:migrate-mysql-to-pgsql --fresh --verify
```

### 2d. Cutover ke PostgreSQL

Edit `.env`:

```env
DB_CONNECTION=pgsql
```

```powershell
docker compose exec app php artisan config:clear
docker compose up -d --force-recreate app queue scheduler
```

Verifikasi:

```powershell
docker compose exec app php artisan tinker --execute="echo DB::connection()->getDatabaseName();"
# Harus: sikerja_ppkp
```

Panduan detail: `dashboard-skrining/docs/POSTGRESQL-SELF-HOSTED.md`, `docs/MIGRATE-MYSQL-TO-POSTGRESQL.md`

---

## Langkah 3 — MCU Monitor (`mcu-monitor`)

Satu skrip mengorkestrasi MySQL legacy + migrasi PG:

```powershell
cd E:\laragon\www\mcu-monitor
.\deploy\install-migrate-pgsql.ps1 -InitEnv   # opsional: buat .env dari template
# Edit .env: PGSQL_*, APP_KEY, CKG_* (bridge)
.\deploy\install-migrate-pgsql.ps1
```

Skrip di atas:

1. Memastikan `ppkp-data` ada (jalankan health-platform jika belum)
2. Start MySQL (`profile mysql-legacy`) sebagai sumber data
3. Build & start `app`, `queue`, `scheduler`
4. `migrate --database=pgsql`
5. `mcu:migrate-mysql-to-pgsql --fresh` + `--verify`
6. `ckg-bridge:verify` (peringatan jika bridge belum aktif)

Verifikasi:

```powershell
docker compose exec app php artisan tinker --execute="echo App\Models\Participant::count();"
```

Panduan detail: `mcu-monitor/docs/MIGRATE-MYSQL-TO-POSTGRESQL.md`

---

## Langkah 4 — Bridge CKG ↔ MCU

Bridging memakai **HTTP API**, bukan koneksi database silang.

### Dashboard (sumber API)

1. Login super admin → **Integrasi → Bridging Monitoring MCU**
2. Klik **Generate API key baru** — salin key yang ditampilkan (sekali)
3. Endpoint: `http://127.0.0.1:9006/api/bridge/mcu/health`

### MCU (konsumen)

1. **Integrasi CKG** → tempel API key dari langkah di atas
2. URL: `http://host.docker.internal:9006`, header `X-Mcu-Api-Key`
3. Aktifkan konfigurasi database → Simpan → Tes koneksi

Panduan: `mcu-monitor/docs/BRIDGE-AFTER-PG-MIGRATION.md`

---

## Checklist selesai

- [ ] `docker ps` — `ppkp-postgres`, `dashboard-skrining-*`, `monitoring-mcu-*` running
- [ ] Dashboard http://127.0.0.1:9006 — login OK
- [ ] MCU http://127.0.0.1:9003 — login OK
- [ ] pgAdmin http://127.0.0.1:5050 — lihat DB `sikerja_ppkp` dan `mcu_monitor`
- [ ] `sikerja:migrate-mysql-to-pgsql --verify` (dashboard) — OK
- [ ] `mcu:migrate-mysql-to-pgsql --verify` (MCU) — OK
- [ ] `ckg-bridge:verify` (MCU) — OK
- [ ] Sync peserta MCU > 0 (jika data CKG memenuhi filter eligibility)

---

## Reset total (mulai dari nol)

**Hati-hati:** menghapus volume = data hilang.

```powershell
# Hentikan semua
cd E:\laragon\www\mcu-monitor
docker compose --profile mysql-legacy down -v

cd E:\laragon\www\dashboard-skrining
docker compose down -v

cd E:\laragon\www\health-platform
.\scripts\install-local.ps1 -Down
docker volume rm health-platform_postgres_data 2>$null   # nama volume bisa beda — cek: docker volume ls

# Ulangi Langkah 1 → 4
```

Jika hanya ganti password user aplikasi (tanpa reset volume):

```powershell
docker exec ppkp-postgres psql -U postgres -c "ALTER USER sikerja WITH PASSWORD 'Ppkp-Dev-2026!';"
docker exec ppkp-postgres psql -U postgres -c "ALTER USER mcu_monitor WITH PASSWORD 'Ppkp-Dev-2026!';"
```

Lalu recreate container app di kedua repo dan `config:clear`.

---

## Monitoring opsional

```powershell
cd E:\laragon\www\health-platform
.\scripts\install-local.ps1 -Monitoring
```

Grafana: http://127.0.0.1:3000 (atau `GRAFANA_PORT` di `.env`)

---

## Troubleshooting singkat

| Gejala | Solusi |
|--------|--------|
| `network ppkp-data not found` | Jalankan `health-platform\scripts\install-local.ps1` dulu |
| `password authentication failed` | Samakan `DASHBOARD_DB_PASSWORD` / `MCU_DB_PASSWORD` ↔ `PGSQL_PASSWORD`; `ALTER USER` jika volume lama |
| MCU restart loop | Cek `PGSQL_PASSWORD` vs password di PostgreSQL |
| Bridge 401 | Generate ulang di CKG (Bridging MCU), tempel ke MCU (Integrasi CKG) |
| Bridge connection refused | Dashboard harus jalan di port 9006; cek `CKG_API_BASE_URL` |
| Port 5432 bentrok (lokal) | Set `POSTGRES_PUBLISH_PORT` di health-platform `.env` |
| Port produksi VM | Pakai `.env.production.example` + `docker-compose.prod.yml` — lihat [PORTS.md](./PORTS.md) |

---

## Urutan ringkas (copy-paste)

```powershell
# 1. Infrastruktur
cd E:\laragon\www\health-platform
Copy-Item .env.example .env   # edit password
.\scripts\install-local.ps1

# 2. Dashboard
cd E:\laragon\www\dashboard-skrining
.\deploy\install-local.ps1 -InitEnv
# edit .env PGSQL_*
.\deploy\install-local.ps1
docker compose exec app php artisan ckg:bootstrap-admin
docker compose exec app php artisan migrate --database=pgsql --force
docker compose exec app php artisan sikerja:migrate-mysql-to-pgsql --fresh --verify
# ubah DB_CONNECTION=pgsql di .env, lalu:
docker compose exec app php artisan config:clear
docker compose up -d --force-recreate app queue scheduler

# 3. MCU
cd E:\laragon\www\mcu-monitor
.\deploy\install-migrate-pgsql.ps1 -InitEnv
# edit .env PGSQL_* + CKG_*
.\deploy\install-migrate-pgsql.ps1

# 4. Bridge (UI: generate di CKG, tempel di MCU Integrasi CKG)
docker compose exec app php artisan ckg-bridge:verify
docker compose exec app php artisan ckg:sync-participants-from-ckg --no-interaction
```
