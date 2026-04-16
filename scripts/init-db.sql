-- =============================================================================
-- init-db.sql — runs once on first postgres container startup
-- Creates the schema that Flyway expects before running migrations.
-- Using .sql instead of .sh avoids file permission issues across platforms.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS "asset-orchestrator";
GRANT ALL ON SCHEMA "asset-orchestrator" TO current_user;
