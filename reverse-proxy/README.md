# Reverse proxy (opsional)

Nginx di host atau container terpisah untuk:

- `sikerja.local` → dashboard-skrining:9006
- `mcu.local` → mcu-monitor:9003
- `pgadmin.local` → ppkp-pgadmin:5050

Contoh upstream — sesuaikan di `nginx.conf` saat dipakai.
