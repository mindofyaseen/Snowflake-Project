-- ============================================================================
-- CareMatch Data Platform: Pipeline Execution Audit & Metadata Tracking
-- ============================================================================
-- Tracks batch-level ingestion metadata, row counts, checksums, execution timing,
-- and load status across all 11 entities in the S3 landing zone.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;
USE SCHEMA RAW;

-- 1. Create durable audit logging table in RAW schema
CREATE TABLE IF NOT EXISTS CAREMATCH.RAW.PIPELINE_LOAD_AUDIT (
    audit_id VARCHAR(64) DEFAULT UUID_STRING() PRIMARY KEY,
    pipeline_run_id VARCHAR(128) NOT NULL,
    airflow_dag_run_id VARCHAR(128) NOT NULL,
    batch_id VARCHAR(128) NOT NULL,
    load_mode VARCHAR(32) NOT NULL,              -- 'initial' or 'incremental'
    source_system VARCHAR(64) NOT NULL,          -- 'operational', 'data_science', 'app_stream', etc.
    entity_name VARCHAR(64) NOT NULL,            -- 'nurses', 'nurse_scores', 'events', etc.
    source_filename VARCHAR(512) NOT NULL,       -- S3 key or basename
    source_row_count NUMBER(38, 0) NOT NULL,     -- Rows declared in manifest
    loaded_row_count NUMBER(38, 0) DEFAULT 0,    -- Rows loaded into Snowflake
    rejected_row_count NUMBER(38, 0) DEFAULT 0,  -- Rows rejected by COPY INTO
    checksum VARCHAR(64) NOT NULL,               -- SHA-256 hash from manifest
    load_started_at TIMESTAMP_NTZ NOT NULL,
    load_completed_at TIMESTAMP_NTZ,
    final_status VARCHAR(32) NOT NULL,           -- 'STARTED', 'SUCCESS', 'FAILED'
    error_message VARCHAR(2048),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- 2. Create Staging View for audit reporting and reconciliation
CREATE OR REPLACE VIEW CAREMATCH.STAGING.STG_PIPELINE_LOAD_AUDIT AS
SELECT
    audit_id,
    pipeline_run_id,
    airflow_dag_run_id,
    batch_id,
    load_mode,
    source_system,
    entity_name,
    source_filename,
    source_row_count,
    loaded_row_count,
    rejected_row_count,
    checksum,
    load_started_at,
    load_completed_at,
    DATEDIFF('second', load_started_at, load_completed_at) AS duration_seconds,
    final_status,
    error_message,
    CASE 
        WHEN source_row_count = loaded_row_count AND rejected_row_count = 0 THEN TRUE
        ELSE FALSE
    END AS is_reconciled
FROM CAREMATCH.RAW.PIPELINE_LOAD_AUDIT;

-- 3. Verification & Reconciliation Queries (Read-Only)

-- A. Audit log summary by batch and status
SELECT
    batch_id,
    load_mode,
    final_status,
    COUNT(*) AS entity_count,
    SUM(source_row_count) AS total_source_rows,
    SUM(loaded_row_count) AS total_loaded_rows,
    SUM(rejected_row_count) AS total_rejected_rows,
    MIN(load_started_at) AS earliest_start,
    MAX(load_completed_at) AS latest_complete
FROM CAREMATCH.RAW.PIPELINE_LOAD_AUDIT
GROUP BY batch_id, load_mode, final_status
ORDER BY earliest_start DESC;

-- B. Audit records with discrepancies or errors
SELECT
    batch_id,
    entity_name,
    source_row_count,
    loaded_row_count,
    rejected_row_count,
    final_status,
    error_message
FROM CAREMATCH.STAGING.STG_PIPELINE_LOAD_AUDIT
WHERE NOT is_reconciled OR final_status != 'SUCCESS';
