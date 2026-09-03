# CareMatch Data Platform: Failure Handling & Disaster Recovery Runbook

This runbook documents failure modes, diagnosis procedures, resolution steps, and rollback versus roll-forward
guidelines across each layer of the CareMatch healthcare staffing pipeline.

---

## 1. Quick Reference: Failure Classification

| Layer | Failure Scenario | Impact | Action / Recovery Strategy |
|---|---|---|---|
| **Orchestration** | Airflow DAG failure on EC2 | Data generation incomplete | Inspect docker logs via SSM, fix parameter, re-trigger DAG |
| **Compute** | EC2 or Docker daemon crash | Airflow UI and runner offline | Restart EC2/Docker via AWS CLI; pipeline is stateless |
| **Storage** | S3 upload failure | Objects missing from raw prefix | Re-run DAG task; S3 uploads are idempotent by batch ID |
| **Integrity** | Corrupt manifest / checksum mismatch | Downstream ingestion halts | Invalidate batch, re-generate files with matched checksum |
| **Warehouse** | Snowflake COPY INTO failure | Raw tables not updated | Inspect COPY_HISTORY, resolve schema mismatch, re-run COPY |
| **Transform** | dbt build or test failure | Marts not materialized | Fix SQL model or bad data; staging views allow rapid retry |
| **SaaS Ingestion**| Fivetran sync failure | SurveyMonkey data delayed | Reauthorize OAuth in Fivetran web UI, trigger manual sync |
| **Reverse ETL** | Hightouch sync failure | Audience not delivered to Slack | Check sync error; update channel to `#first-project` (`C0BSC5B2743`) |
| **Slack** | `not_in_channel` error | Hightouch cannot post messages | In Slack channel `#first-project`, run `/invite @Hightouch` |
| **Auth** | AWS / Snowflake credential expiry | CLI commands return 401/403 | Refresh temporary session or rotate RSA key pair |

---

## 2. Airflow & EC2 Failures

### A. Airflow DAG Execution Failure
- **Symptom:** Airflow task `generate_files` or `upload_to_s3` reports `failed` state.
- **Root Causes:**
  - `CAREMATCH_S3_BUCKET` environment variable missing in `airflow/.env`.
  - Disk full on EC2 instance host volume.
  - Invalid parameters passed in DAG run configuration (e.g., negative nurse count).
- **Diagnosis via AWS SSM:**
  ```powershell
  aws ssm send-command `
    --instance-ids i-02bdd56e8690f35d1 `
    --document-name AWS-RunShellScript `
    --parameters 'commands=["docker compose -f /opt/carematch/project/airflow/docker-compose.ec2.yaml logs --tail=100 airflow-worker"]'
  ```
- **Recovery Procedure:**
  1. Resolve configuration or disk space constraint.
  2. Clear the failed task instance in Airflow UI or re-trigger the DAG with a new unique run ID:
     ```powershell
     .\scripts\invoke_case_study_pipeline.ps1 -Mode incremental -IncrementalNurseCount 550
     ```

### B. EC2 Instance or Docker Crash
- **Symptom:** SSM commands fail to connect, or port forwarding to Airflow (port 8080) times out.
- **Recovery Procedure:**
  1. Check instance state via AWS CLI:
     ```powershell
     aws ec2 describe-instances --instance-ids i-02bdd56e8690f35d1 --query "Reservations[0].Instances[0].State.Name"
     ```
  2. If instance is stopped, start it:
     ```powershell
     aws ec2 start-instances --instance-ids i-02bdd56e8690f35d1
     aws ec2 wait instance-running --instance-ids i-02bdd56e8690f35d1
     ```
  3. Systemd automatically restarts the Docker compose service (`carematch-airflow.service`). Confirm containers:
     ```powershell
     aws ssm send-command --instance-ids i-02bdd56e8690f35d1 --document-name AWS-RunShellScript --parameters 'commands=["docker ps"]'
     ```

---

## 3. S3 Storage & Manifest Verification Failures

### A. Corrupt Manifest or Checksum Mismatch
- **Symptom:** Automated validation detects a mismatch between an S3 object SHA-256 hash and `manifest.json`.
- **Root Cause:** Incomplete network upload or partial multipart write.
- **Recovery Procedure:**
  1. Never alter the existing immutable S3 batch in place.
  2. Treat the batch as orphaned and trigger a clean subsequent batch run.
  3. S3 object versioning ensures all historical attempts remain auditable.

---

## 4. Snowflake Ingestion & dbt Transformation Failures

### A. Snowflake COPY INTO Failure
- **Symptom:** `scripts/run_snowflake_sql.py` exits with status code 1.
- **Diagnosis:** Query `INFORMATION_SCHEMA.LOAD_HISTORY`:
  ```sql
  SELECT table_name, file_name, error_count, first_error_message
  FROM INFORMATION_SCHEMA.LOAD_HISTORY
  WHERE status = 'LOAD_FAILED'
  ORDER BY last_load_time DESC LIMIT 10;
  ```
- **Recovery Procedure:**
  - If schema evolution occurred, update table DDL in `snowflake/sql/02_s3_stage_and_raw_load.sql`.
  - Re-execute the script. Because `FORCE = TRUE` is strictly omitted, Snowflake will safely skip any already-loaded files and only ingest uncommitted files.

### B. dbt Build or Test Failure
- **Symptom:** `dbt build` fails with model compilation or test assertion errors (e.g. `dbt test` failure on `unique` or `not_null`).
- **Diagnosis:** Inspect `dbt/target/run_results.json` and `dbt/logs/dbt.log`.
- **Recovery Procedure:**
  - Because staging models are views and marts are tables, models can be rebuilt without data loss.
  - Fix the transformation logic in `dbt/models/` and re-run:
    ```powershell
    dbt build --project-dir dbt --profiles-dir dbt
    ```

---

## 5. SaaS Integration Failures (Fivetran & Hightouch)

### A. Fivetran SurveyMonkey Sync Failure & OAuth Expiration
- **Symptom:** `scripts/saas_sync.py fivetran` fails or logs `sync_state: paused` or `rescheduled`.
- **Root Cause:** SurveyMonkey trial token expiration or revoked user credentials.
- **Recovery Procedure:**
  - Follow Section 1 of `docs/BROWSER_ACTIONS.md` to reauthorize OAuth in Fivetran.
  - After re-authorization, trigger sync via `python scripts/saas_sync.py fivetran`.

### B. Hightouch Sync Failure & Slack `not_in_channel` Error
- **Symptom:** Hightouch run fails with 100% rejected operations or Slack API error `not_in_channel`.
- **Root Cause:**
  - Sync `8379886` is pointing to stale channel `C0BS2TQSS9M`.
  - The `@Hightouch` bot was not invited to `#first-project` (`C0BSC5B2743`).
- **Recovery Procedure:**
  1. In Slack channel `#first-project`, type `/invite @Hightouch`.
  2. In Hightouch web UI, navigate to Sync `8379886` -> Configuration -> update Destination Channel to `#first-project` (`C0BSC5B2743`).
  3. Re-trigger the sync.

---

## 6. Rollback vs. Roll-Forward Decisions

### A. When to Roll Forward (Recommended Default)
- **Data corrections:** If an incremental batch lands with inaccurate synthetic data, generate a new batch with corrected parameters and current timestamp. dbt deduplication (`QUALIFY ROW_NUMBER() OVER (PARTITION BY nurse_id ORDER BY record_updated_at DESC) = 1`) automatically promotes the newest record.
- **SQL / dbt logic bugs:** Edit the dbt model SQL and re-execute `dbt build`. Staging views immediately reflect the new logic.

### B. When to Roll Back
- **Corrupt database migration:** If a DDL change breaks dependent marts, execute `snowflake/sql/01_platform_bootstrap.sql` to re-establish the clean baseline schema.
- **Infrastructure regression:** If Terraform changes introduce network isolation, revert the git commit and run `terraform apply` to restore working VPC routing.
