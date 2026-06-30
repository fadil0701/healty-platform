# health-platform — infrastruktur bersama PPKP DKI

PostgreSQL bersama, pgAdmin, Redis, dan MinIO untuk **dashboard-skrining** dan **mcu-monitor**.

## Panduan utama

| Dokumen | Isi |
|---------|-----|
| **[INSTALL-DAN-MIGRASI.md](docs/deployment/INSTALL-DAN-MIGRASI.md)** | **Panduan lengkap** instalasi + migrasi MySQL→PG (lokal & produksi VM) |
| [PRODUCTION-DEPLOY-WORKFLOW.md](docs/deployment/PRODUCTION-DEPLOY-WORKFLOW.md) | Deploy harian setelah migrasi, subdomain |
| [FIREWALL.md](docs/deployment/FIREWALL.md) | Akses LAN + UFW/iptables |
| [PORTS.md](docs/deployment/PORTS.md) | Port lokal vs produksi |
| [DATABASE-NAMING.md](docs/deployment/DATABASE-NAMING.md) | `sikerja_ppkp`, `mcu_monitor`, alias host |
| [APP-ENV.md](docs/deployment/APP-ENV.md) | Mapping password antar `.env` |

## Perintah cepat

| Lingkungan | Perintah |
|------------|----------|
| Lokal Windows | `.\scripts\install-local.ps1` |
| Produksi VM | `./scripts/install-production.sh` |
| Reset pgAdmin | `./scripts/reset-pgadmin.sh` |
| Firewall LAN | `sudo ./scripts/configure-firewall-production.sh --apply` |

```powershell
# Lokal
cd E:\laragon\www\health-platform
Copy-Item .env.example .env
.\scripts\install-local.ps1
```

```bash
# Produksi VM (10.15.101.117)
cd /var/www/html/healty-platform
cp .env.production.example .env
./scripts/install-production.sh
```

Lanjut migrasi aplikasi: [INSTALL-DAN-MIGRASI.md](docs/deployment/INSTALL-DAN-MIGRASI.md)
