#!/usr/bin/env bash
# Generate pgpass + servers.generated.json dari health-platform/.env
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-$ROOT/.env}"
PGPASS="$ROOT/infrastructure/pgadmin/pgpass"
SERVERS="$ROOT/infrastructure/pgadmin/servers.generated.json"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "File tidak ada: $ENV_FILE" >&2
    exit 1
fi

# shellcheck source=/dev/null
set -a && source "$ENV_FILE" && set +a

SUPER_USER="${POSTGRES_SUPERUSER:-postgres}"
SUPER_PASS="${POSTGRES_SUPERUSER_PASSWORD:-}"
PGADMIN_GROUP="${PGADMIN_SERVER_GROUP:-Production}"
PGADMIN_NAME="${PGADMIN_SERVER_NAME:-PPKP PostgreSQL}"

if [[ -z "$SUPER_PASS" ]]; then
    echo "POSTGRES_SUPERUSER_PASSWORD kosong di $ENV_FILE" >&2
    exit 1
fi

mkdir -p "$(dirname "$PGPASS")"

# LF only — CRLF membuat pgAdmin gagal baca pgpass
printf '%s\n' \
    "sikerja-postgres:5432:*:${SUPER_USER}:${SUPER_PASS}" \
    "sikerja-postgres:5432:*:ppkp_dba_readonly:${SUPER_PASS}" \
    "ppkp-postgres:5432:*:${SUPER_USER}:${SUPER_PASS}" \
    "ppkp-postgres:5432:*:ppkp_dba_readonly:${SUPER_PASS}" \
    > "$PGPASS"

# Escape password untuk JSON
SUPER_PASS_JSON="${SUPER_PASS//\\/\\\\}"
SUPER_PASS_JSON="${SUPER_PASS_JSON//\"/\\\"}"

cat > "$SERVERS" <<EOF
{
  "Servers": {
    "1": {
      "Name": "${PGADMIN_NAME}",
      "Group": "${PGADMIN_GROUP}",
      "Host": "sikerja-postgres",
      "Port": 5432,
      "MaintenanceDB": "postgres",
      "Username": "ppkp_dba_readonly",
      "Password": "${SUPER_PASS_JSON}",
      "PassFile": "/var/lib/pgadmin/.pgpass",
      "SSLMode": "prefer",
      "Comment": "sikerja_ppkp (dashboard-skrining), mcu_monitor (mcu-monitor)"
    }
  }
}
EOF

echo "pgAdmin config: $PGPASS, $SERVERS"
