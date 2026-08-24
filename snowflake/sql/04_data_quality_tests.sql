-- SQL representation of the dbt uniqueness, relationship, and policy tests.

USE ROLE CAREMATCH_TRANSFORMER;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;

WITH test_results AS (
  SELECT 'nurses_primary_key' AS test_name,
         COUNT(*) - COUNT(DISTINCT nurse_id) + COUNT_IF(nurse_id IS NULL) AS failing_rows
  FROM STAGING.STG_NURSES

  UNION ALL
  SELECT 'shifts_primary_key',
         COUNT(*) - COUNT(DISTINCT shift_id) + COUNT_IF(shift_id IS NULL)
  FROM STAGING.STG_SHIFTS

  UNION ALL
  SELECT 'applications_primary_key',
         COUNT(*) - COUNT(DISTINCT application_id) + COUNT_IF(application_id IS NULL)
  FROM STAGING.STG_APPLICATIONS

  UNION ALL
  SELECT 'assignments_primary_key',
         COUNT(*) - COUNT(DISTINCT assignment_id) + COUNT_IF(assignment_id IS NULL)
  FROM STAGING.STG_ASSIGNMENTS

  UNION ALL
  SELECT 'assignment_relationships', COUNT(*)
  FROM STAGING.STG_ASSIGNMENTS a
  LEFT JOIN STAGING.STG_SHIFTS s USING (shift_id)
  LEFT JOIN STAGING.STG_NURSES n USING (nurse_id)
  WHERE s.shift_id IS NULL OR n.nurse_id IS NULL

  UNION ALL
  SELECT 'application_relationships', COUNT(*)
  FROM STAGING.STG_APPLICATIONS a
  LEFT JOIN STAGING.STG_SHIFTS s USING (shift_id)
  LEFT JOIN STAGING.STG_NURSES n USING (nurse_id)
  WHERE s.shift_id IS NULL OR n.nurse_id IS NULL

  UNION ALL
  SELECT 'activation_audience_policy', COUNT(*)
  FROM ANALYTICS.AUDIENCE_AT_RISK_NURSES
  WHERE NOT notification_opt_in OR has_active_override OR email IS NULL
)
SELECT *
FROM test_results
ORDER BY test_name;
