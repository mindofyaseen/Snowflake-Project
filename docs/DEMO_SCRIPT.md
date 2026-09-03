# CareMatch Modern Data Stack: Live Presentation & Demo Script

**Target Duration:** 10 - 15 minutes  
**Audience:** Data Engineering Leads, Solution Architects, Technical Hiring Managers  
**Objective:** Walk through the complete IntelyCare-inspired healthcare staffing data platform, showcasing
end-to-end data flow, incremental ingestion, dbt deduplication, and reverse ETL activation.

---

## Part 1: Introduction & The Business Problem (Minutes 00:00 - 02:00)

**Speaker Script:**
> "Welcome everyone. Today I'm demonstrating CareMatch, an end-to-end modern healthcare staffing data platform
> inspired by IntelyCare's operating model.
>
> In per-diem healthcare staffing, post-acute facilities need nurses immediately, and nurses want flexible shifts.
> The business challenge is three-fold:
> 1. Multi-source operational fragmentation: Shift bookings, applications, and licensing credentials come from
>    internal operational databases, while satisfaction surveys live in SaaS apps like SurveyMonkey.
> 2. Clinical churn prevention: Nurses disengage quickly if unfilled shifts aren't matched within 48 hours.
>    We need automated alerts to recruiters to retain at-risk clinical staff.
> 3. Data integrity and deduplication: As nurses update credentials and completed shifts, operational snapshots
>    must be ingested incrementally without double-counting active nurses."

---

## Part 2: Architecture & Infrastructure Walkthrough (Minutes 02:00 - 04:00)

**Speaker Script:**
> "Let's review our architecture.
> - **Orchestration:** Apache Airflow running in Docker Compose on a private AWS EC2 instance.
> - **Data Lake:** Amazon S3 with immutable Hive-style partitioning and cryptographic manifest verification.
> - **Warehouse:** Snowflake, decoupled compute and storage with native COPY_HISTORY idempotency.
> - **Transformations:** dbt for automated deduplication and dimensional marts.
> - **SaaS Ingestion:** Fivetran synchronizing SurveyMonkey survey responses into `FIVETRAN_LANDING`.
> - **Reverse ETL:** Hightouch synchronizing our governed at-risk nurse retention audience to Slack `#first-project`.
>
> Everything on AWS and Snowflake is defined as Infrastructure as Code using modular Terraform in `infra/terraform/`.
> The EC2 host has zero open inbound internet ports—all access is tunneled through AWS Systems Manager."

---

## Part 3: Airflow to S3 Initial & Incremental Batches (Minutes 04:00 - 07:00)

**Speaker Script:**
> "Now let's examine the pipeline execution.
>
> In our initial load, Airflow triggers synthetic data generation for 500 baseline nurses across 6 source families.
> The batch lands in S3 under `s3://carematch-data-237657481511-dev/raw/` accompanied by `manifest.json`.
>
> To demonstrate business activity growth, we trigger an incremental run with 550 nurses.
> Here is our live verified execution:
> - DAG run ID: `manual__inc_550_20260903T085640Z`
> - S3 batch partition: `load_date=2026-09-03/batch_id=manual__inc_550_20260903T085640Z/`
> - Total rows landed: 20,700 across 11 entity files.
> - Exactly 550 rows in `nurses.csv` with verified SHA-256 hash `8cfe4e411abe8de1cb038530de657d2642a5e5dcc41dbb7a85111dcef984768c`.
>
> Notice that S3 is immutable: the new batch does not overwrite the initial files; it lands under its own unique prefix."

---

## Part 4: Snowflake Ingestion & dbt Deduplication (Minutes 07:00 - 10:00)

**Speaker Script:**
> "Next, let's step into Snowflake and dbt.
>
> When Snowflake executes `02_s3_stage_and_raw_load.sql`, `COPY INTO` loads the new files.
> Crucially, `FORCE = TRUE` is strictly forbidden. Snowflake's load history detects that earlier S3 files
> were already ingested, so only the 550 new nurse snapshot rows are loaded into `CAREMATCH.RAW.NURSES`.
>
> Total rows in RAW now equal 1,050 cumulative historical snapshots (500 initial + 550 incremental).
>
> Now, how do we prevent double-counting in analytics?
> In `dbt/models/staging/stg_nurses.sql`, we apply:
> `QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ORDER BY record_updated_at DESC) = 1`.
>
> When `dbt build` executes:
> - `CAREMATCH.STAGING.STG_NURSES` deduplicates by nurse business key and selects only the newest record.
> - `CAREMATCH.ANALYTICS.DIM_NURSES` yields exactly 550 unique active nurses with zero duplicates.
> - If we rerun the S3 ingestion SQL right now, exactly 0 rows are loaded—proving complete idempotency."

---

## Part 5: SaaS Integrations (Fivetran, Hightouch, Slack) (Minutes 10:00 - 12:00)

**Speaker Script:**
> "Next, we integrate external feedback and operationalize our data.
>
> **Fivetran Ingestion:**
> Nurse satisfaction feedback from SurveyMonkey is ingested via connector `prohibited_every` into
> `FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY`. This requires an initial web-based OAuth consent from the account owner.
>
> **Hightouch Reverse ETL:**
> In dbt, we materialize `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES`. This model filters for active nurses
> whose churn risk score exceeds 0.7 and who have not completed a shift in over 14 days, respecting patient privacy
> and notification opt-ins.
>
> Hightouch Sync `8379886` reads this model and delivers real-time tabular alerts to staffing recruiters in Slack
> channel `#first-project` (`C0BSC5B2743`).
>
> *(Note for live demo: The one-time browser steps to complete SurveyMonkey OAuth and verify the Slack channel
> mapping in Hightouch UI are documented in `docs/BROWSER_ACTIONS.md`.)*"

---

## Part 6: Failure Handling, Security & Teardown (Minutes 12:00 - 14:00)

**Speaker Script:**
> "Reliability and cost control are central to our design:
> - **Failure Recovery:** If a batch upload fails or a manifest hash mismatches, our pipeline rolls forward
>   by generating a new unique batch. dbt staging models automatically resolve the newest valid state.
> - **Security:** Zero plaintext credentials are committed to Git. All service accounts use RSA key-pair authentication.
> - **Cost Control:** Snowflake warehouses auto-suspend after 60 seconds of idle time. Our Airflow EC2 instance is
>   stopped immediately after execution, dropping compute costs to zero."

---

## Part 7: Closing Summary & Questions (Minutes 14:00 - 15:00)

**Speaker Script:**
> "To summarize: We have demonstrated a production-grade healthcare staffing data platform:
> - 11 entity datasets generated deterministically across 6 source families.
> - Immutable S3 landing with verified incremental execution of 550 nurses.
> - Idempotent Snowflake loading and robust dbt window-function deduplication.
> - Governed reverse ETL activation into Slack.
> - Complete Infrastructure as Code portability via Terraform.
>
> Thank you, and I welcome any questions!"
