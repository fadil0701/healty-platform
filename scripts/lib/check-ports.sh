#!/usr/bin/env bash
# Cek port host belum dipakai sebelum docker compose up.
# Usage: source scripts/lib/check-ports.sh && check_infra_ports

check_port_in_use() {
    local port="$1"
    local label="$2"

    if command -v ss >/dev/null 2>&1; then
        if ss -lntp 2>/dev/null | grep -qE "127\.0\.0\.1:${port}[[:space:]]|:${port}[[:space:]]"; then
            echo "ERROR: Port ${port} (${label}) sudah dipakai di host:" >&2
            ss -lntp 2>/dev/null | grep -E ":${port}[[:space:]]" || true
            return 1
        fi
        return 0
    fi

    if command -v netstat >/dev/null 2>&1; then
        if netstat -tln 2>/dev/null | grep -qE ":${port}[[:space:]]"; then
            echo "ERROR: Port ${port} (${label}) sudah dipakai di host." >&2
            return 1
        fi
    fi

    return 0
}

check_infra_ports() {
    local failed=0

    check_port_in_use "${POSTGRES_PUBLISH_PORT:-5435}" "PostgreSQL" || failed=1
    check_port_in_use "${PGADMIN_PORT:-5050}" "pgAdmin" || failed=1
    check_port_in_use "${REDIS_PUBLISH_PORT:-6380}" "Redis" || failed=1
    check_port_in_use "${MINIO_API_PORT:-9100}" "MinIO API" || failed=1
    check_port_in_use "${MINIO_CONSOLE_PORT:-9200}" "MinIO Console" || failed=1

    if [[ "$failed" -ne 0 ]]; then
        echo "" >&2
        echo "Solusi:" >&2
        echo "  1. Hentikan proses/container yang memakai port tersebut" >&2
        echo "  2. Atau ubah port di .env (lihat docs/deployment/PORTS.md)" >&2
        echo "     Contoh: REDIS_PUBLISH_PORT=6381" >&2
        return 1
    fi

    return 0
}
