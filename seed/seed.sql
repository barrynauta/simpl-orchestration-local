-- =============================================================================
-- Simpl Asset Orchestrator — Seed Data
-- =============================================================================
-- Loads CSV files into the asset-orchestrator schema and builds relationships.
-- Run automatically by the 'seed' Docker Compose service after startup.
--
-- To extend: edit the CSV files in seed/csv/ and re-run:
--   docker compose run --rm seed
-- =============================================================================

SET search_path TO "asset-orchestrator";

-- -----------------------------------------------------------------------------
-- 1. catalog_asset — load from CSV
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_catalog_asset (
    original_id       VARCHAR(255),
    asset_type        VARCHAR(255),
    asset_description TEXT,
    provider_email    VARCHAR(255)
);

\COPY tmp_catalog_asset FROM '/seed/csv/catalog_assets.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO catalog_asset (original_id, asset_type, asset_description, provider_email)
SELECT original_id, asset_type, asset_description, provider_email
FROM tmp_catalog_asset
ON CONFLICT (original_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. workflow — load from CSV
-- -----------------------------------------------------------------------------
CREATE TEMP TABLE tmp_workflow (
    repository_name VARCHAR(255),
    job_name        VARCHAR(255),
    code_location   VARCHAR(255)
);

\COPY tmp_workflow FROM '/seed/csv/workflows.csv' WITH (FORMAT csv, HEADER true);

INSERT INTO workflow (repository_name, job_name, code_location)
SELECT repository_name, job_name, code_location
FROM tmp_workflow
ON CONFLICT (repository_name, job_name, code_location) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. workflow_catalog_asset — associate assets with workflows
-- -----------------------------------------------------------------------------
-- Patient records → k-anonymity (active)
INSERT INTO workflow_catalog_asset (catalog_asset_id, workflow_id, association_title, is_active, yaml_configuration)
SELECT ca.id, w.id,
    'K-Anonymity pipeline for patient records NL',
    true,
    '{"k": 5, "quasi_identifiers": ["age", "zipcode", "gender"], "sensitive_attr": "diagnosis"}'
FROM catalog_asset ca, workflow w
WHERE ca.original_id = 'urn:simpl:asset:health:patient-records-nl'
  AND w.job_name = 'k_anonymity_job'
ON CONFLICT DO NOTHING;

-- Patient records → l-diversity (active)
INSERT INTO workflow_catalog_asset (catalog_asset_id, workflow_id, association_title, is_active, yaml_configuration)
SELECT ca.id, w.id,
    'L-Diversity pipeline for patient records NL',
    true,
    '{"l": 3, "quasi_identifiers": ["age", "zipcode", "gender"], "sensitive_attr": "diagnosis"}'
FROM catalog_asset ca, workflow w
WHERE ca.original_id = 'urn:simpl:asset:health:patient-records-nl'
  AND w.job_name = 'l_diversity_job'
ON CONFLICT DO NOTHING;

-- Clinical trials → k-anonymity (active)
INSERT INTO workflow_catalog_asset (catalog_asset_id, workflow_id, association_title, is_active, yaml_configuration)
SELECT ca.id, w.id,
    'K-Anonymity pipeline for clinical trials DE',
    true,
    '{"k": 10, "quasi_identifiers": ["age", "gender", "trial_site"], "sensitive_attr": "outcome"}'
FROM catalog_asset ca, workflow w
WHERE ca.original_id = 'urn:simpl:asset:health:clinical-trials-de'
  AND w.job_name = 'k_anonymity_job'
ON CONFLICT DO NOTHING;

-- Traffic flow → data quality completeness (active)
INSERT INTO workflow_catalog_asset (catalog_asset_id, workflow_id, association_title, is_active, yaml_configuration)
SELECT ca.id, w.id,
    'Completeness check for traffic flow data',
    true,
    '{"threshold": 0.95, "columns": ["timestamp", "location_id", "flow_count"]}'
FROM catalog_asset ca, workflow w
WHERE ca.original_id = 'urn:simpl:asset:mobility:traffic-flow-be'
  AND w.job_name = 'completeness_check_job'
ON CONFLICT DO NOTHING;

-- Energy data → outlier detection (inactive — shows mixed states in UI)
INSERT INTO workflow_catalog_asset (catalog_asset_id, workflow_id, association_title, is_active, yaml_configuration)
SELECT ca.id, w.id,
    'Outlier detection for smart meter readings',
    false,
    '{"method": "iqr", "threshold": 3.0, "columns": ["reading_kwh"]}'
FROM catalog_asset ca, workflow w
WHERE ca.original_id = 'urn:simpl:asset:energy:smart-meter-readings'
  AND w.job_name = 'outlier_detection_job'
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4. workflow_catalog_asset_run — some historical run records
-- -----------------------------------------------------------------------------
-- Successful run for patient records k-anonymity
INSERT INTO workflow_catalog_asset_run (workflow_catalog_asset_id, yaml_execution, started_at, status)
SELECT wca.id,
    '{"run_id": "abc-001", "k": 5, "rows_processed": 12450, "rows_suppressed": 38}',
    NOW() - INTERVAL '2 days',
    'SUCCESS'
FROM workflow_catalog_asset wca
JOIN catalog_asset ca ON ca.id = wca.catalog_asset_id
JOIN workflow w ON w.id = wca.workflow_id
WHERE ca.original_id = 'urn:simpl:asset:health:patient-records-nl'
  AND w.job_name = 'k_anonymity_job';

-- Successful run for patient records l-diversity
INSERT INTO workflow_catalog_asset_run (workflow_catalog_asset_id, yaml_execution, started_at, status)
SELECT wca.id,
    '{"run_id": "abc-002", "l": 3, "rows_processed": 12450, "rows_suppressed": 102}',
    NOW() - INTERVAL '1 day',
    'SUCCESS'
FROM workflow_catalog_asset wca
JOIN catalog_asset ca ON ca.id = wca.catalog_asset_id
JOIN workflow w ON w.id = wca.workflow_id
WHERE ca.original_id = 'urn:simpl:asset:health:patient-records-nl'
  AND w.job_name = 'l_diversity_job';

-- Failed run (shows error state in UI)
INSERT INTO workflow_catalog_asset_run (workflow_catalog_asset_id, yaml_execution, started_at, status)
SELECT wca.id,
    '{"run_id": "abc-003", "k": 10, "error": "Source file not available at expected path"}',
    NOW() - INTERVAL '3 hours',
    'FAILURE'
FROM workflow_catalog_asset wca
JOIN catalog_asset ca ON ca.id = wca.catalog_asset_id
JOIN workflow w ON w.id = wca.workflow_id
WHERE ca.original_id = 'urn:simpl:asset:health:clinical-trials-de'
  AND w.job_name = 'k_anonymity_job';

-- In-progress run (shows running state)
INSERT INTO workflow_catalog_asset_run (workflow_catalog_asset_id, yaml_execution, started_at, status)
SELECT wca.id,
    '{"run_id": "abc-004", "threshold": 0.95, "rows_checked": 8200}',
    NOW() - INTERVAL '5 minutes',
    'RUNNING'
FROM workflow_catalog_asset wca
JOIN catalog_asset ca ON ca.id = wca.catalog_asset_id
JOIN workflow w ON w.id = wca.workflow_id
WHERE ca.original_id = 'urn:simpl:asset:mobility:traffic-flow-be'
  AND w.job_name = 'completeness_check_job';

-- -----------------------------------------------------------------------------
-- Done
-- -----------------------------------------------------------------------------
SELECT 'Seed complete.' AS status;
SELECT 'catalog_asset rows: ' || COUNT(*)::text FROM catalog_asset;
SELECT 'workflow rows: ' || COUNT(*)::text FROM workflow;
SELECT 'workflow_catalog_asset rows: ' || COUNT(*)::text FROM workflow_catalog_asset;
SELECT 'workflow_catalog_asset_run rows: ' || COUNT(*)::text FROM workflow_catalog_asset_run;
