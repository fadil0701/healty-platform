#!/usr/bin/env bash
# Helper upload ke MinIO via container minio/mc (tanpa pasang mc di host).
set -euo pipefail

minio_load_env() {
    local root="${1:?}"
    # shellcheck source=../../scripts/lib/load-env.sh
    source "$root/scripts/lib/load-env.sh"
    load_env_file "$root/.env"
    : "${MINIO_ROOT_USER:?Set MINIO_ROOT_USER di .env}"
    : "${MINIO_ROOT_PASSWORD:?Set MINIO_ROOT_PASSWORD di .env}"
    MINIO_BACKUP_BUCKET="${MINIO_BACKUP_BUCKET:-minio.sikerja}"
    MINIO_API_PORT="${MINIO_API_PORT:-9000}"
}

minio_resolve_network() {
    if [ -n "${MINIO_DOCKER_NETWORK:-}" ]; then
        echo "$MINIO_DOCKER_NETWORK"
        return 0
    fi

    if docker inspect ppkp-minio >/dev/null 2>&1; then
        docker inspect ppkp-minio --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' | head -1
        return 0
    fi

    local project="${COMPOSE_PROJECT_NAME:-health-platform}"
    echo "${project}_default"
}

minio_assert_running() {
    if ! docker ps --format '{{.Names}}' | grep -qx 'ppkp-minio'; then
        echo "ERROR: Container ppkp-minio tidak berjalan. Jalankan: docker compose up -d minio" >&2
        exit 1
    fi
}

# minio_upload_dir <local-dir> <remote-prefix-within-bucket>
# Contoh: minio_upload_dir /path/to/2026-06-29 pg-backups/2026-06-29
minio_upload_dir() {
    local local_dir="$1"
    local remote_prefix="$2"
    local network

    if [ ! -d "$local_dir" ]; then
        echo "ERROR: Folder tidak ditemukan: $local_dir" >&2
        exit 1
    fi

    local abs_dir
    abs_dir="$(cd "$local_dir" && pwd)"

    minio_assert_running
    network="$(minio_resolve_network)"

    echo "==> Upload ke MinIO"
    echo "    Bucket:   $MINIO_BACKUP_BUCKET"
    echo "    Prefix:   $remote_prefix"
    echo "    Sumber:   $abs_dir"
    echo "    Network:  $network"

    docker run --rm \
        --network "$network" \
        --entrypoint /bin/sh \
        -v "${abs_dir}:/backup:ro" \
        -e "MINIO_ROOT_USER=${MINIO_ROOT_USER}" \
        -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}" \
        -e "MINIO_BACKUP_BUCKET=${MINIO_BACKUP_BUCKET}" \
        -e "REMOTE_PREFIX=${remote_prefix}" \
        minio/mc:latest \
        -ec '
            mc alias set ppkp http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
            mc mb --ignore-existing "ppkp/${MINIO_BACKUP_BUCKET}"
            mc cp --recursive /backup/ "ppkp/${MINIO_BACKUP_BUCKET}/${REMOTE_PREFIX}/"
            echo ""
            echo "Isi bucket (prefix ini):"
            mc ls --recursive "ppkp/${MINIO_BACKUP_BUCKET}/${REMOTE_PREFIX}/"
        '
}
