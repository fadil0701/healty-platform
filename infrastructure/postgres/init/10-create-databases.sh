#!/bin/bash
set -euo pipefail

# Volume baru — init sekali (docker-entrypoint-initdb.d)

: "${DASHBOARD_DB_PASSWORD:?Set DASHBOARD_DB_PASSWORD}"
: "${MCU_DB_PASSWORD:?Set MCU_DB_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pgcrypto";

    DO \$\$
    BEGIN
        -- dashboard-skrining
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'sikerja') THEN
            CREATE USER sikerja WITH PASSWORD '${DASHBOARD_DB_PASSWORD}' LOGIN;
        END IF;
        -- mcu-monitor
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcu_monitor') THEN
            CREATE USER mcu_monitor WITH PASSWORD '${MCU_DB_PASSWORD}' LOGIN;
        END IF;
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ppkp_dba_readonly') THEN
            CREATE USER ppkp_dba_readonly WITH PASSWORD '${POSTGRES_SUPERUSER_PASSWORD}' LOGIN;
        END IF;
    END
    \$\$;

    SELECT 'CREATE DATABASE sikerja_ppkp OWNER sikerja'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'sikerja_ppkp')\gexec

    SELECT 'CREATE DATABASE mcu_monitor OWNER mcu_monitor'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mcu_monitor')\gexec

    REVOKE ALL ON DATABASE sikerja_ppkp FROM PUBLIC;
    REVOKE ALL ON DATABASE mcu_monitor FROM PUBLIC;
    GRANT CONNECT ON DATABASE sikerja_ppkp TO sikerja, ppkp_dba_readonly;
    GRANT CONNECT ON DATABASE mcu_monitor TO mcu_monitor, ppkp_dba_readonly;
EOSQL

for db_user in "sikerja_ppkp:sikerja" "mcu_monitor:mcu_monitor"; do
    db="${db_user%%:*}"
    user="${db_user##*:}"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
        REVOKE ALL ON SCHEMA public FROM PUBLIC;
        GRANT USAGE ON SCHEMA public TO ${user};
        GRANT ALL ON SCHEMA public TO ${user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${user};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO ${user};
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO ppkp_dba_readonly;
EOSQL
done
