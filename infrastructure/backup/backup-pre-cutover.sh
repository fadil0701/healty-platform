#!/usr/bin/env bash
# Cadangan penuh sebelum cutover PostgreSQL / deploy besar di VM produksi.
# Jalankan di host Linux (SSH ke 10.15.101.117), BUKAN dari laptop Windows.
#
# Usage:
#   ./infrastructure/backup/backup-pre-cutover.sh
#   ./infrastructure/backup/backup-pre-cutover.sh --output /mnt/nas/ppkp-backup
#
# Env opsional:
#   DASHBOARD_ROOT=/var/www/html/dashboard-skrining
#   MCU_ROOT=/var/www/html/mcu-monitor
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

DASHBOARD_ROOT="${DASHBOARD_ROOT:-/var/www/html/dashboard-skrining}"
MCU_ROOT="${MCU_ROOT:-/var/www/html/mcu-monitor}"
OUTPUT_BASE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        -o|--output)
            OUTPUT_BASE="${2:?}"
            shift 2
            ;;
        *)
            echo "Argumen tidak dikenal: $1" >&2
            exit 1
            ;;
    esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${OUTPUT_BASE:-$ROOT/storage/backups}/pre-cutover-${STAMP}"
mkdir -p "$BACKUP_DIR"/{database,config,meta,volumes}

echo "==> Cadangan pre-cutover"
echo "    Folder: $BACKUP_DIR"
echo "    Dashboard: $DASHBOARD_ROOT"
echo "    MCU:       $MCU_ROOT"
echo ""

manifest="$BACKUP_DIR/MANIFEST.txt"
{
    echo "pre-cutover backup"
    echo "created: $(date -Is)"
    echo "host: $(hostname)"
    echo "user: $(whoami)"
    echo "backup_dir: $BACKUP_DIR"
    echo "dashboard_root: $DASHBOARD_ROOT"
    echo "mcu_root: $MCU_ROOT"
} > "$manifest"

backup_app_database() {
    local label="$1"
    local app_root="$2"

    if [ ! -d "$app_root" ]; then
        echo "PERINGATAN: Folder tidak ada — lewati DB $label: $app_root" | tee -a "$manifest"
        return 0
    fi

    if [ ! -f "$app_root/.env" ]; then
        echo "PERINGATAN: .env tidak ada — lewati DB $label" | tee -a "$manifest"
        return 0
    fi

    echo "==> Database $label"
    local dest="$BACKUP_DIR/database/$label"
    mkdir -p "$dest"

    if [ -x "$app_root/deploy/backup-database.sh" ]; then
        (
            cd "$app_root"
            BACKUP_MODE=docker \
            BACKUP_DIR="$dest" \
            BACKUP_RETENTION_DAYS=0 \
            ./deploy/backup-database.sh
        ) || {
            echo "PERINGATAN: backup-database.sh gagal untuk $label — coba mysqldump manual" | tee -a "$manifest"
            backup_mysql_manual "$label" "$app_root" "$dest"
        }
    else
        backup_mysql_manual "$label" "$app_root" "$dest"
    fi
}

backup_mysql_manual() {
    local label="$1"
    local app_root="$2"
    local dest="$3"

    local root_pass db_name
    root_pass="$(grep -E '^MYSQL_ROOT_PASSWORD=' "$app_root/.env" | tail -1 | cut -d= -f2- | tr -d ' \"'"'"'')"
    db_name="$(grep -E '^DB_DATABASE=' "$app_root/.env" | tail -1 | cut -d= -f2- | tr -d ' \"'"'"'')"
    db_name="${db_name:-$( [ "$label" = "dashboard" ] && echo ckg_ppkp || echo monitoring_mcu )}"

    if [ -z "$root_pass" ]; then
        echo "ERROR: MYSQL_ROOT_PASSWORD kosong di $app_root/.env" | tee -a "$manifest"
        return 1
    fi

    local out="$dest/backup-${db_name}-manual-${STAMP}.sql"
    echo "    mysqldump manual -> $out"
    (
        cd "$app_root"
        docker compose exec -T mysql mysqldump \
            --single-transaction --routines --triggers --events \
            --default-character-set=utf8mb4 \
            -u root -p"${root_pass}" "${db_name}" > "$out"
    )
    gzip -f "$out"
}

backup_app_config() {
    local label="$1"
    local app_root="$2"
    local dest="$BACKUP_DIR/config/$label"
    mkdir -p "$dest"

    [ -f "$app_root/.env" ] && cp -a "$app_root/.env" "$dest/.env"
    [ -f "$app_root/docker-compose.yml" ] && cp -a "$app_root/docker-compose.yml" "$dest/"
    [ -f "$app_root/docker-compose.prod.yml" ] && cp -a "$app_root/docker-compose.prod.yml" "$dest/"

    if [ -d "$app_root/.git" ]; then
        git -C "$app_root" rev-parse HEAD > "$dest/git-commit.txt" 2>/dev/null || true
        git -C "$app_root" status --short > "$dest/git-status.txt" 2>/dev/null || true
    fi
}

backup_mysql_volume() {
    local label="$1"
    local app_root="$2"

    [ -d "$app_root" ] || return 0

    local project volume_name
    project="$(basename "$app_root")"
    volume_name="$(docker volume ls --format '{{.Name}}' | grep -E "${project}.*mysql_data|mysql_data" | head -1 || true)"

    if [ -z "$volume_name" ]; then
        echo "    Volume MySQL $label: tidak ditemukan (mungkin sudah PG)" | tee -a "$manifest"
        return 0
    fi

    echo "    Volume $volume_name"
    docker run --rm \
        -v "${volume_name}:/data:ro" \
        -v "$BACKUP_DIR/volumes:/backup" \
        alpine:3.20 \
        tar czf "/backup/${label}-mysql_data-${STAMP}.tar.gz" -C /data .
    echo "volume_${label}=${volume_name}" >> "$manifest"
}

backup_host_nginx() {
    local dest="$BACKUP_DIR/config/nginx-host"
    mkdir -p "$dest"

    for path in \
        /etc/nginx/sites-enabled \
        /etc/nginx/conf.d \
        /etc/nginx/snippets; do
        if [ -d "$path" ]; then
            tar czf "$dest/$(basename "$path").tar.gz" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null || true
        fi
    done
}

save_docker_state() {
    docker ps -a --no-trunc > "$BACKUP_DIR/meta/docker-ps.txt" 2>/dev/null || true
    docker volume ls > "$BACKUP_DIR/meta/docker-volumes.txt" 2>/dev/null || true
    docker network ls > "$BACKUP_DIR/meta/docker-networks.txt" 2>/dev/null || true

    [ -f "$ROOT/.env" ] && cp -a "$ROOT/.env" "$BACKUP_DIR/config/health-platform.env"

    if [ -d "$ROOT/.git" ]; then
        git -C "$ROOT" rev-parse HEAD > "$BACKUP_DIR/meta/health-platform-git-commit.txt" 2>/dev/null || true
    fi
}

backup_app_database dashboard "$DASHBOARD_ROOT"
backup_app_database mcu "$MCU_ROOT"

echo "==> Konfigurasi aplikasi"
backup_app_config dashboard "$DASHBOARD_ROOT"
backup_app_config mcu "$MCU_ROOT"
backup_host_nginx

echo "==> Volume MySQL (opsional, bisa besar)"
backup_mysql_volume dashboard "$DASHBOARD_ROOT"
backup_mysql_volume mcu "$MCU_ROOT"

echo "==> State Docker"
save_docker_state

{
    echo ""
    echo "restore:"
    echo "  cd $ROOT"
    echo "  ./infrastructure/backup/restore-pre-cutover.sh $BACKUP_DIR"
    echo ""
    echo "verify database:"
    echo "  ls -la $BACKUP_DIR/database/*/"
} >> "$manifest"

echo ""
echo "==> Selesai: $BACKUP_DIR"
echo "    Salin folder ini ke NAS/laptop sebelum cutover:"
echo "      scp -r user@10.15.101.117:$BACKUP_DIR ./"
echo ""
cat "$manifest"
