#!/usr/bin/env bash
# Install health-platform di VM produksi (Linux)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DOWN=false
MONITORING=false
for arg in "$@"; do
    case "$arg" in
        --down) DOWN=true ;;
        --monitoring) MONITORING=true ;;
    esac
done

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker belum terpasang." >&2
    exit 1
fi

if [[ ! -f .env ]]; then
    if [[ -f .env.production.example ]]; then
        cp .env.production.example .env
        echo "File .env dibuat dari .env.production.example"
        echo "Edit password di .env lalu jalankan ulang skrip ini."
        exit 1
    fi
    echo "Salin .env.production.example ke .env" >&2
    exit 1
fi

COMPOSE=(docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml)

if $DOWN; then
    "${COMPOSE[@]}" down
    echo "health-platform dihentikan."
    exit 0
fi

chmod +x "$ROOT/scripts/generate-pgadmin-config.sh"
chmod +x "$ROOT/scripts/lib/"*.sh 2>/dev/null || true
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh"
# shellcheck source=lib/check-ports.sh
source "$ROOT/scripts/lib/check-ports.sh"

load_env_file "$ROOT/.env"
check_infra_ports

"$ROOT/scripts/generate-pgadmin-config.sh"

mkdir -p storage/backups
chmod +x "$ROOT/infrastructure/backup/"*.sh 2>/dev/null || true

if $MONITORING; then
    "${COMPOSE[@]}" --profile monitoring up -d
else
    "${COMPOSE[@]}" up -d
fi

load_env_file "$ROOT/.env"

echo ""
echo "health-platform (produksi) berjalan."
echo "  PostgreSQL : 127.0.0.1:${POSTGRES_PUBLISH_PORT:-5435}  (ppkp-postgres / sikerja-postgres)"
echo "    - sikerja_ppkp  (dashboard-skrining)"
echo "    - mcu_monitor   (mcu-monitor)"
echo "  pgAdmin    : 127.0.0.1:${PGADMIN_PORT:-5050}  (SSH tunnel dari laptop)"
echo "  Redis      : 127.0.0.1:${REDIS_PUBLISH_PORT:-6380}"
echo "  MinIO      : 127.0.0.1:${MINIO_CONSOLE_PORT:-9200} (console)"
echo "  Port map   : docs/deployment/PORTS.md"
echo ""
echo "Lanjut: docs/deployment/PRODUCTION.md"
