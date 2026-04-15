#!/bin/bash
# =============================================================================
# init-db.sh — runs once on first postgres container startup
# Creates the schema that Flyway expects to exist before running migrations
# =============================================================================
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE SCHEMA IF NOT EXISTS "asset-orchestrator";
    GRANT ALL ON SCHEMA "asset-orchestrator" TO "$POSTGRES_USER";
EOSQL

echo "Schema 'asset-orchestrator' created."
