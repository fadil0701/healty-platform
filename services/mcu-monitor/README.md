# MCU Monitor

Repo: `../../../mcu-monitor` — env: `mcu-monitor/.env`

Penamaan database: prefix **`mcu_monitor`** (bukan `sikerja`).

| Item | Nilai |
|------|--------|
| Host | `mcu-monitor-postgres` |
| Database | `mcu_monitor` |
| User | `mcu_monitor` |
| Password | `MCU_DB_PASSWORD` |

Port: sesuaikan `APP_PORT` di `.env` (default **9003**)

Migrasi data: `docs/MIGRATE-MYSQL-TO-POSTGRESQL.md` atau `deploy/install-migrate-pgsql.ps1`
