# Rename cluster lama (db_dashboard_skrining / dashboard_user) → sikerja_ppkp / sikerja
# Jalankan manual jika volume PG sudah ada sebelum penamaan baru:
#   docker exec -e DASHBOARD_DB_PASSWORD='...' -e POSTGRES_SUPERUSER_PASSWORD='...' \
#     ppkp-postgres bash /docker-entrypoint-initdb.d/20-migrate-to-sikerja.sh

set -euo pipefail

: "${DASHBOARD_DB_PASSWORD:?Set DASHBOARD_DB_PASSWORD}"
: "${POSTGRES_SUPERUSER_PASSWORD:?Set POSTGRES_SUPERUSER_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'dashboard_user')
           AND NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sikerja') THEN
            ALTER USER dashboard_user RENAME TO sikerja;
        ELSIF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sikerja') THEN
            CREATE USER sikerja WITH PASSWORD '${DASHBOARD_DB_PASSWORD}' LOGIN;
        END IF;
    END
    \$\$;

    ALTER USER sikerja WITH PASSWORD '${DASHBOARD_DB_PASSWORD}';

    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname = 'db_dashboard_skrining' AND pid <> pg_backend_pid();

    SELECT 'ALTER DATABASE db_dashboard_skrining RENAME TO sikerja_ppkp'
    WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'db_dashboard_skrining')
      AND NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sikerja_ppkp')\gexec

    SELECT 'CREATE DATABASE sikerja_ppkp OWNER sikerja'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sikerja_ppkp')\gexec

    GRANT CONNECT ON DATABASE sikerja_ppkp TO sikerja, ppkp_dba_readonly;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname sikerja_ppkp <<-EOSQL
    GRANT ALL ON SCHEMA public TO sikerja;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO ppkp_dba_readonly;
EOSQL
