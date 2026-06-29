#!/usr/bin/env bash
# Upload arsip backup lokal ke bucket MinIO.
#
# Usage:
#   ./infrastructure/backup/upload-to-minio.sh
#   ./infrastructure/backup/upload-to-minio.sh storage/backups/2026-06-29
#   ./infrastructure/backup/upload-to-minio.sh storage/backups/2026-06-29 pg-backups/2026-06-29
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=lib/minio.sh
source "$ROOT/infrastructure/backup/lib/minio.sh"

minio_load_env "$ROOT"

LOCAL_PATH="${1:-}"
REMOTE_PREFIX="${2:-}"

if [ -z "$LOCAL_PATH" ]; then
    DATE="$(date +%F)"
    LOCAL_PATH="${BACKUP_DIR:-$ROOT/storage/backups}/$DATE"
    REMOTE_PREFIX="${REMOTE_PREFIX:-${MINIO_BACKUP_PREFIX:-pg-backups}/$DATE}"
elif [ -z "$REMOTE_PREFIX" ]; then
    basename_path="$(basename "$LOCAL_PATH")"
    REMOTE_PREFIX="${MINIO_BACKUP_PREFIX:-pg-backups}/$basename_path"
fi

if [ ! -d "$LOCAL_PATH" ]; then
    echo "ERROR: Folder backup tidak ada: $LOCAL_PATH" >&2
    echo "Jalankan dulu: ./infrastructure/backup/backup-all.sh" >&2
    exit 1
fi

minio_upload_dir "$LOCAL_PATH" "$REMOTE_PREFIX"

echo ""
echo "Selesai. Buka MinIO Console: http://127.0.0.1:${MINIO_CONSOLE_PORT:-9001}"
echo "Bucket: ${MINIO_BACKUP_BUCKET} → ${REMOTE_PREFIX}/"
