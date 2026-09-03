# CareMatch Technical Interview & Architectural Defense Questions

This document provides concise, technically rigorous answers to key architectural, design, and operational
questions for the CareMatch healthcare staffing data platform.

---

### 1. Why not Databricks?
**Answer:**  
CareMatch is primarily an analytical and operational reporting pipeline with SQL-centric transformations. Snowflake provides instant, auto-suspending virtual warehouses with zero cluster management overhead, native VARIANT dot-notation querying for semi-structured JSON clickstream data, and native COPY_HISTORY file-level idempotency. Databricks requires cluster provisioning and warm-up latency that introduces unnecessary management overhead for a scheduled batch architecture.

### 2. Why not MWAA (Managed Workflows for Apache Airflow)?
**Answer:**  
AWS MWAA incurs a static minimum cost of ~$350/month (~$0.49/hour) even when the environment is completely idle. By running Airflow 2.8 in Docker Compose on a single EC2 `t3.large` instance ($0.0832/hour), we can stop the instance when not in use, reducing compute costs to $0.00 while maintaining 100% reproducible deployment via Terraform.

### 3. Why use both Airflow and Fivetran?
**Answer:**  
They solve distinct operational problems:
- **Airflow** is a workflow orchestrator for custom business logic: generating multi-source synthetic healthcare domains, staging files to S3, enforcing cryptographic manifest validation, and coordinating pipeline execution order.
- **Fivetran** is a managed ELT pipeline for third-party SaaS APIs (SurveyMonkey): it handles OAuth authentication, upstream schema drift, rate limiting, and API pagination without engineering code maintenance.

### 4. Why use Hightouch for Reverse ETL?
**Answer:**  
Traditional ETL moves data into the warehouse, leaving it isolated from operational business tools. Hightouch completes the loop by turning Snowflake into the single source of truth and syncing governed audiences (`CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES`) directly into operational systems (Slack). It provides native change data capture (CDC), preventing duplicate spam alerts.

### 5. How is incremental loading implemented?
**Answer:**  
Incremental loading occurs at three stages:
1. **S3 Landing:** Airflow partitions new batches under immutable prefixes: `source=<family>/entity=<name>/load_date=<date>/batch_id=<id>/`.
2. **Snowflake COPY INTO:** Snowflake checks its internal 64-day `COPY_HISTORY`. Only newly arrived S3 object URIs are ingested; existing files are skipped.
3. **dbt Materialization:** Downstream models filter on incremental watermarks or rebuild views over raw snapshot history.

### 6. How is idempotency guaranteed?
**Answer:**  
Idempotency is enforced by strictly omitting `FORCE = TRUE` in `snowflake/sql/02_s3_stage_and_raw_load.sql`. If an operator reruns the ingestion script against the same S3 bucket, Snowflake inspects the load history and loads exactly 0 rows. In dbt, staging views use deterministic window functions that yield identical active record sets regardless of how many times models are compiled.

### 7. How are duplicates removed?
**Answer:**  
Deduplication is performed in dbt staging models using the window function:
```sql
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY nurse_id
  ORDER BY record_updated_at DESC
) = 1
```
This partitions all historical snapshots for each nurse by their business key (`nurse_id`), orders by the update timestamp descending, and filters for rank 1, selecting only the latest state.

### 8. Why do RAW tables contain repeated business records?
**Answer:**  
The RAW schema serves as an append-only historical snapshot audit log. Storing every version of a nurse's profile allows point-in-time auditing, retroactive churn analysis, and state change tracking. Deduplication is deliberately decoupled from raw ingestion and handled in the modeling layer.

### 9. How does dbt choose the latest record?
**Answer:**  
Through the `ORDER BY record_updated_at DESC` clause within the `QUALIFY ROW_NUMBER()` window function. If two records share the exact same timestamp, tie-breaking is enforced by sorting on secondary surrogate IDs or file load timestamps.

### 10. How would the system scale to 100,000+ nurses?
**Answer:**  
- **Storage:** Amazon S3 scales infinitely with multipart concurrent uploads and partitioned prefixes.
- **Warehouse:** Snowflake compute scales horizontally by resizing warehouses from `X-Small` to `Medium`/`Large` in seconds or enabling multi-cluster warehouse auto-scaling.
- **Transformations:** Convert dbt staging models from views to dbt incremental tables using `is_incremental()` macros.

### 11. How are costs controlled?
**Answer:**  
- EC2 instance `i-02bdd56e8690f35d1` is stopped when not in use.
- Snowflake warehouses are configured with `AUTO_SUSPEND = 60` seconds and `STATEMENT_TIMEOUT_IN_SECONDS = 3600`.
- S3 objects use standard tier with lifecycle rules to transition old batches to Infrequent Access or Glacier.

### 12. How are secrets managed?
**Answer:**  
- Zero plaintext credentials or passwords are committed to Git.
- Local secrets (e.g. RSA private keys) reside in `.secrets/`, which is ignored by Git.
- Environment variables are injected at runtime in shell sessions.
- In production, secrets are managed via AWS Secrets Manager or HashiCorp Vault.

### 13. How is sensitive healthcare data protected?
**Answer:**  
- The platform uses deterministic synthetic healthcare data with reserved `.example` email domains to ensure zero real patient or staff exposure.
- All S3 data is encrypted at rest with AES-256 and in transit via TLS 1.2+.
- S3 bucket blocks all public access (`block_public_acls = true`, `block_public_policy = true`).
- EC2 operates in a private subnet with no public IP and no open inbound ports, accessible solely via IAM-authenticated AWS Systems Manager.

### 14. What happens when a downstream sync fails?
**Answer:**  
- The upstream warehouse and raw landing data remain unaffected and durable.
- In Hightouch, sync runs log specific failure details (e.g., `not_in_channel`). Because Hightouch maintains CDC state, once the destination channel is fixed and bot invited, the sync retries and delivers only the pending audience delta.

### 15. How would we migrate after trial accounts expire?
**Answer:**  
The entire platform is defined as Infrastructure as Code. In `docs/TERRAFORM_MIGRATION.md`, we provide the complete guide: update `aws_profile` and `snowflake_account` variables in Terraform, run `terraform apply`, execute `01_platform_bootstrap.sql`, and re-link SaaS connectors in under 30 minutes.

### 16. What is currently simulated versus genuinely integrated?
**Answer:**  
- **Genuinely Integrated & Verified:**
  - AWS EC2 instance running Airflow in Docker Compose.
  - AWS S3 bucket receiving live partitioned entity files and manifests.
  - Live Airflow incremental DAG run `manual__inc_550_20260903T085640Z` landing 550 nurses.
  - Complete Snowflake SQL scripts and dbt models validated locally via credential-free dbt parse.
- **SaaS Pending Browser Handoff:**
  - SurveyMonkey OAuth token in Fivetran requires account owner web consent.
  - Hightouch sync `8379886` requires updating the destination channel to `#first-project` (`C0BSC5B2743`) in the Hightouch UI and running `/invite @Hightouch` in Slack.
- **Intentionally Excluded:**
  - Marketo, Pendo, Adobe, Google Ads, and Facebook Ads are outside the core pipeline scope.
