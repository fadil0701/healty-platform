#!/usr/bin/env bash
# Restore dari cadangan pre-cutover (kembali ke kondisi sebelum deploy PG / cutover).
#
# Usage:
#   ./infrastructure/backup/restore-pre-cutover.sh /path/to/pre-cutover-YYYYMMDD-HHMMSS
#   BACKUP_RESTORE_YES=1 ./infrastructure/backup/restore-pre-cutover.sh ...
#
# Env opsional:
#   DASHBOARD_ROOT=/var/www/html/dashboard-skrining
#   MCU_ROOT=/var/www/html/mcu-monitor
#   RESTORE_ENV=1          # restore .env (default 1)
#   RESTORE_DATABASE=1     # restore MySQL dari dump (default 1)
#   RESTORE_VOLUMES=0      # restore volume tar (default 0 — hati-hati, timpa data)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

DASHBOARD_ROOT="${DASHBOARD_ROOT:-/var/www/html/dashboard-skrining}"
MCU_ROOT="${MCU_ROOT:-/var/www/html/mcu-monitor}"
RESTORE_ENV="${RESTORE_ENV:-1}"
RESTORE_DATABASE="${RESTORE_DATABASE:-1}"
RESTORE_VOLUMES="${RESTORE_VOLUMES:-0}"

usage() {
    sed -n '2,14p' "$0"
}

BACKUP_DIR="${1:-}"
if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
    usage
    echo ""
    echo "ERROR: Folder backup tidak valid: ${BACKUP_DIR:-<kosong>}" >&2
    exit 1
fi

if [ "${BACKUP_RESTORE_YES:-}" != "1" ]; then
    echo "PERINGATAN: Operasi ini akan mengembalikan konfigurasi/database ke snapshot:"
    echo "  $BACKUP_DIR"
    echo ""
    echo "Pastikan stack dihentikan atau maintenance mode aktif."
    printf "Ketik 'ya' untuk lanjut: "
    read -r confirm
    if [ "$confirm" != "ya" ]; then
        echo "Dibatalkan."
        exit 1
    fi
fi

echo "==> Restore pre-cutover dari $BACKUP_DIR"

restore_env_file() {
    local label="$1"
    local app_root="$2"
    local src="$BACKUP_DIR/config/$label/.env"

    [ "$RESTORE_ENV" = "1" ] || return 0
    [ -f "$src" ] || { echo "Lewati .env $label (tidak ada)"; return 0; }

    if [ -f "$app_root/.env" ]; then
        cp -a "$app_root/.env" "$app_root/.env.before-restore-$(date +%Y%m%d-%H%M%S)"
    fi
    cp -a "$src" "$app_root/.env"
    echo "    .env $label dipulihkan"
}

find_latest_dump() {
    local dir="$1"
    ls -t "$dir"/backup-*.{sql.gz,sql.gz.gpg,sql} 2>/dev/null | head -1 || true
}

restore_app_database() {
    local label="$1"
    local app_root="$2"

    [ "$RESTORE_DATABASE" = "1" ] || return 0
    [ -d "$app_root" ] || return 0

    local dump_dir="$BACKUP_DIR/database/$label"
    local dump
    dump="$(find_latest_dump "$dump_dir")"

    if [ -z "$dump" ]; then
        echo "PERINGATAN: Tidak ada dump untuk $label di $dump_dir"
        return 0
    fi

    echo "==> Restore database $label"
    echo "    File: $dump"

    (
        cd "$app_root"
        # Pastikan MySQL legacy jalan untuk restore
        docker compose --profile mysql-legacy up -d mysql 2>/dev/null \
            || docker compose up -d mysql 2>/dev/null \
            || true

        if [ -x "./deploy/restore-database.sh" ]; then
            BACKUP_RESTORE_YES=1 ./deploy/restore-database.sh "$dump"
        else
            echo "ERROR: deploy/restore-database.sh tidak ada di $app_root" >&2
            exit 1
        fi
    )
}

restore_mysql_volume() {
    local label="$1"
    local app_root="$2"
    local archive

    [ "$RESTORE_VOLUMES" = "1" ] || return 0
    [ -d "$app_root" ] || return 0

    archive="$(ls -t "$BACKUP_DIR/volumes/${label}"-mysql_data-*.tar.gz 2>/dev/null | head -1 || true)"
    [ -n "$archive" ] || return 0

    local volume_name
    volume_name="$(grep -E "^volume_${label}=" "$BACKUP_DIR/MANIFEST.txt" 2>/dev/null | cut -d= -f2- || true)"
    if [ -z "$volume_name" ]; then
        volume_name="$(docker volume ls --format '{{.Name}}' | grep -E "$(basename "$app_root").*mysql_data|mysql_data" | head -1 || true)"
    fi

    if [ -z "$volume_name" ]; then
        echo "PERINGATAN: Volume MySQL $label tidak ditemukan"
        return 0
    fi

    echo "==> Restore volume $volume_name dari $archive"
    docker compose -f "$app_root/docker-compose.yml" stop mysql 2>/dev/null || true
    docker run --rm \
        -v "${volume_name}:/data" \
        -v "$BACKUP_DIR/volumes:/backup:ro" \
        alpine:3.20 \
        sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf /backup/$(basename "$archive") -C /data"
}

restart_apps() {
    echo "==> Restart stack aplikasi"

    if [ -d "$DASHBOARD_ROOT" ]; then
        (
            cd "$DASHBOARD_ROOT"
            docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d 2>/dev/null \
                || docker compose up -d
        ) || true
    fi

    if [ -d "$MCU_ROOT" ]; then
        (
            cd "$MCU_ROOT"
            docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d 2>/dev/null \
                || docker compose up -d
        ) || true
    fi

    if [ -f "$ROOT/.env" ] && [ -f "$ROOT/docker-compose.yml" ]; then
        (
            cd "$ROOT"
            docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml down 2>/dev/null || true
        ) || true
        echo "    health-platform dihentikan (kembali ke MySQL legacy)"
    fi
}

restore_env_file dashboard "$DASHBOARD_ROOT"
restore_env_file mcu "$MCU_ROOT"

if [ -f "$BACKUP_DIR/config/health-platform.env" ] && [ -d "$ROOT" ]; then
  cp -a "$BACKUP_DIR/config/health-platform.env" "$ROOT/.env.before-cutover-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
fi

restore_mysql_volume dashboard "$DASHBOARD_ROOT"
restore_mysql_volume mcu "$MCU_ROOT"

restore_app_database dashboard "$DASHBOARD_ROOT"
restore_app_database mcu "$MCU_ROOT"

restart_apps

echo ""
echo "==> Restore selesai."
echo "    Verifikasi:"
echo "      curl -fsS http://127.0.0.1:9006/up"
echo "      curl -fsS http://127.0.0.1:9003/up"
echo "    Login UI + cek jumlah data vs sebelum cutover."
