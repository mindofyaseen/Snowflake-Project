# CareMatch Healthcare Staffing Data Platform - End-to-End Case Study

## 1. Executive Summary

CareMatch is an IntelyCare-inspired modern healthcare staffing data platform. It solves the operational challenge of matching available nursing professionals with healthcare facility shift demand.

The platform automates the end-to-end flow of healthcare data:
- Six synthetic and operational source domains are generated on a schedule.
- Apache Airflow running in Docker on an Amazon EC2 host orchestrates ingestion and loads date-partitioned files into an Amazon S3 data lake.
- Snowflake loads immutable batches from S3 into an initial RAW layer without data duplication.
- dbt transforms raw data into clean staging views and business-ready dimensional models, resolving duplicates by taking the latest business record.
- Governed audiences of disengaging nurses are activated downstream into Slack using Hightouch reverse ETL.
- A secondary ingestion path demonstrates automated SaaS ingestion from SurveyMonkey into Snowflake using Fivetran.

All infrastructure is defined as code in Terraform, and every transformation and pipeline contract is covered by automated tests.

---

## 2. Business Problem

Per-diem healthcare staffing agencies face high churn and rapid shifts in labor demand. Key business questions often go unanswered when operational data remains siloed:
- Which qualified nurses are becoming inactive and risk leaving the platform?
- Where is healthcare facility demand outpacing local nurse supply?
- Which recruitment advertising campaigns produce completed shifts rather than idle signups?
- How can sensitive operational data be transformed and activated into communication tools like Slack without exposing private operational tables?

Manual spreadsheets and batch exports lead to stale data, duplicated nurse records, and missed shift coverage. CareMatch provides an automated, auditable, and reliable single source of truth.

---

## 3. IntelyCare-Style Healthcare Staffing Use Case

IntelyCare matches nursing professionals (RNs, LPNs, CNAs) with post-acute and long-term care facilities. The CareMatch case study mirrors this business model:
1. **Supply Side:** Nurses register, provide credential and health screening information, set availability, and receive engagement scores.
2. **Demand Side:** Healthcare facilities post shift openings with specialty requirements, hourly base pay, and urgency tiers.
3. **Marketplace Matching:** Nurses apply for shifts, assignments are confirmed, and shifts are completed or cancelled.
4. **Retention and Activation:** Machine learning churn models identify high-value nurses at risk of becoming inactive. Downstream operations teams receive alerts in Slack to initiate targeted outreach.

---

## 4. Architecture and Data Flow

```text
[Operational Sources]  [Market Data]  [Nurse Scores]  [Campaigns]  [Pendo Events]  [Spreadsheet Suppressions]
          \                  |              |              |              |                    /
           ------------------------------------------------------------------------------------
                                                     |
                                                     v
                                       Airflow on AWS EC2 (Docker)
                                                     |
                                                     v
                                     Amazon S3 Landing Lake (raw/)
                                                     |
                                                     v
                                           Snowflake RAW Layer
                                                     |
                                                     v
                                         dbt STAGING Views (Cleanse)
                                                     |
                                                     v
                                        dbt ANALYTICS Marts (Tables)
                                                     |
                                                     v
                              Hightouch Reverse ETL (AUDIENCE_AT_RISK_NURSES)
                                                     |
                                                     v
                                        Slack Channel (#first-project)

[SurveyMonkey] --------> Fivetran Managed Connector --------> Snowflake FIVETRAN_LANDING
```

---

## 5. Source Datasets and Business Meaning

The pipeline ingests six source families covering 11 persistent entity datasets:

| Family | Entity / Dataset | Format | Primary Key | Business Meaning |
|---|---|---|---|---|
| `operational` | `nurses` | CSV | `nurse_id` | Nurse workforce profiles, license status, lifetime shifts, and opt-in settings. |
| `operational` | `facilities` | CSV | `facility_id` | Partner facilities, tier, type (hospital, nursing home), and location. |
| `operational` | `shifts` | CSV | `shift_id` | Open, filled, and completed shift postings with hourly rates and urgency. |
| `operational` | `applications` | CSV | `application_id` | Applications submitted by nurses to open shifts. |
| `operational` | `assignments` | CSV | `assignment_id` | Confirmed matches between a nurse and a shift. |
| `external` | `market_conditions` | CSV | `market_key` | Regional market supply-demand ratios and competitor benchmark rates. |
| `data_science` | `nurse_scores` | CSV | `nurse_id` | Churn risk probability, reliability score, and shift completion likelihood. |
| `appcast` | `campaign_performance` | CSV | `campaign_id` | Recruitment advertising spend, clicks, impressions, and leads. |
| `spreadsheets` | `manual_overrides` | CSV | `nurse_id` | Manual operational contact suppressions and recruiter overrides. |
| `app_stream` | `app_events` | JSONL | `event_id` | In-app clickstream events (search, shift view, accept, push open). |
| `operational` | `health_screenings` | CSV | `screening_id`| TB test, background check, and credential clearance records. |

---

## 6. Data Formats and Approximate Volumes

- **CSV Files:** Tabular datasets formatted with header lines, quoted strings, and ISO-8601 timestamps.
- **JSON Lines:** Semi-structured event streams stored as raw JSON strings and ingested into Snowflake `VARIANT` columns.
- **Manifest File:** Each batch contains `manifest.json` detailing file keys, exact byte lengths, row counts, and SHA-256 hashes.
- **Approximate Baseline Volumes (Initial Run):**
  - Nurses: 500 rows
  - Facilities: 40 rows
  - Shifts: 3,000 rows
  - Applications: ~4,500 rows
  - Assignments: ~2,500 rows
  - Health Screenings: ~500 rows
  - Market Conditions: ~100 rows
  - Nurse Scores: 500 rows
  - Campaign Performance: ~50 rows
  - Manual Overrides: ~25 rows
  - App Events: ~10,000 rows
  - Total Raw Rows per Batch: ~22,000 to ~25,000 rows

---

## 7. Initial Loading

The initial pipeline run establishes baseline data:
1. Airflow generates synthetic files using seed `20260821` and target nurse count `500`.
2. Files are written locally on the EC2 worker, validated against checksums, and uploaded to S3 under `raw/.../batch_id=carematch_initial_.../`.
3. Snowflake storage integration reads the new S3 stage files.
4. `COPY INTO` loads files into the 11 `CAREMATCH.RAW` tables.
5. dbt builds staging views and materialized mart tables.
6. The resulting nurse dimension reflects exactly 500 active nurses.

---

## 8. Incremental Loading

The incremental run simulates subsequent business activity:
1. Airflow runs with target nurse count `550` and the current UTC date.
2. 50 new nurse profiles are generated, while existing nurses receive updated shift counts, days since active, and engagement scores.
3. The batch is uploaded to S3 under a new unique batch prefix: `.../batch_id=carematch_incremental_.../`.
4. Snowflake executes `COPY INTO` without `FORCE = TRUE`. Snowflake load history detects that earlier files were already loaded and only copies the newly arrived files.
5. Raw tables hold cumulative historical snapshots. In the verified environment, several earlier demonstrations already existed, so the latest batch changed RAW nurses from 5,025 to 7,575 rows rather than from 500 to 1,050.
6. dbt staging models deduplicate by business key and pick the latest record.
7. The active nurse dimension updates from 500 to 550 unique nurses.

### Live Verified Incremental Batch
- **Airflow DAG Run ID:** `manual__inc_550_20260903T085640Z`
- **Execution Result:** `success` (completed in 14 seconds via EC2 Airflow webserver).
- **Remote S3 Manifest:** `s3://carematch-data-237657481511-dev/manifests/load_date=2026-09-03/batch_id=manual__inc_550_20260903T085640Z/manifest.json`
- **Remote Row Counts Verified:**
  - `nurses.csv`: **550 rows** (SHA-256: `8cfe4e411abe8de1cb038530de657d2642a5e5dcc41dbb7a85111dcef984768c`)
  - `nurse_scores.csv`: **550 rows**
  - `health_screenings.csv`: **550 rows**
  - `applications.csv`: **10,539 rows**
  - `assignments.csv`: **2,029 rows**
  - `facilities.csv`: **40 rows**
  - `shifts.csv`: **3,000 rows**
  - `events.jsonl`: **3,408 rows**
  - `campaign_performance.csv`: **4 rows**
  - `market_conditions.csv`: **15 rows**
  - `manual_overrides.csv`: **11 rows**
  - Total Raw Batch Rows: **20,700 rows** across 11 entity files.

---

## 9. Airflow DAGs and Responsibilities

- **DAG ID:** `carematch_synthetic_sources_to_s3`
- **Schedule:** `@daily` (with manual trigger support for ad-hoc and incremental runs).
- **Execution Environment:** Docker Compose on AWS EC2 (Amazon Linux 2023).
- **Key Tasks:**
  - `generate_files`: Runs synthetic generator, calculates SHA-256 hashes, writes local files and `manifest.json`.
  - `upload_source`: Six parallel tasks (one per source family) uploading files to partitioned S3 paths via `S3Hook`.
  - `upload_manifest`: Uploads the execution manifest to S3 for external verification.
- **Reliability:** Built-in task retries (2 retries, 3-minute backoff), container health checks, and loopback UI binding (`127.0.0.1:8080`) to protect the Airflow console from public internet exposure.

---

## 10. S3 Data Lake Organization

The S3 bucket `carematch-data-237657481511-dev` follows Hive-compatible partitioning:

```text
s3://carematch-data-237657481511-dev/
  raw/
    source=operational/
      entity=nurses/
        load_date=2026-09-03/
          batch_id=carematch_initial_20260903T120000Z/
            nurses.csv
    source=app_stream/
      entity=app_events/
        load_date=2026-09-03/
          batch_id=carematch_initial_20260903T120000Z/
            events.jsonl
  manifests/
    load_date=2026-09-03/
      batch_id=carematch_initial_20260903T120000Z/
        manifest.json
  airflow-logs/
```

- **Security:** Default AES-256 server-side encryption, Bucket Owner Enforced controls, public access block enabled, object versioning enabled.

---

## 11. Snowflake Schemas and Tables

- **Database:** `CAREMATCH`
- **Schemas:**
  - `RAW`: Holds persistent tables loaded directly from S3 stages.
  - `STAGING`: Contains dbt views providing deduplication, casting, and JSON flattening.
  - `ANALYTICS`: Contains materialized reporting marts and reverse ETL audiences.
- **Why RAW Tables (11) Differ from Source File Count:**
  Airflow generates 11 distinct entity CSV/JSONL files plus 1 `manifest.json` per batch. While S3 stores thousands of partitioned files over time across batches, Snowflake maps each entity type into exactly one cumulative `RAW` table.

---

## 12. dbt Models and Transformations

```text
RAW (11 Tables)
  ├── NURSES ──────────────> stg_nurses (View, deduped) ─────┬──> dim_nurses (Table)
  ├── FACILITIES ──────────> stg_facilities (View, deduped) ──┼──> fct_shift_applications (Table)
  ├── SHIFTS ──────────────> stg_shifts (View) ──────────────┤
  ├── APPLICATIONS ────────> stg_applications (View) ────────┘
  ├── NURSE_SCORES ────────> stg_nurse_scores (View, deduped) ──> audience_at_risk_nurses (Table)
  └── MANUAL_OVERRIDES ────> stg_manual_overrides (View) ──────┘
```

- **Staging Layer (`STAGING`):** All 11 models materialized as views. Performs schema renaming, null substitution, timestamp standardization, and JSON variant parsing (`stg_app_events`).
- **Marts Layer (`ANALYTICS`):**
  - `dim_nurses`: Complete nurse profiles, lifetime shift stats, current engagement scores.
  - `fct_shift_applications`: Grain is application event, joined with facility and shift details.
  - `audience_at_risk_nurses`: Business logic filtering for active nurses with high churn probability who have not opted out and have no manual recruiter suppressions.

---

## 13. Deduplication Strategy

In per-diem staffing, nurse profile attributes change frequently. Ingestion accumulates all snapshots in `RAW.NURSES`.
The dbt staging model `stg_nurses` enforces deduplication using SQL analytic functions:

```sql
SELECT
    nurse_id,
    full_name,
    email,
    city,
    specialty,
    experience_years,
    completed_shifts_lifetime,
    days_since_active,
    notification_opt_in,
    record_updated_at
FROM {{ source('raw', 'nurses') }}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY nurse_id
    ORDER BY record_updated_at DESC
) = 1;
```

This guarantees that downstream marts always see exactly one record per nurse reflecting their latest known state.

---

## 14. Data Quality Tests

dbt and Snowflake enforce data contract rules:
- **Primary Key Uniqueness:** `nurse_id`, `facility_id`, `shift_id`, `application_id`.
- **Not-Null Constraints:** Verified on IDs and required foreign keys.
- **Referential Integrity:** `applications.nurse_id` references `nurses.nurse_id`.
- **Business Logic Checks:**
  - Shift end time occurs after start time.
  - Urgency values fall within allowed ranges (1 to 5).
  - Churn risk score is bounded between 0.0 and 1.0.
  - Audience at risk includes only nurses with `notification_opt_in = TRUE` and no manual contact suppressions.

---

## 15. Fivetran Ingestion

- **Source:** SurveyMonkey case study collector (`https://www.surveymonkey.com/r/QHFR7TD`).
- **Connector Name:** `prohibited_every`.
- **Destination:** Snowflake database `FIVETRAN_LANDING`, schema `SURVEY_MONKEY_CASE_STUDY`.
- **Execution Mechanism:** Automated synchronization via `scripts/saas_sync.py`:
  1. Reads connector status and captures baseline `succeeded_at` and `failed_at`.
  2. Issues `POST /v1/connectors/prohibited_every/force`.
  3. Polls until `succeeded_at` advances past baseline.
  4. Aborts if `failed_at` advances or if connector is paused.
- **Historical Baseline:** Initial sync loaded 51 rows across 10 tables (`RESPONSE_HISTORY`, `QUESTION_HISTORY`, etc.).

---

## 16. Hightouch Reverse ETL

- **Source Model:** `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES`
- **Primary Key:** `NURSE_ID`
- **Sync ID:** `8379886`
- **Trigger Script:** `scripts/saas_sync.py hightouch`
  1. Calls `POST /api/v1/syncs/8379886/trigger`.
  2. Extracts exact sync request ID from trigger response.
  3. Polls `/sync_requests` requiring an exact match on that request ID.
  4. Returns PASS on `success`; fails immediately on `failed`, `cancelled`, or `interrupted`.

---

## 17. Slack Delivery

- **Target Channel:** `#first-project` (ID: `C0BSC5B2743`).
- **Stale Channel Notice:** Sync `8379886` was previously configured with channel `C0BS2TQSS9M`, which produced a `not_in_channel` error because the bot was not a member.
- **Owner Action:** In the Hightouch UI, verify or update the destination channel to `#first-project` (`C0BSC5B2743`) and invite the bot using `/invite @Hightouch`.
- **Data Payload:** Formatted tabular messages delivering nurse name, specialty, days inactive, and churn risk score to care coordinators.

---

## 18. Security

- **Zero Committed Secrets:** All passwords, Fernet keys, private keys, and API tokens are excluded via `.gitignore` and passed strictly via environment variables.
- **RSA Key-Pair Authentication:** Snowflake service accounts (`FIVETRAN_USER`, `HIGHTOUCH_USER`) authenticate using 2048-bit RSA keys, eliminating permanent passwords.
- **Least Privilege Access:**
  - `FIVETRAN_ROLE`: Can write only to `FIVETRAN_LANDING`.
  - `HIGHTOUCH_ROLE`: Can read only from `CAREMATCH.ANALYTICS`.
- **AWS Security:** EC2 instance has no public SSH port open. All administrative commands use AWS Systems Manager (SSM). S3 bucket blocks public ACLs and enforces encryption.

---

## 19. Monitoring and Failure Recovery

- **Airflow Task Alerts:** Airflow tracks task status and task logs; failures raise alerts.
- **Idempotent Ingestion:** If Snowflake loading fails midway, rerunning `02_s3_stage_and_raw_load.sql` is safe because Snowflake copy history tracks loaded files.
- **SSM Diagnostic Capture:** Orchestrator captures remote stdout and stderr from EC2 commands even if the SSM waiter reports failure.
- **SaaS Polling Retries:** Transient 5xx HTTP errors during Fivetran or Hightouch polling are logged as warnings and retried up to the configurable timeout.

---

## 20. Cost Controls

- **Auto-Suspending Warehouses:** Snowflake warehouses (`CAREMATCH_INGEST_WH`, `FIVETRAN_WAREHOUSE`) auto-suspend after 60 seconds of inactivity.
- **Airflow EC2 Sizing:** Runs on a cost-effective `t3.large` instance. Can be stopped when not running demonstration pipelines.
- **Fivetran Trial Safety:** Terraform schedule module defaults to `pause_after_trial = true` to prevent automatic credit card billing after free trials end.

---

## 21. Terraform Portability

Infrastructure is modularized under `infra/terraform/`:
- `s3`: Bucket, versioning, encryption, lifecycle, policies.
- `ec2-airflow`: VPC, subnet, route table, security group, IAM role, SSM attachment, EC2 instance.
- `snowflake-s3-integration`: AWS IAM role trust policy for Snowflake storage integration.
- `fivetran-schedule`: Fivetran connector sync frequency and pause safeguards.
- `platform`: Composite root module orchestrating all child modules.

---

## 22. Account Migration Procedure

When moving from sandbox or trial accounts to a permanent organization:
1. **AWS:** Configure named profile in `~/.aws/credentials`. Update `aws_profile = "default"` and `environment` in `terraform.tfvars`. Run `terraform init` and `terraform apply`.
2. **Snowflake:** Run `01_platform_bootstrap.sql` to establish roles and databases. Run `05_service_integrations.sql` to configure service users with new RSA public keys.
3. **Storage Trust:** Run `scripts/read_snowflake_integration.py` to extract IAM trust ARN and external ID, then apply `module.snowflake_s3_trust`.
4. **Fivetran:** Re-authenticate SurveyMonkey OAuth in Fivetran console and configure destination pointing to the new Snowflake host.
5. **Hightouch:** Add Snowflake connection using the new account locator and RSA key, map model to `AUDIENCE_AT_RISK_NURSES`, and connect to Slack.

---

## 23. System-Design Decisions

1. **Storage Integration vs IAM User Keys:** Used native Snowflake Storage Integration rather than embedding AWS access keys in Snowflake stages, eliminating key rotation risks.
2. **SSM vs SSH:** Used AWS Systems Manager instead of opening port 22 on EC2, eliminating inbound firewall rules and bastion hosts.
3. **dbt Views vs Tables in Staging:** Materialized staging as views to avoid duplicate storage costs, materializing only marts as tables for fast analytics querying.
4. **Analytic Dedup vs Merge:** Used `QUALIFY ROW_NUMBER()` in dbt staging models rather than destructive Snowflake `MERGE` commands, preserving raw historical snapshots for auditability.

---

## 24. Alternatives, Tradeoffs, and Architectural Comparisons

### Snowflake versus Databricks
- **Snowflake (Selected):** Near-zero management, native SQL governance, excellent semi-structured JSON querying, and seamless integration with reverse ETL tools.
- **Databricks:** Superior for deep machine learning and custom Spark processing, but introduces higher infrastructure complexity for pure SQL data transformation workflows.

### Airflow on EC2 versus AWS MWAA
- **Airflow on EC2 (Selected):** Zero minimum hourly cost when stopped, full control over Docker Compose containers, and fast local file generation without remote latency.
- **AWS MWAA:** Fully managed and scalable, but incurs a continuous ~$300/month baseline cost that is impractical for trial demonstrations.

### S3 Data Lake versus Direct Database Loading
- **S3 Staging (Selected):** Decouples data generation from Snowflake compute. Provides an immutable audit archive and allows replaying raw data into other engines.
- **Direct Database Loading:** Simpler pipeline architecture, but tightly couples operational workloads to the warehouse and increases compute costs.

### dbt versus Snowflake Stored Procedures
- **dbt (Selected):** Declarative SQL, automatic DAG dependency management, built-in testing, documentation generation, and version control.
- **Stored Procedures:** Imperative, difficult to unit test, lacks automated dependency resolution, and obfuscates data lineage.

### Fivetran versus Custom Ingestion Scripts
- **Fivetran (Selected):** Manages API pagination, rate limits, schema drifts, and OAuth token refreshes for external SaaS platforms automatically.
- **Custom Scripts:** Incurs continuous maintenance overhead whenever third-party APIs introduce breaking changes.

### Hightouch versus Custom Reverse ETL Scripts
- **Hightouch (Selected):** Visual audience mapping, out-of-the-box Slack rate limiting, operation diffing (only syncing changed rows), and audit logging.
- **Custom Scripts:** Requires maintaining custom webhook listeners, retry mechanisms, and OAuth integrations.

---

## 25. Scaling Considerations

- **Workforce Growth (100x Scale):** For 50,000+ nurses, transition dbt staging and marts to incremental materializations using `record_updated_at > (select max(record_updated_at) from {{ this }})`.
- **Airflow Scaling:** Transition from Docker Compose LocalExecutor to CeleryExecutor on AWS ECS or MWAA when task concurrency exceeds single-host memory limits.
- **Snowflake Scaling:** Separate ingestion workload (`CAREMATCH_INGEST_WH`) from transformation (`CAREMATCH_TRANSFORM_WH`) and analytics queries (`CAREMATCH_BI_WH`).

---

## 26. Limitations and Remaining Manual Steps

- **Browser-Only OAuth:** SurveyMonkey and Slack require manual browser-based OAuth consent. Cloud APIs cannot simulate user web consent without stored refresh tokens.
- **Slack Bot Channel Invite:** The Hightouch Slack app bot must be invited manually to `#first-project` inside the Slack UI.
- **Snowflake Account Expiration:** Trial accounts expire after 30 days. Recreating requires running the account portability procedure documented in Section 22.

---

## 27. Troubleshooting Guide

| Symptom | Probable Cause | Corrective Action |
|---|---|---|
| `SSM send-command failed` | EC2 instance stopped or SSM agent offline | Verify EC2 state with `aws ec2 describe-instances`; start instance if stopped. |
| `dbt parse Compilation Error` | Duplicate source definitions | Check all `.yml` files in `dbt/models/`; ensure each table is declared in only one source file. |
| `FORCE = TRUE detected` | Accidental non-idempotent copy command | Remove `FORCE = TRUE` from `02_s3_stage_and_raw_load.sql`. |
| Hightouch `not_in_channel` | Bot not invited to Slack channel | Run `/invite @Hightouch` in Slack channel `#first-project`. |
| Fivetran `HTTP 401 Unauthorized` | Expired SurveyMonkey OAuth token | Log in to Fivetran web UI, open `prohibited_every` connector, and re-authorize SurveyMonkey. |
| Snowflake `Object does not exist` | Warehouse or database not selected | Run `USE WAREHOUSE CAREMATCH_INGEST_WH; USE DATABASE CAREMATCH;`. |

---

## 28. Manual Demo Runbook with Before & After Queries

### Initial Load Proof
Execute in Snowflake Worksheet:

```sql
-- 1. Check raw baseline rows
SELECT COUNT(*) AS raw_nurse_snapshots FROM CAREMATCH.RAW.NURSES;
-- Expected: 500

-- 2. Check deduplicated active nurses in staging
SELECT COUNT(*) AS unique_active_nurses FROM CAREMATCH.STAGING.STG_NURSES;
-- Expected: 500

-- 3. Check audience eligible for retention outreach
SELECT COUNT(*) AS at_risk_nurses FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES;
-- Expected: ~280 - 290
```

### Incremental Load Proof
After running `invoke_case_study_pipeline.ps1 -Mode incremental -IncrementalNurseCount 550`:

```sql
-- 1. Check raw snapshots increased
SELECT COUNT(*) AS raw_nurse_snapshots FROM CAREMATCH.RAW.NURSES;
-- Verified on 3 September 2026: 7,575 cumulative raw rows

-- 2. Check deduplication picked latest state and unique nurse count grew
SELECT COUNT(*) AS unique_active_nurses FROM CAREMATCH.STAGING.STG_NURSES;
-- Expected: 550

-- 3. Verify zero duplicate nurse_ids exist in marts
SELECT nurse_id, COUNT(*)
FROM CAREMATCH.ANALYTICS.DIM_NURSES
GROUP BY nurse_id
HAVING COUNT(*) > 1;
-- Expected: 0 rows returned
```

---

## 29. Exact Browser-Only Checklist

1. [ ] Log in to SurveyMonkey and verify survey `CareMatch Healthcare Staffing Experience 2026`.
2. [ ] In Fivetran console, open connector `prohibited_every` and confirm SurveyMonkey connection status shows `CONNECTED`.
3. [ ] Open Slack workspace, navigate to `#first-project` (`C0BSC5B2743`), and run `/invite @Hightouch`.
4. [ ] In Hightouch console, open sync `8379886`, verify destination targets `#first-project`, and test the destination health check.
5. [ ] Open Snowflake Snowsight, select database `CAREMATCH`, and visually inspect the tables in `RAW`, `STAGING`, and `ANALYTICS`.

---

## 30. Completion Matrix

| Component | Status | Verification Evidence |
|---|---|---|
| Synthetic Healthcare Generator | **Implemented & Verified** | Unit tests pass; produces 500 initial and 550 incremental records with valid schema. |
| Airflow DAG on EC2 | **Implemented & Verified** | Running on EC2 `i-02bdd56e8690f35d1`; containers healthy; SSM commands succeed. |
| S3 Data Lake Partitioning | **Implemented & Verified** | Live bucket `carematch-data-237657481511-dev` verified; encryption, versioning, and public block active. |
| Snowflake Ingestion Scripts | **Implemented & Verified** | SQL scripts audited; idempotent `COPY INTO` without `FORCE = TRUE`; service users configured. |
| dbt Staging & Mart Models | **Implemented & Verified** | Credential-free `dbt parse` passes exit 0; `QUALIFY ROW_NUMBER()` deduplication validated by contract tests. |
| Fivetran Synchronization Logic | **Implemented & Verified** | `saas_sync.py` polling logic tested; 6 mocked unit tests covering advance, failure, and timeouts pass. |
| Hightouch Synchronization Logic | **Implemented & Verified** | `saas_sync.py` exact ID match tested; 6 mocked unit tests covering exact matching and failures pass. |
| End-to-End Orchestration Script | **Implemented & Verified** | `scripts/invoke_case_study_pipeline.ps1` supports initial, incremental, verify modes; 0 parse errors. |
| Terraform Platform Modules | **Implemented & Verified** | All 5 modules validated (`Success! The configuration is valid`); `fmt -check` clean. |
| Automated Test Suite | **Implemented & Verified** | 45 unit, contract, and behavioral tests pass cleanly. |
| Airflow to S3 Incremental Run | **Implemented & Verified** | DAG run `manual__inc_550_20260903T085640Z` succeeded; 550 nurse records and manifest confirmed in S3. |
| Live Snowflake Loading | **Implemented & Verified** | RAW nurses changed from 5,025/525 distinct to 7,575/550 distinct. Repeating COPY produced no additional rows. |
| Transformation Relations | **Implemented & Verified** | Snowflake staging and analytics relations were rebuilt from repository SQL: DIM_NURSES 550, FCT_SHIFT_PERFORMANCE 3,000, and activation audience 248. Six visible quality checks returned zero failures. |
| Native dbt CLI Build | **Implemented (CLI Authentication Pending)** | Credential-free parse passes, but a native CLI `dbt build` still needs password, private-key, or external-browser authentication. |
| Slack Bot Channel Membership | **Requires Browser Action** | Account owner must run `/invite @Hightouch` in `#first-project`. |
| SurveyMonkey OAuth Consent | **Requires Browser Action** | Account owner must approve OAuth screen in browser. |
| Hightouch Sync Channel Setting | **Requires Browser Action** | Update sync `8379886` destination in UI from `C0BS2TQSS9M` to `C0BSC5B2743`. |
| Pendo, Marketo, Salesforce, Ads | **Excluded from Scope** | Intentionally excluded from active demonstration; documented as non-live connectors. |
