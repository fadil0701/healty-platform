# Mapping `.env` aplikasi ↔ health-platform

Lihat konvensi lengkap: [DATABASE-NAMING.md](./DATABASE-NAMING.md)

| Repo | File konfigurasi app |
|------|----------------------|
| Infrastruktur | `health-platform/.env` |
| Dashboard Skrining | `dashboard-skrining/.env` |
| MCU Monitor | `mcu-monitor/.env` |

## Dashboard Skrining — prefix `sikerja`

| `dashboard-skrining/.env` | `health-platform/.env` |
|---------------------------|------------------------|
| `PGSQL_HOST=sikerja-postgres` | alias `ppkp-postgres` |
| `PGSQL_DATABASE=sikerja_ppkp` | — |
| `PGSQL_USERNAME=sikerja` | — |
| `PGSQL_PASSWORD=...` | `DASHBOARD_DB_PASSWORD` |

## MCU Monitor — prefix `mcu_monitor`

| `mcu-monitor/.env` | `health-platform/.env` |
|--------------------|------------------------|
| `PGSQL_HOST=mcu-monitor-postgres` | alias `ppkp-postgres` |
| `PGSQL_DATABASE=mcu_monitor` | — |
| `PGSQL_USERNAME=mcu_monitor` | — |
| `PGSQL_PASSWORD=...` | `MCU_DB_PASSWORD` |

## pgAdmin / DBA

| Item | Nilai |
|------|--------|
| Host UI | `sikerja-postgres` atau `ppkp-postgres` |
| Superuser | `POSTGRES_SUPERUSER` |
| Read-only | `ppkp_dba_readonly` |

## Migrasi penamaan lama

```powershell
cd E:\laragon\www\health-platform

# Dashboard: db_dashboard_skrining → sikerja_ppkp
docker exec -e DASHBOARD_DB_PASSWORD=Ppkp-Dev-2026! -e POSTGRES_USER=postgres -e POSTGRES_DB=postgres -e POSTGRES_SUPERUSER_PASSWORD=Ppkp-DKI@2026!! ppkp-postgres `
  bash /docker-entrypoint-initdb.d/20-migrate-to-sikerja.sh

# MCU: db_mcu_monitor → mcu_monitor
docker exec -e MCU_DB_PASSWORD=Ppkp-Dev-2026! -e POSTGRES_USER=postgres -e POSTGRES_DB=postgres ppkp-postgres `
  bash /docker-entrypoint-initdb.d/21-migrate-mcu-naming.sh

docker compose up -d --force-recreate postgres
.\scripts\install-local.ps1
```
