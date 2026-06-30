#!/usr/bin/env bash
# Backup logical semua database aplikasi — host Linux/VM atau Windows (Git Bash).
# Tanpa pg_dump di host: otomatis pakai docker exec ppkp-postgres.
#
# Usage:
#   ./infrastructure/backup/backup-all.sh
#   ./infrastructure/backup/backup-all.sh 2026-06-29
#   ./infrastructure/backup/backup-all.sh --upload-minio
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../../scripts/lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh"
load_env_file "$ROOT/.env"

UPLOAD_MINIO=0
DATE=""

for arg in "$@"; do
    case "$arg" in
        --upload-minio) UPLOAD_MINIO=1 ;;
        -h|--help)
            sed -n '2,10p' "$0"
            exit 0
            ;;
        *)
            DATE="$arg"
            ;;
    esac
done

DATE="${DATE:-$(date +%F)}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT/storage/backups}/$DATE"
PGHOST="${POSTGRES_HOST:-127.0.0.1}"
PGPORT="${POSTGRES_PUBLISH_PORT:-5432}"
PGUSER="${POSTGRES_SUPERUSER:-postgres}"
export PGPASSWORD="${POSTGRES_SUPERUSER_PASSWORD:?}"

mkdir -p "$BACKUP_DIR"

pg_dump_one() {
    local db="$1"
    local out="$BACKUP_DIR/${db}.dump"

    echo "==> pg_dump $db"

    if command -v pg_dump >/dev/null 2>&1; then
        pg_dump -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -Fc "$db" > "$out"
        return 0
    fi

    if docker ps --format '{{.Names}}' | grep -qx 'ppkp-postgres'; then
        # Di dalam container, superuser lokal biasanya `postgres` (peer auth).
        docker exec ppkp-postgres pg_dump -U postgres -Fc "$db" > "$out"
        return 0
    fi

    echo "ERROR: pg_dump tidak ditemukan dan container ppkp-postgres tidak berjalan." >&2
    exit 1
}

for DB in sikerja_ppkp mcu_monitor; do
    pg_dump_one "$DB"
done

echo "Backup selesai: $BACKUP_DIR"
ls -la "$BACKUP_DIR" 2>/dev/null || dir "$BACKUP_DIR"

if [ "$UPLOAD_MINIO" = "1" ]; then
    "$ROOT/infrastructure/backup/upload-to-minio.sh" "$BACKUP_DIR"
fi
