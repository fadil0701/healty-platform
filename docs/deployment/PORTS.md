# Port health-platform

Port **host** (akses dari VM / SSH tunnel). Aplikasi di Docker (`dashboard-skrining`, `mcu-monitor`) memakai **hostname + port internal** (`sikerja-postgres:5432`), bukan port publish host.

## Produksi VM (`docker-compose.prod.yml` + `.env.production.example`)

| Layanan | Variabel `.env` | Host (localhost VM) | Port container |
|---------|-----------------|---------------------|----------------|
| PostgreSQL | `POSTGRES_PUBLISH_PORT` | **5435** | 5432 |
| pgAdmin | `PGADMIN_PORT` | **5050** | 80 |
| Redis | `REDIS_PUBLISH_PORT` | **6380** | 6379 |
| MinIO API | `MINIO_API_PORT` | **9100** | 9000 |
| MinIO Console | `MINIO_CONSOLE_PORT` | **9200** | 9001 |
| Prometheus | `PROMETHEUS_PORT` | **9090** | 9090 |
| Grafana | `GRAFANA_PORT` | **3200** | 3000 |
| Loki | `LOKI_PORT` | **3100** | 3100 |

SSH tunnel contoh:

```bash
ssh -L 5050:127.0.0.1:5050 -L 9200:127.0.0.1:9200 user@10.15.101.117
# pgAdmin: http://127.0.0.1:5050
# MinIO:   http://127.0.0.1:9200
```

`pg_dump` dari host VM:

```bash
pg_dump -h 127.0.0.1 -p 5435 -U ppkp-dki -Fc sikerja_ppkp > backup.dump
```

## Lokal Windows (`docker-compose.yml` saja, tanpa `docker-compose.prod.yml`)

| Layanan | Default `.env.example` | URL |
|---------|------------------------|-----|
| PostgreSQL | `5432` | `localhost:5432` |
| pgAdmin | `5050` | http://127.0.0.1:5050 |
| Redis | `6379` | `localhost:6379` |
| MinIO API | `9000` | http://127.0.0.1:9000 |
| MinIO Console | `9001` | http://127.0.0.1:9001 |
| Grafana | `3000` | http://127.0.0.1:3000 |
| Loki | `3100` | — |

## Aplikasi (tidak berubah)

| App | `APP_PORT` | Subpath |
|-----|------------|---------|
| dashboard-skrining | `9006` | `/sikerja/` |
| mcu-monitor | `9003` | `/mcuppkp/` |

`PGSQL_PORT=5432` di `.env` aplikasi = port **di dalam** network Docker `ppkp-data`, bukan `POSTGRES_PUBLISH_PORT`.
