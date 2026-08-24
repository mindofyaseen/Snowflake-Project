-- Load the six Airflow-delivered source domains from S3 into Snowflake.
-- Safe to rerun: COPY INTO tracks previously loaded files.

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CAREMATCH_INGEST_WH;
USE DATABASE CAREMATCH;
USE SCHEMA RAW;

CREATE FILE FORMAT IF NOT EXISTS CAREMATCH_CSV_FORMAT
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  EMPTY_FIELD_AS_NULL = TRUE
  NULL_IF = ('', 'NULL', 'null');

CREATE FILE FORMAT IF NOT EXISTS CAREMATCH_JSON_FORMAT
  TYPE = JSON
  STRIP_OUTER_ARRAY = FALSE;

CREATE STAGE IF NOT EXISTS CAREMATCH_RAW_STAGE
  URL = 's3://carematch-data-237657481511-dev/raw/'
  STORAGE_INTEGRATION = CAREMATCH_S3_INT;

CREATE TABLE IF NOT EXISTS FACILITIES (
  facility_id VARCHAR,
  facility_name VARCHAR,
  city VARCHAR,
  facility_type VARCHAR,
  quality_tier VARCHAR,
  active BOOLEAN,
  record_updated_at TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS NURSES (
  nurse_id VARCHAR,
  full_name VARCHAR,
  email VARCHAR,
  city VARCHAR,
  specialty VARCHAR,
  experience_years INTEGER,
  hire_date DATE,
  license_expiry_date DATE,
  completed_shifts_lifetime INTEGER,
  cancelled_shifts_lifetime INTEGER,
  days_since_active INTEGER,
  notification_opt_in BOOLEAN,
  record_updated_at TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS SHIFTS (
  shift_id VARCHAR,
  facility_id VARCHAR,
  city VARCHAR,
  shift_date DATE,
  start_hour INTEGER,
  hours INTEGER,
  specialty_required VARCHAR,
  base_hourly_rate NUMBER(10,2),
  urgency INTEGER,
  status VARCHAR,
  posted_at TIMESTAMP_TZ
);

CREATE TABLE IF NOT EXISTS APPLICATIONS (
  application_id VARCHAR,
  shift_id VARCHAR,
  nurse_id VARCHAR,
  application_status VARCHAR,
  applied_at TIMESTAMP_TZ,
  source_channel VARCHAR
);

CREATE TABLE IF NOT EXISTS ASSIGNMENTS (
  assignment_id VARCHAR,
  shift_id VARCHAR,
  nurse_id VARCHAR,
  assigned_hourly_rate NUMBER(10,2),
  assignment_outcome VARCHAR,
  cancelled_by VARCHAR
);

CREATE TABLE IF NOT EXISTS HEALTH_SCREENINGS (
  screening_id VARCHAR,
  nurse_id VARCHAR,
  screened_on DATE,
  symptom_flag BOOLEAN,
  license_valid BOOLEAN,
  cleared_to_work BOOLEAN
);

CREATE TABLE IF NOT EXISTS MARKET_CONDITIONS (
  market_date DATE,
  city VARCHAR,
  specialty VARCHAR,
  open_shift_demand INTEGER,
  estimated_available_supply INTEGER,
  market_hourly_rate NUMBER(10,2),
  external_demand_index NUMBER(10,4)
);

CREATE TABLE IF NOT EXISTS NURSE_SCORES (
  nurse_id VARCHAR,
  score_date DATE,
  shift_completion_probability NUMBER(10,4),
  churn_probability NUMBER(10,4),
  estimated_12m_value NUMBER(12,2),
  eligible_for_recommendations BOOLEAN,
  model_version VARCHAR
);

CREATE TABLE IF NOT EXISTS CAMPAIGN_PERFORMANCE (
  campaign_id VARCHAR,
  campaign_date DATE,
  channel VARCHAR,
  city VARCHAR,
  impressions INTEGER,
  clicks INTEGER,
  applicants INTEGER,
  qualified_applicants INTEGER,
  spend_usd NUMBER(12,2)
);

CREATE TABLE IF NOT EXISTS MANUAL_OVERRIDES (
  override_id VARCHAR,
  nurse_id VARCHAR,
  override_type VARCHAR,
  reason_code VARCHAR,
  effective_date DATE,
  expires_on DATE,
  approved_by VARCHAR
);

CREATE TABLE IF NOT EXISTS APP_EVENTS (payload VARIANT);

COPY INTO FACILITIES
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=facilities/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO NURSES
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=nurses/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO SHIFTS
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=shifts/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO APPLICATIONS
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=applications/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO ASSIGNMENTS
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=assignments/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO HEALTH_SCREENINGS
  FROM @CAREMATCH_RAW_STAGE/source=operational/entity=health_screenings/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO MARKET_CONDITIONS
  FROM @CAREMATCH_RAW_STAGE/source=external/entity=market_conditions/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO NURSE_SCORES
  FROM @CAREMATCH_RAW_STAGE/source=data_science/entity=nurse_scores/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO CAMPAIGN_PERFORMANCE
  FROM @CAREMATCH_RAW_STAGE/source=appcast/entity=campaign_performance/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO MANUAL_OVERRIDES
  FROM @CAREMATCH_RAW_STAGE/source=spreadsheets/entity=manual_overrides/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_CSV_FORMAT)
  PATTERN = '.*[.]csv';

COPY INTO APP_EVENTS
  FROM @CAREMATCH_RAW_STAGE/source=app_stream/entity=events/
  FILE_FORMAT = (FORMAT_NAME = CAREMATCH_JSON_FORMAT)
  PATTERN = '.*[.]jsonl';

SELECT 'APPLICATIONS' AS table_name, COUNT(*) AS row_count FROM APPLICATIONS
UNION ALL SELECT 'APP_EVENTS', COUNT(*) FROM APP_EVENTS
UNION ALL SELECT 'ASSIGNMENTS', COUNT(*) FROM ASSIGNMENTS
UNION ALL SELECT 'CAMPAIGN_PERFORMANCE', COUNT(*) FROM CAMPAIGN_PERFORMANCE
UNION ALL SELECT 'FACILITIES', COUNT(*) FROM FACILITIES
UNION ALL SELECT 'HEALTH_SCREENINGS', COUNT(*) FROM HEALTH_SCREENINGS
UNION ALL SELECT 'MANUAL_OVERRIDES', COUNT(*) FROM MANUAL_OVERRIDES
UNION ALL SELECT 'MARKET_CONDITIONS', COUNT(*) FROM MARKET_CONDITIONS
UNION ALL SELECT 'NURSE_SCORES', COUNT(*) FROM NURSE_SCORES
UNION ALL SELECT 'NURSES', COUNT(*) FROM NURSES
UNION ALL SELECT 'SHIFTS', COUNT(*) FROM SHIFTS
ORDER BY table_name;
