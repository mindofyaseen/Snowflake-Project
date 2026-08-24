-- Deploy the same relations defined in /dbt for immediate validation.
-- The dbt project remains the source of truth for ongoing transformations.

USE ROLE CAREMATCH_TRANSFORMER;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;

CREATE OR REPLACE VIEW STAGING.STG_NURSES AS
SELECT
  nurse_id,
  full_name,
  LOWER(email) AS email,
  city,
  specialty,
  experience_years,
  hire_date,
  license_expiry_date,
  completed_shifts_lifetime,
  cancelled_shifts_lifetime,
  days_since_active,
  notification_opt_in,
  record_updated_at,
  cancelled_shifts_lifetime / NULLIF(completed_shifts_lifetime + cancelled_shifts_lifetime, 0) AS lifetime_cancel_rate
FROM RAW.NURSES
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY nurse_id
  ORDER BY record_updated_at DESC
) = 1;

CREATE OR REPLACE VIEW STAGING.STG_SHIFTS AS
SELECT
  shift_id,
  facility_id,
  city,
  shift_date,
  start_hour,
  hours,
  specialty_required,
  base_hourly_rate,
  urgency,
  LOWER(status) AS shift_status,
  posted_at,
  hours * base_hourly_rate AS estimated_shift_value
FROM RAW.SHIFTS
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY shift_id
  ORDER BY posted_at DESC
) = 1;

CREATE OR REPLACE VIEW STAGING.STG_ASSIGNMENTS AS
SELECT
  assignment_id,
  shift_id,
  nurse_id,
  assigned_hourly_rate,
  LOWER(assignment_outcome) AS assignment_outcome,
  LOWER(cancelled_by) AS cancelled_by
FROM RAW.ASSIGNMENTS
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY assignment_id
  ORDER BY assignment_id
) = 1;

CREATE OR REPLACE VIEW STAGING.STG_APPLICATIONS AS
SELECT
  application_id,
  shift_id,
  nurse_id,
  LOWER(application_status) AS application_status,
  applied_at,
  LOWER(source_channel) AS source_channel
FROM RAW.APPLICATIONS
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY application_id
  ORDER BY applied_at DESC
) = 1;

CREATE OR REPLACE VIEW STAGING.STG_APP_EVENTS AS
SELECT
  payload:event_id::VARCHAR AS event_id,
  payload:event_name::VARCHAR AS event_name,
  payload:event_timestamp::TIMESTAMP_TZ AS event_timestamp,
  payload:nurse_id::VARCHAR AS nurse_id,
  payload:platform::VARCHAR AS platform,
  payload:session_id::VARCHAR AS session_id
FROM RAW.APP_EVENTS
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY payload:event_id::VARCHAR
  ORDER BY payload:event_timestamp::TIMESTAMP_TZ DESC
) = 1;

CREATE OR REPLACE TABLE ANALYTICS.DIM_NURSES AS
WITH latest_score AS (
  SELECT *
  FROM RAW.NURSE_SCORES
  QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ORDER BY score_date DESC) = 1
),
latest_screening AS (
  SELECT *
  FROM RAW.HEALTH_SCREENINGS
  QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ORDER BY screened_on DESC) = 1
),
active_override AS (
  SELECT *
  FROM RAW.MANUAL_OVERRIDES
  WHERE CURRENT_DATE BETWEEN effective_date AND expires_on
  QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ORDER BY effective_date DESC) = 1
)
SELECT
  n.*,
  s.shift_completion_probability,
  s.churn_probability,
  s.estimated_12m_value,
  s.eligible_for_recommendations,
  h.cleared_to_work,
  h.license_valid,
  o.override_type,
  o.reason_code AS override_reason,
  IFF(o.nurse_id IS NOT NULL, TRUE, FALSE) AS has_active_override,
  IFF(n.days_since_active >= 30 OR s.churn_probability >= 0.65, TRUE, FALSE) AS is_at_risk
FROM STAGING.STG_NURSES n
LEFT JOIN latest_score s USING (nurse_id)
LEFT JOIN latest_screening h USING (nurse_id)
LEFT JOIN active_override o USING (nurse_id);

CREATE OR REPLACE TABLE ANALYTICS.FCT_SHIFT_PERFORMANCE AS
WITH application_rollup AS (
  SELECT
    shift_id,
    COUNT(*) AS application_count,
    COUNT_IF(application_status = 'accepted') AS accepted_application_count,
    MIN(applied_at) AS first_application_at
  FROM STAGING.STG_APPLICATIONS
  GROUP BY 1
),
assignment_rollup AS (
  SELECT
    shift_id,
    COUNT(*) AS assignment_count,
    COUNT_IF(assignment_outcome = 'completed') AS completed_assignment_count,
    COUNT_IF(cancelled_by NOT IN ('none', '')) AS cancelled_assignment_count,
    AVG(assigned_hourly_rate) AS average_assigned_hourly_rate
  FROM STAGING.STG_ASSIGNMENTS
  GROUP BY 1
),
latest_facility AS (
  SELECT *
  FROM RAW.FACILITIES
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY facility_id
    ORDER BY record_updated_at DESC
  ) = 1
)
SELECT
  s.*,
  f.facility_name,
  f.facility_type,
  f.quality_tier,
  COALESCE(a.application_count, 0) AS application_count,
  COALESCE(a.accepted_application_count, 0) AS accepted_application_count,
  a.first_application_at,
  COALESCE(x.assignment_count, 0) AS assignment_count,
  COALESCE(x.completed_assignment_count, 0) AS completed_assignment_count,
  COALESCE(x.cancelled_assignment_count, 0) AS cancelled_assignment_count,
  x.average_assigned_hourly_rate,
  IFF(x.assignment_count > 0, TRUE, FALSE) AS was_filled,
  IFF(x.completed_assignment_count > 0, TRUE, FALSE) AS was_completed
FROM STAGING.STG_SHIFTS s
LEFT JOIN latest_facility f USING (facility_id)
LEFT JOIN application_rollup a USING (shift_id)
LEFT JOIN assignment_rollup x USING (shift_id);

CREATE OR REPLACE TABLE ANALYTICS.MART_MARKETING_EFFICIENCY AS
SELECT
  campaign_date,
  channel,
  city,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(applicants) AS applicants,
  SUM(qualified_applicants) AS qualified_applicants,
  SUM(spend_usd) AS spend_usd,
  SUM(clicks) / NULLIF(SUM(impressions), 0) AS click_through_rate,
  SUM(qualified_applicants) / NULLIF(SUM(applicants), 0) AS qualification_rate,
  SUM(spend_usd) / NULLIF(SUM(applicants), 0) AS cost_per_applicant,
  SUM(spend_usd) / NULLIF(SUM(qualified_applicants), 0) AS cost_per_qualified_applicant
FROM RAW.CAMPAIGN_PERFORMANCE
GROUP BY 1, 2, 3;

CREATE OR REPLACE TABLE ANALYTICS.MART_MARKET_SUPPLY_DEMAND AS
SELECT
  market_date,
  city,
  specialty,
  open_shift_demand,
  estimated_available_supply,
  open_shift_demand - estimated_available_supply AS supply_gap,
  open_shift_demand / NULLIF(estimated_available_supply, 0) AS demand_supply_ratio,
  market_hourly_rate,
  external_demand_index
FROM RAW.MARKET_CONDITIONS;

CREATE OR REPLACE TABLE ANALYTICS.AUDIENCE_AT_RISK_NURSES AS
SELECT
  nurse_id,
  full_name,
  email,
  city,
  specialty,
  days_since_active,
  churn_probability,
  estimated_12m_value,
  notification_opt_in,
  has_active_override,
  override_type
FROM ANALYTICS.DIM_NURSES
WHERE is_at_risk
  AND notification_opt_in
  AND NOT has_active_override
  AND COALESCE(cleared_to_work, FALSE);

SELECT 'DIM_NURSES' AS model_name, COUNT(*) AS row_count FROM ANALYTICS.DIM_NURSES
UNION ALL SELECT 'FCT_SHIFT_PERFORMANCE', COUNT(*) FROM ANALYTICS.FCT_SHIFT_PERFORMANCE
UNION ALL SELECT 'MART_MARKETING_EFFICIENCY', COUNT(*) FROM ANALYTICS.MART_MARKETING_EFFICIENCY
UNION ALL SELECT 'MART_MARKET_SUPPLY_DEMAND', COUNT(*) FROM ANALYTICS.MART_MARKET_SUPPLY_DEMAND
UNION ALL SELECT 'AUDIENCE_AT_RISK_NURSES', COUNT(*) FROM ANALYTICS.AUDIENCE_AT_RISK_NURSES
ORDER BY model_name;
