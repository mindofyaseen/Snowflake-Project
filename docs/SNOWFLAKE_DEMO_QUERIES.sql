-- ============================================================================
-- CareMatch Modern Data Stack: Live Demonstration & Verification Queries
-- ============================================================================
-- Use this script in Snowflake Snowsight to verify row counts, deduplication,
-- incremental batch history, and data quality metrics without modifying data.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;

-- ============================================================================
-- 1. RAW LAYER COUNTS & LATEST BATCH AUDIT
-- ============================================================================

-- A. Total row counts across all 11 RAW tables
SELECT 'RAW.NURSES' AS table_name, COUNT(*) AS row_count FROM CAREMATCH.RAW.NURSES
UNION ALL
SELECT 'RAW.FACILITIES', COUNT(*) FROM CAREMATCH.RAW.FACILITIES
UNION ALL
SELECT 'RAW.SHIFTS', COUNT(*) FROM CAREMATCH.RAW.SHIFTS
UNION ALL
SELECT 'RAW.APPLICATIONS', COUNT(*) FROM CAREMATCH.RAW.APPLICATIONS
UNION ALL
SELECT 'RAW.ASSIGNMENTS', COUNT(*) FROM CAREMATCH.RAW.ASSIGNMENTS
UNION ALL
SELECT 'RAW.HEALTH_SCREENINGS', COUNT(*) FROM CAREMATCH.RAW.HEALTH_SCREENINGS
UNION ALL
SELECT 'RAW.MARKET_CONDITIONS', COUNT(*) FROM CAREMATCH.RAW.MARKET_CONDITIONS
UNION ALL
SELECT 'RAW.NURSE_SCORES', COUNT(*) FROM CAREMATCH.RAW.NURSE_SCORES
UNION ALL
SELECT 'RAW.CAMPAIGN_PERFORMANCE', COUNT(*) FROM CAREMATCH.RAW.CAMPAIGN_PERFORMANCE
UNION ALL
SELECT 'RAW.MANUAL_OVERRIDES', COUNT(*) FROM CAREMATCH.RAW.MANUAL_OVERRIDES
UNION ALL
SELECT 'RAW.APP_EVENTS', COUNT(*) FROM CAREMATCH.RAW.APP_EVENTS;

-- B. Most recently updated raw records and timestamp evidence
SELECT
    nurse_id,
    full_name,
    specialty,
    completed_shifts_lifetime,
    days_since_active,
    record_updated_at
FROM CAREMATCH.RAW.NURSES
ORDER BY record_updated_at DESC
LIMIT 10;

-- ============================================================================
-- 2. DEDUPLICATION PROOF (STAGING LAYER)
-- ============================================================================

-- Compare total raw snapshots vs distinct active nurses
SELECT
    (SELECT COUNT(*) FROM CAREMATCH.RAW.NURSES) AS total_raw_nurse_snapshots,
    (SELECT COUNT(*) FROM CAREMATCH.STAGING.STG_NURSES) AS deduplicated_active_nurses,
    (SELECT COUNT(DISTINCT nurse_id) FROM CAREMATCH.RAW.NURSES) AS distinct_raw_nurse_keys,
    (SELECT COUNT(*) FROM CAREMATCH.RAW.NURSES) - (SELECT COUNT(*) FROM CAREMATCH.STAGING.STG_NURSES) AS duplicates_resolved;

-- Prove deduplication took the latest record_updated_at per nurse_id
SELECT
    raw.nurse_id,
    COUNT(*) AS snapshot_count,
    MIN(raw.record_updated_at) AS earliest_seen,
    MAX(raw.record_updated_at) AS latest_seen,
    MAX(stg.record_updated_at) AS staging_selected_timestamp
FROM CAREMATCH.RAW.NURSES raw
JOIN CAREMATCH.STAGING.STG_NURSES stg ON raw.nurse_id = stg.nurse_id
GROUP BY raw.nurse_id
HAVING COUNT(*) > 1
ORDER BY snapshot_count DESC
LIMIT 10;

-- ============================================================================
-- 3. ANALYTICS MARTS COUNTS & INTEGRITY
-- ============================================================================

-- Row counts across materialized reporting marts
SELECT 'ANALYTICS.DIM_NURSES' AS mart_table, COUNT(*) AS row_count FROM CAREMATCH.ANALYTICS.DIM_NURSES
UNION ALL
SELECT 'ANALYTICS.FCT_SHIFT_APPLICATIONS', COUNT(*) FROM CAREMATCH.ANALYTICS.FCT_SHIFT_APPLICATIONS
UNION ALL
SELECT 'ANALYTICS.AUDIENCE_AT_RISK_NURSES', COUNT(*) FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES;

-- Assert zero duplicate primary keys in DIM_NURSES
SELECT
    nurse_id,
    COUNT(*) AS occurrence_count
FROM CAREMATCH.ANALYTICS.DIM_NURSES
GROUP BY nurse_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows returned

-- ============================================================================
-- 4. HIGHTOUCH AUDIENCE VALIDATION
-- ============================================================================

-- Inspect governed audience destined for Slack #first-project
SELECT
    nurse_id,
    full_name,
    specialty,
    days_since_active,
    churn_risk_score,
    notification_opt_in
FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES
ORDER BY churn_risk_score DESC
LIMIT 10;

-- Verify consent safeguards: No opted-out nurses or recruiter suppressions
SELECT COUNT(*) AS violation_count
FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES
WHERE notification_opt_in = FALSE
   OR nurse_id IN (SELECT nurse_id FROM CAREMATCH.RAW.MANUAL_OVERRIDES WHERE suppress_outreach = TRUE);
-- Expected: 0

-- ============================================================================
-- 5. COPY HISTORY & IDEMPOTENCY AUDIT
-- ============================================================================

-- Query Snowflake load history to show which S3 batch files were ingested
SELECT
    table_name,
    file_name,
    row_count,
    row_parsed,
    status,
    first_error_message,
    last_load_time
FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE schema_name = 'RAW'
ORDER BY last_load_time DESC
LIMIT 25;

-- Proof of idempotency: Rerunning COPY INTO on already loaded files
-- adds 0 rows because Snowflake tracks previously loaded files in LOAD_HISTORY.
