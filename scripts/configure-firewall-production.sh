#!/usr/bin/env bash
# Atur UFW + iptables DOCKER-USER untuk port PPKP (infra + aplikasi).
# Jalankan di VM produksi dengan sudo setelah compose up.
#
# Usage:
#   ./scripts/configure-firewall-production.sh --dry-run
#   sudo ./scripts/configure-firewall-production.sh --apply
#
# Variabel .env:
#   FIREWALL_ALLOW_CIDR=10.15.0.0/16
#   FIREWALL_SSH_PORT=22
#   INFRA_BIND_HOST=0.0.0.0   (agar port listen di LAN; tetap dibatasi firewall)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APPLY=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=true ;;
        --dry-run) DRY_RUN=true ;;
    esac
done

if ! $APPLY && ! $DRY_RUN; then
    echo "Usage: $0 --dry-run | --apply" >&2
    echo "  --dry-run  Tampilkan perintah tanpa menjalankan" >&2
    echo "  --apply    Terapkan UFW + iptables (butuh root/sudo)" >&2
    exit 1
fi

# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh"
load_env_file "$ROOT/.env" 2>/dev/null || true

CIDR="${FIREWALL_ALLOW_CIDR:-10.15.0.0/16}"
SSH_PORT="${FIREWALL_SSH_PORT:-22}"
PG_PORT="${POSTGRES_PUBLISH_PORT:-5435}"
PGADMIN_PORT="${PGADMIN_PORT:-5050}"
REDIS_PORT="${REDIS_PUBLISH_PORT:-6380}"
MINIO_API="${MINIO_API_PORT:-9100}"
MINIO_CONSOLE="${MINIO_CONSOLE_PORT:-9200}"
PROM_PORT="${PROMETHEUS_PORT:-9090}"
GRAFANA_PORT="${GRAFANA_PORT:-3200}"
LOKI_PORT="${LOKI_PORT:-3100}"
APP_DASHBOARD="${FIREWALL_APP_DASHBOARD_PORT:-9006}"
APP_MCU="${FIREWALL_APP_MCU_PORT:-9003}"

run() {
    if $DRY_RUN; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

sudo_run() {
    if $DRY_RUN; then
        echo "[dry-run] sudo $*"
    else
        sudo "$@"
    fi
}

echo "==> Firewall PPKP — allow CIDR: ${CIDR}"
echo "    Infra: ${PG_PORT} ${PGADMIN_PORT} ${REDIS_PORT} ${MINIO_API} ${MINIO_CONSOLE} ${PROM_PORT} ${GRAFANA_PORT} ${LOKI_PORT}"
echo "    App:   ${APP_DASHBOARD} ${APP_MCU} | SSH: ${SSH_PORT}"
echo ""

if $APPLY && [[ "$(id -u)" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
    echo "ERROR: --apply membutuhkan sudo/root." >&2
    exit 1
fi

# ── UFW ─────────────────────────────────────────────────────────────────────
if command -v ufw >/dev/null 2>&1; then
    echo "==> UFW"
    sudo_run ufw default deny incoming
    sudo_run ufw default allow outgoing
    # Portal publik (subdomain nginx host) — tidak dibatasi CIDR
    sudo_run ufw allow 80/tcp comment 'HTTP nginx portal'
    sudo_run ufw allow 443/tcp comment 'HTTPS nginx portal'
    sudo_run ufw allow from "$CIDR" to any port "$SSH_PORT" proto tcp comment 'PPKP SSH'
    sudo_run ufw allow from "$CIDR" to any port "$APP_DASHBOARD" proto tcp comment 'SIKERJA'
    sudo_run ufw allow from "$CIDR" to any port "$APP_MCU" proto tcp comment 'MCU Monitor'
    sudo_run ufw allow from "$CIDR" to any port "$PG_PORT" proto tcp comment 'PostgreSQL host'
    sudo_run ufw allow from "$CIDR" to any port "$PGADMIN_PORT" proto tcp comment 'pgAdmin'
    sudo_run ufw allow from "$CIDR" to any port "$REDIS_PORT" proto tcp comment 'Redis infra'
    sudo_run ufw allow from "$CIDR" to any port "$MINIO_API" proto tcp comment 'MinIO API'
    sudo_run ufw allow from "$CIDR" to any port "$MINIO_CONSOLE" proto tcp comment 'MinIO Console'
    sudo_run ufw allow from "$CIDR" to any port "$PROM_PORT" proto tcp comment 'Prometheus'
    sudo_run ufw allow from "$CIDR" to any port "$GRAFANA_PORT" proto tcp comment 'Grafana'
    sudo_run ufw allow from "$CIDR" to any port "$LOKI_PORT" proto tcp comment 'Loki'
    if $APPLY; then
        sudo_run ufw --force enable
        sudo_run ufw status numbered
    fi
else
    echo "PERINGATAN: ufw tidak terpasang — lewati UFW (hanya iptables DOCKER-USER)."
fi

# ── iptables DOCKER-USER (Docker sering bypass UFW untuk port publish) ───────
echo ""
echo "==> iptables DOCKER-USER (batasi port publish Docker ke ${CIDR})"

DOCKER_PORTS=(
    "$SSH_PORT"
    "$APP_DASHBOARD"
    "$APP_MCU"
    "$PG_PORT"
    "$PGADMIN_PORT"
    "$REDIS_PORT"
    "$MINIO_API"
    "$MINIO_CONSOLE"
    "$PROM_PORT"
    "$GRAFANA_PORT"
    "$LOKI_PORT"
)

if $DRY_RUN; then
    echo "[dry-run] sudo iptables -N DOCKER-USER 2>/dev/null || true"
    echo "[dry-run] sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN || sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN"
    echo "[dry-run] # nginx host → 127.0.0.1:9006/:9003 (subdomain /sikerja/ /mcuppkp/)"
    for port in "$APP_DASHBOARD" "$APP_MCU"; do
        echo "[dry-run] sudo iptables -C DOCKER-USER -s 127.0.0.0/8 -p tcp --dport ${port} -j RETURN || sudo iptables -I DOCKER-USER -s 127.0.0.0/8 -p tcp --dport ${port} -j RETURN"
    done
    for port in "${DOCKER_PORTS[@]}"; do
        echo "[dry-run] sudo iptables -C DOCKER-USER -p tcp --dport ${port} ! -s ${CIDR} -j DROP || sudo iptables -I DOCKER-USER -p tcp --dport ${port} ! -s ${CIDR} -j DROP"
    done
    echo "[dry-run] sudo iptables -C DOCKER-USER -j RETURN || sudo iptables -A DOCKER-USER -j RETURN"
elif $APPLY; then
    sudo iptables -N DOCKER-USER 2>/dev/null || true
    if ! sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN 2>/dev/null; then
        sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
    fi
    # Nginx di host mem-proxy subdomain ke 127.0.0.1 — jangan blokir loopback
    for port in "$APP_DASHBOARD" "$APP_MCU"; do
        if ! sudo iptables -C DOCKER-USER -s 127.0.0.0/8 -p tcp --dport "$port" -j RETURN 2>/dev/null; then
            sudo iptables -I DOCKER-USER -s 127.0.0.0/8 -p tcp --dport "$port" -j RETURN
        fi
    done
    for port in "${DOCKER_PORTS[@]}"; do
        if ! sudo iptables -C DOCKER-USER -p tcp --dport "$port" ! -s "$CIDR" -j DROP 2>/dev/null; then
            sudo iptables -I DOCKER-USER -p tcp --dport "$port" ! -s "$CIDR" -j DROP
        fi
    done
    if ! sudo iptables -C DOCKER-USER -j RETURN 2>/dev/null; then
        sudo iptables -A DOCKER-USER -j RETURN
    fi
    echo "    Aturan DOCKER-USER diterapkan."
    sudo iptables -L DOCKER-USER -n -v --line-numbers | head -30
fi

echo ""
if $DRY_RUN; then
    echo "Selesai (dry-run). Jalankan: sudo $0 --apply"
elif $APPLY; then
    echo "Selesai. Uji dari laptop LAN:"
    echo "  http://10.15.101.117:${MINIO_CONSOLE}/  (MinIO Console)"
    echo "  http://10.15.101.117:${PGADMIN_PORT}/   (pgAdmin)"
    echo "  http://10.15.101.117:${APP_DASHBOARD}/up"
fi
