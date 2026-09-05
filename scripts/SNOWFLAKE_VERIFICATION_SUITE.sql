-- ============================================================================
-- CareMatch Data Platform: Complete Snowflake Verification & Demo Suite
-- ============================================================================
-- Is script ko Snowflake Snowsight Worksheet mein paste kar ke run karen.
-- Tamam queries READ-ONLY hain aur safely execute hoti hain.

-- ----------------------------------------------------------------------------
-- 0. INITIAL SETUP: Role, Warehouse aur Database Select Karna
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;

-- ============================================================================
-- 1. RAW LAYER ROW COUNTS: Tamam 11 Tables ka Data Audit
-- ============================================================================
SELECT 'RAW.NURSES' AS table_name, COUNT(*) AS row_count FROM CAREMATCH.RAW.NURSES
UNION ALL
SELECT 'RAW.SHIFTS', COUNT(*) FROM CAREMATCH.RAW.SHIFTS
UNION ALL
SELECT 'RAW.APPLICATIONS', COUNT(*) FROM CAREMATCH.RAW.APPLICATIONS
UNION ALL
SELECT 'RAW.ASSIGNMENTS', COUNT(*) FROM CAREMATCH.RAW.ASSIGNMENTS
UNION ALL
SELECT 'RAW.FACILITIES', COUNT(*) FROM CAREMATCH.RAW.FACILITIES
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
SELECT 'RAW.APP_EVENTS', COUNT(*) FROM CAREMATCH.RAW.APP_EVENTS
ORDER BY table_name;

-- ============================================================================
-- 2. DEDUPLICATION PROOF: Raw Snapshots vs Current Active Nurses
-- ============================================================================
SELECT
    (SELECT COUNT(*) FROM CAREMATCH.RAW.NURSES) AS total_raw_snapshots,
    (SELECT COUNT(DISTINCT nurse_id) FROM CAREMATCH.RAW.NURSES) AS distinct_unique_nurse_ids,
    (SELECT COUNT(*) FROM CAREMATCH.STAGING.STG_NURSES) AS staging_deduplicated_count,
    (SELECT COUNT(*) FROM CAREMATCH.RAW.NURSES) - (SELECT COUNT(*) FROM CAREMATCH.STAGING.STG_NURSES) AS duplicate_snapshots_removed;

-- ============================================================================
-- 3. PROVING LATEST RECORD SELECTION: Window Function Evidence
-- ============================================================================
SELECT
    raw.nurse_id,
    COUNT(*) AS total_snapshots_seen,
    MIN(raw.record_updated_at) AS first_seen_timestamp,
    MAX(raw.record_updated_at) AS latest_raw_timestamp,
    MAX(stg.record_updated_at) AS selected_staging_timestamp
FROM CAREMATCH.RAW.NURSES raw
JOIN CAREMATCH.STAGING.STG_NURSES stg ON raw.nurse_id = stg.nurse_id
GROUP BY raw.nurse_id
HAVING COUNT(*) > 1
ORDER BY total_snapshots_seen DESC
LIMIT 5;

-- ============================================================================
-- 4. ANALYTICS MARTS LAYER: Reporting Tables Status
-- ============================================================================
SELECT 'ANALYTICS.DIM_NURSES' AS mart_table, COUNT(*) AS row_count FROM CAREMATCH.ANALYTICS.DIM_NURSES
UNION ALL
SELECT 'ANALYTICS.FCT_SHIFT_PERFORMANCE', COUNT(*) FROM CAREMATCH.ANALYTICS.FCT_SHIFT_PERFORMANCE
UNION ALL
SELECT 'ANALYTICS.MART_MARKETING_EFFICIENCY', COUNT(*) FROM CAREMATCH.ANALYTICS.MART_MARKETING_EFFICIENCY
UNION ALL
SELECT 'ANALYTICS.MART_MARKET_SUPPLY_DEMAND', COUNT(*) FROM CAREMATCH.ANALYTICS.MART_MARKET_SUPPLY_DEMAND
UNION ALL
SELECT 'ANALYTICS.AUDIENCE_AT_RISK_NURSES', COUNT(*) FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES;

-- ============================================================================
-- 5. PRIMARY KEY INTEGRITY TEST: Zero Duplicate Assertion (Expected: 0 rows)
-- ============================================================================
SELECT
    nurse_id,
    COUNT(*) AS duplicate_count
FROM CAREMATCH.ANALYTICS.DIM_NURSES
GROUP BY nurse_id
HAVING COUNT(*) > 1;

-- ============================================================================
-- 6. REVERSE ETL AUDIENCE (Slack Delivery Preview)
-- ============================================================================
SELECT
    nurse_id,
    full_name,
    email,
    city,
    specialty,
    days_since_active,
    ROUND(churn_probability, 2) AS churn_risk,
    estimated_12m_value,
    notification_opt_in,
    has_active_override
FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES
ORDER BY churn_probability DESC
LIMIT 10;

-- ============================================================================
-- 7. REVERSE ETL COMPLIANCE & CONSENT CHECK (Expected: 0 violations)
-- ============================================================================
SELECT COUNT(*) AS compliance_violations
FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES
WHERE notification_opt_in = FALSE
   OR has_active_override = TRUE;

-- ============================================================================
-- 8. CLINICAL SCREENING & CLEARANCE CHECK (In DIM_NURSES)
-- ============================================================================
SELECT
    nurse_id,
    full_name,
    specialty,
    cleared_to_work,
    license_valid,
    is_at_risk
FROM CAREMATCH.ANALYTICS.DIM_NURSES
WHERE cleared_to_work = TRUE
LIMIT 10;

-- ============================================================================
-- 9. IDEMPOTENCY AUDIT: S3 Ingestion History
-- ============================================================================
SELECT
    table_name,
    file_name,
    row_count,
    status,
    last_load_time
FROM INFORMATION_SCHEMA.LOAD_HISTORY
WHERE schema_name = 'RAW'
ORDER BY last_load_time DESC
LIMIT 15;

-- ============================================================================
-- 10. FIVETRAN SURVEYMONKEY LANDING: Managed SaaS Ingestion Verification
-- ============================================================================
USE WAREHOUSE FIVETRAN_WAREHOUSE;

SELECT
    table_name,
    row_count
FROM FIVETRAN_LANDING.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'SURVEY_MONKEY_CASE_STUDY'
ORDER BY table_name;

SELECT COUNT(*) AS response_history_rows
FROM FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY.RESPONSE_HISTORY;
