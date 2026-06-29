#!/usr/bin/env bash
# Backup PostgreSQL (pg_dump) lalu upload otomatis ke MinIO.
#
# Usage:
#   ./infrastructure/backup/backup-and-archive.sh
#   ./infrastructure/backup/backup-and-archive.sh 2026-06-29
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DATE="${1:-$(date +%F)}"

"$ROOT/infrastructure/backup/backup-all.sh" "$DATE"
"$ROOT/infrastructure/backup/upload-to-minio.sh" "${BACKUP_DIR:-$ROOT/storage/backups}/$DATE"
