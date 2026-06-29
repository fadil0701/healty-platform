#!/bin/bash
# Cluster lama: db_mcu_monitor / mcu_user → mcu_monitor / mcu_monitor
set -euo pipefail

: "${MCU_DB_PASSWORD:?Set MCU_DB_PASSWORD}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcu_user')
           AND NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcu_monitor') THEN
            ALTER USER mcu_user RENAME TO mcu_monitor;
        ELSIF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mcu_monitor') THEN
            CREATE USER mcu_monitor WITH PASSWORD '${MCU_DB_PASSWORD}' LOGIN;
        END IF;
    END
    \$\$;

    ALTER USER mcu_monitor WITH PASSWORD '${MCU_DB_PASSWORD}';

    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE datname IN ('db_mcu_monitor', 'mcu_monitor') AND pid <> pg_backend_pid();

    SELECT 'ALTER DATABASE db_mcu_monitor RENAME TO mcu_monitor'
    WHERE EXISTS (SELECT FROM pg_database WHERE datname = 'db_mcu_monitor')
      AND NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mcu_monitor')\gexec

    SELECT 'CREATE DATABASE mcu_monitor OWNER mcu_monitor'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'mcu_monitor')\gexec

    GRANT CONNECT ON DATABASE mcu_monitor TO mcu_monitor, ppkp_dba_readonly;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname mcu_monitor <<-EOSQL
    GRANT ALL ON SCHEMA public TO mcu_monitor;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO ppkp_dba_readonly;
EOSQL
