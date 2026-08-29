-- Read-only before-and-after evidence for the CareMatch incremental demo.
-- Run this before Airflow, again after 02_s3_stage_and_raw_load.sql, and after dbt.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;

-- RAW retains every landed snapshot. This count must grow after a new S3 batch.
SELECT
  COUNT(*) AS raw_nurse_snapshots,
  COUNT(DISTINCT nurse_id) AS distinct_nurse_ids,
  MAX(TO_DATE(record_updated_at)) AS latest_source_date
FROM RAW.NURSES;

-- Shows the number of rows belonging to each source date.
SELECT
  TO_DATE(record_updated_at) AS source_date,
  COUNT(*) AS nurse_rows
FROM RAW.NURSES
GROUP BY source_date
ORDER BY source_date DESC;

-- METADATA$FILENAME exists only while querying a stage. For table load evidence,
-- use Snowflake COPY history instead of selecting METADATA$FILENAME from RAW.NURSES.
SELECT
  file_name,
  row_count,
  row_parsed,
  status,
  last_load_time
FROM TABLE(
  INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'CAREMATCH.RAW.NURSES',
    START_TIME => DATEADD(day, -14, CURRENT_TIMESTAMP())
  )
)
ORDER BY last_load_time DESC;

-- STAGING is the latest deduplicated state produced by dbt.
SELECT
  COUNT(*) AS current_nurses,
  COUNT(DISTINCT nurse_id) AS distinct_current_nurses
FROM STAGING.STG_NURSES;

-- Hightouch reads this governed, business-ready audience.
SELECT COUNT(*) AS at_risk_nurses
FROM ANALYTICS.AUDIENCE_AT_RISK_NURSES;
