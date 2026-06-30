#!/usr/bin/env bash
# Reset volume pgAdmin setelah ganti SERVER_MODE atau error auth_source_manager di /login.
# Server PostgreSQL di servers.generated.json + pgpass tetap di-generate ulang.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml)

if [[ -f docker-compose.pgadmin-login.yml ]]; then
    COMPOSE+=(-f docker-compose.pgadmin-login.yml)
fi

echo "==> Stop pgAdmin"
"${COMPOSE[@]}" stop pgadmin 2>/dev/null || true
docker rm -f ppkp-pgadmin 2>/dev/null || true

echo "==> Hapus volume internal pgAdmin (session/desktop mode lama)"
docker volume rm ppkp_pgadmin_data 2>/dev/null || true

chmod +x "$ROOT/scripts/generate-pgadmin-config.sh"
"$ROOT/scripts/generate-pgadmin-config.sh"

echo "==> Start pgAdmin (SERVER_MODE=True di produksi)"
"${COMPOSE[@]}" up -d --force-recreate pgadmin

echo ""
echo "Tunggu ~30 detik, lalu buka (incognito):"
echo "  http://127.0.0.1:${PGADMIN_PORT:-5050}/"
echo "Login: PGADMIN_EMAIL / PGADMIN_PASSWORD dari .env"
echo ""
echo "Jangan buka /login langsung jika masih error — gunakan URL root di atas."
