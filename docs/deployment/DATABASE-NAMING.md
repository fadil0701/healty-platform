# Konvensi penamaan database PPKP

Satu cluster PostgreSQL (`ppkp-postgres`), **dua namespace** terpisah — jangan mencampur prefix.

## Dashboard Skrining (`dashboard-skrining`)

| Lapisan | Nilai |
|---------|--------|
| Host dari container app | `sikerja-postgres` (alias Docker) |
| Database | `sikerja_ppkp` |
| User PostgreSQL | `sikerja` |
| Password | `DASHBOARD_DB_PASSWORD` di `health-platform/.env` |
| Password di app | `PGSQL_PASSWORD` di `dashboard-skrining/.env` |

## MCU Monitor (`mcu-monitor`)

| Lapisan | Nilai |
|---------|--------|
| Host dari container app | `mcu-monitor-postgres` (alias Docker) |
| Database | `mcu_monitor` |
| User PostgreSQL | `mcu_monitor` |
| Password | `MCU_DB_PASSWORD` di `health-platform/.env` |
| Password di app | `PGSQL_PASSWORD` di `mcu-monitor/.env` |

## Infrastruktur bersama (`health-platform`)

| Item | Nilai |
|------|--------|
| Container | `ppkp-postgres` |
| Network | `ppkp-data` |
| Superuser DBA | `POSTGRES_SUPERUSER` (mis. `ppkp-dki`) |
| pgAdmin read-only | `ppkp_dba_readonly` |

**Bukan** untuk aplikasi Laravel: jangan pakai superuser di `PGSQL_USERNAME`.

## Yang tidak dipakai lagi

| Lama | Baru |
|------|------|
| `db_dashboard_skrining` / `dashboard_user` | `sikerja_ppkp` / `sikerja` |
| `db_mcu_monitor` / `mcu_user` | `mcu_monitor` / `mcu_monitor` |
| MCU pakai host `sikerja-postgres` | `mcu-monitor-postgres` |

## Diagram

```
ppkp-postgres (health-platform)
├── sikerja-postgres       → dashboard-skrining  → sikerja_ppkp / sikerja
└── mcu-monitor-postgres   → mcu-monitor         → mcu_monitor / mcu_monitor

Bridge CKG → MCU (HTTP, bukan shared DB):
  dashboard-skrining:9006/api/bridge/mcu/*  ──►  mcu-monitor (sync participants)
```

Lihat `mcu-monitor/docs/BRIDGE-AFTER-PG-MIGRATION.md`.
