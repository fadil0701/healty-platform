# Firewall & akses LAN — VM produksi (`10.15.101.117`)

Panduan membuka port infrastruktur ke **jaringan kantor (LAN)** dengan pembatasan IP, bukan internet publik.

## Ringkasan

| Mode | `INFRA_BIND_HOST` | Akses dari laptop LAN | Firewall |
|------|-------------------|------------------------|----------|
| Aman (default lama) | `127.0.0.1` | Hanya SSH tunnel | Tidak wajib |
| **LAN + firewall** | `0.0.0.0` | Langsung `http://10.15.101.117:PORT` | **Wajib** `./scripts/configure-firewall-production.sh` |

## Port yang diatur

| Port | Layanan | URL contoh |
|------|---------|------------|
| `9006` | Dashboard SIKERJA | http://10.15.101.117:9006 |
| `9003` | MCU Monitor | http://10.15.101.117:9003 |
| `5435` | PostgreSQL (host / DBA) | `psql -h 10.15.101.117 -p 5435` |
| `5050` | pgAdmin | http://10.15.101.117:5050 |
| `6380` | Redis infra | internal / admin |
| `9100` | MinIO **S3 API** | skrip backup (bukan browser) |
| `9200` | MinIO **Console** | http://10.15.101.117:9200 |
| `9090` | Prometheus | monitoring |
| `3200` | Grafana | http://10.15.101.117:3200 |
| `3100` | Loki | monitoring |
| `22` | SSH | admin |

Aplikasi Docker tetap `PGSQL_PORT=5432` internal — bukan `5435`.

---

## Apakah subdomain (`/sikerja/`, `/mcuppkp/`) terganggu?

**Tidak**, jika firewall dikonfigurasi seperti skrip resmi — subdomain **tidak** lewat port `9006`/`9003` langsung dari internet.

### Alur subdomain (tetap jalan)

```
Browser → https://puspelkes.jakarta.go.id/sikerja/
       → nginx host :443 (UFW allow 80/443 publik)
       → proxy_pass http://127.0.0.1:9006/
       → container dashboard
```

Firewall membatasi akses **langsung** ke `:9006` / `:9200` / `:5050` dari luar LAN.  
Nginx di **VM yang sama** mem-proxy lewat **127.0.0.1** — skrip memasukkan pengecualian loopback untuk port app agar subdomain tidak putus.

### Yang dilindungi vs tidak

| Akses | Terpengaruh firewall? |
|-------|------------------------|
| `https://puspelkes.jakarta.go.id/sikerja/` | ❌ Tidak (nginx :443) |
| `https://puspelkes.jakarta.go.id/mcuppkp/` | ❌ Tidak (nginx :443) |
| `http://10.15.101.117:9006` langsung | ✅ Hanya dari `FIREWALL_ALLOW_CIDR` |
| `http://10.15.101.117:9200` MinIO | ✅ Hanya dari CIDR kantor |

### Setelah aktifkan firewall — uji subdomain

```bash
curl -fsSI https://puspelkes.jakarta.go.id/sikerja/up | head -5
curl -fsSI https://puspelkes.jakarta.go.id/mcuppkp/up | head -5
```

---

## Langkah 1 — `.env` health-platform

```bash
cd /var/www/html/healty-platform
nano .env
```

Tambahkan / ubah:

```env
# Listen di semua interface VM (akses via 10.15.101.117)
INFRA_BIND_HOST=0.0.0.0

# Hanya IP jaringan kantor yang boleh connect (sesuaikan!)
FIREWALL_ALLOW_CIDR=10.15.0.0/16
FIREWALL_SSH_PORT=22
FIREWALL_APP_DASHBOARD_PORT=9006
FIREWALL_APP_MCU_PORT=9003
```

> Jika hanya subnet tertentu: `FIREWALL_ALLOW_CIDR=10.15.101.0/24`  
> Jika satu IP admin: `FIREWALL_ALLOW_CIDR=10.15.x.x/32`

---

## Langkah 2 — Recreate container (publish ke LAN)

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate

docker ps --filter name=ppkp-minio --format '{{.Ports}}'
# Harus: 0.0.0.0:9200->9001/tcp, 0.0.0.0:9100->9000/tcp
```

Verifikasi di VM:

```bash
curl -fsS http://127.0.0.1:9200 >/dev/null && echo "MinIO Console OK"
curl -fsS http://10.15.101.117:9200 >/dev/null && echo "MinIO LAN OK"
```

---

## Langkah 3 — Firewall (UFW + iptables Docker)

Docker **sering melewati UFW** untuk port yang di-publish. Skrip ini mengatur **keduanya**: UFW + chain `DOCKER-USER`.

```bash
chmod +x scripts/configure-firewall-production.sh

# Lihat perintah tanpa mengubah sistem
./scripts/configure-firewall-production.sh --dry-run

# Terapkan (butuh sudo)
sudo ./scripts/configure-firewall-production.sh --apply
```

Cek:

```bash
sudo ufw status numbered
sudo iptables -L DOCKER-USER -n -v
```

---

## Langkah 4 — Akses dari laptop (jaringan kantor)

| Layanan | URL | Login |
|---------|-----|-------|
| MinIO Console | http://10.15.101.117:9200 | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| pgAdmin | http://10.15.101.117:5050 | `PGADMIN_EMAIL` / `PGADMIN_PASSWORD` |
| Grafana | http://10.15.101.117:3200 | `admin` / `GRAFANA_PASSWORD` |
| SIKERJA | http://10.15.101.117:9006 | user app |
| MCU | http://10.15.101.117:9003 | user app |

**MinIO port 9100** = API S3 — untuk browser pakai **9200**.

---

## Kembali ke mode SSH tunnel saja

```env
INFRA_BIND_HOST=127.0.0.1
```

```bash
docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml up -d --force-recreate
```

Opsional nonaktifkan aturan khusus: `sudo ufw disable` (hati-hati).

---

## Troubleshooting

| Gejala | Penyebab | Solusi |
|--------|----------|--------|
| `Connection refused` dari LAN | `INFRA_BIND_HOST=127.0.0.1` | Set `0.0.0.0` + recreate |
| Timeout dari luar LAN | Firewall benar | Normal — hanya `FIREWALL_ALLOW_CIDR` |
| Bisa akses dari internet | CIDR terlalu luas / firewall mati | Perketat CIDR; jalankan `--apply` |
| UFW allow tapi tetap terbuka publik | Docker bypass UFW | Pastikan aturan `DOCKER-USER` ada |
| pgAdmin error login | Volume lama | `./scripts/reset-pgadmin.sh` |

---

## Keamanan

- Jangan set `FIREWALL_ALLOW_CIDR=0.0.0.0/0` di produksi.
- Password kuat: `PGADMIN_PASSWORD`, `MINIO_ROOT_PASSWORD`, `POSTGRES_SUPERUSER_PASSWORD`.
- Port `5435` dan `6380` hanya untuk admin — pertimbangkan tidak expose jika tidak perlu.
- Pastikan firewall **perimeter** (router DC) juga membatasi akses ke VM.

---

Dokumen terkait: [PORTS.md](./PORTS.md), [PRODUCTION.md](./PRODUCTION.md)
