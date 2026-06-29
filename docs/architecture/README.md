# Arsitektur health-platform

Monorepo infrastruktur untuk ekosistem PPKP DKI.

- **Satu PostgreSQL** (`ppkp-postgres`) — banyak database terisolasi
- **Satu pgAdmin** — banyak server/lingkungan
- **Redis shared** — prefix key per aplikasi
- **Aplikasi** — repo Git terpisah di `services/*/README.md`

Diagram lengkap: `dashboard-skrining/docs/enterprise/ENTERPRISE_ARCHITECTURE_BLUEPRINT.md`
