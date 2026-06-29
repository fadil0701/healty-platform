# Install health-platform

| Lingkungan | Panduan | Perintah |
|------------|---------|----------|
| Lokal Windows | [docs/deployment/SETUP-FROM-SCRATCH.md](docs/deployment/SETUP-FROM-SCRATCH.md) | `.\scripts\install-local.ps1` |
| Produksi VM Linux | [docs/deployment/PRODUCTION.md](docs/deployment/PRODUCTION.md) | `./scripts/install-production.sh` |

```powershell
# Lokal
cd E:\laragon\www\health-platform
Copy-Item .env.example .env
.\scripts\install-local.ps1
```

```bash
# Produksi VM
cd /opt/health-platform
cp .env.production.example .env
./scripts/install-production.sh
```
