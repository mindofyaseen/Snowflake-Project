# CareMatch Data Platform: Daily Operations & Demo Runbook

This operations runbook provides standardized CLI procedures for operating, inspecting, demonstrating,
and cost-controlling the CareMatch healthcare staffing pipeline.

---

## 1. Starting & Stopping the EC2 Airflow Host

To prevent unnecessary AWS charges, keep the EC2 instance stopped when not actively executing DAG runs:

```powershell
# Check current instance status
aws ec2 describe-instances `
  --profile default --region us-east-1 `
  --instance-ids i-02bdd56e8690f35d1 `
  --query "Reservations[0].Instances[0].State.Name" --output text

# Start the instance
aws ec2 start-instances --profile default --region us-east-1 --instance-ids i-02bdd56e8690f35d1
aws ec2 wait instance-running --profile default --region us-east-1 --instance-ids i-02bdd56e8690f35d1

# Stop the instance after testing/demo
aws ec2 stop-instances --profile default --region us-east-1 --instance-ids i-02bdd56e8690f35d1
aws ec2 wait instance-stopped --profile default --region us-east-1 --instance-ids i-02bdd56e8690f35d1
```

---

## 2. Checking AWS Systems Manager (SSM) & Airflow Containers

The EC2 instance is completely private (no public IP and no open inbound ports). All management occurs via AWS SSM:

```powershell
# Verify SSM agent is online
aws ssm describe-instance-information `
  --profile default --region us-east-1 `
  --filters "Key=InstanceIds,Values=i-02bdd56e8690f35d1" `
  --query "InstanceInformationList[0].PingStatus" --output text

# Check running Docker containers on EC2
aws ssm send-command `
  --profile default --region us-east-1 `
  --instance-ids i-02bdd56e8690f35d1 `
  --document-name AWS-RunShellScript `
  --parameters 'commands=["docker compose -f /opt/carematch/project/airflow/docker-compose.ec2.yaml ps"]'
```

---

## 3. Securely Accessing the Airflow Web UI

Access the Airflow web interface through an encrypted SSM port forwarding tunnel:

```powershell
aws ssm start-session `
  --profile default --region us-east-1 `
  --target i-02bdd56e8690f35d1 `
  --document-name AWS-StartPortForwardingSession `
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

Then open your browser to `http://localhost:8080`.

---

## 4. Triggering Initial & Incremental DAG Runs

### A. Initial Load (500 Nurses)
```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode initial `
  -InitialNurseCount 500 `
  -AwsProfile default `
  -AirflowInstanceId i-02bdd56e8690f35d1 `
  -S3BucketName carematch-data-237657481511-dev
```

### B. Incremental Load (550 Nurses)
```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode incremental `
  -IncrementalNurseCount 550 `
  -AwsProfile default `
  -AirflowInstanceId i-02bdd56e8690f35d1 `
  -S3BucketName carematch-data-237657481511-dev
```

---

## 5. Processing an Existing S3 Batch (Without Rerunning Airflow)

If an S3 batch has already been landed (such as verified batch `manual__inc_550_20260903T085640Z`), skip the Airflow generation and trigger only the downstream Snowflake and dbt stages:

```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode incremental `
  -ExistingBatchId "manual__inc_550_20260903T085640Z" `
  -S3BucketName carematch-data-237657481511-dev
```

---

## 6. Inspecting S3 Manifests & Batch Partitions

```powershell
# List all landing manifests
aws s3 ls s3://carematch-data-237657481511-dev/manifests/ --recursive --profile default

# View the verified incremental batch manifest
aws s3 cp s3://carematch-data-237657481511-dev/manifests/load_date=2026-09-03/batch_id=manual__inc_550_20260903T085640Z/manifest.json - `
  --profile default
```

---

## 7. Running Snowflake Ingestion & dbt Transformations Later

When warehouse credentials become available:

```powershell
# 1. Export Snowflake connection parameters
$env:SNOWFLAKE_ACCOUNT = "AGBKFYW-JO98858"
$env:SNOWFLAKE_USER = "CAREMATCH_TRANSFORMER"
$env:SNOWFLAKE_PRIVATE_KEY_FILE = ".secrets/snowflake_rsa_key.p8"

# 2. Run idempotent COPY INTO load
python scripts/run_snowflake_sql.py `
  --bucket carematch-data-237657481511-dev `
  snowflake/sql/02_s3_stage_and_raw_load.sql

# 3. Build dbt models and execute dbt tests
dbt deps --project-dir dbt --profiles-dir dbt
dbt build --project-dir dbt --profiles-dir dbt
```

---

## 8. Verifying Counts & Deduplication in Snowsight

Execute the read-only queries in `docs/SNOWFLAKE_DEMO_QUERIES.sql` using role `ACCOUNTADMIN`:
- Confirm total raw nurse snapshots = 1,050 (500 initial + 550 incremental).
- Confirm active deduplicated nurses in `CAREMATCH.ANALYTICS.DIM_NURSES` = 550.
- Confirm zero duplicates via `GROUP BY nurse_id HAVING COUNT(*) > 1`.
- Confirm `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` yields ~280-310 at-risk nurses destined for Slack `#first-project` (`C0BSC5B2743`).

---

## 9. Post-Demo Teardown & Cost Control Checklist

1. Close the SSM port forwarding terminal session.
2. Stop the EC2 instance immediately:
   ```powershell
   aws ec2 stop-instances --profile default --region us-east-1 --instance-ids i-02bdd56e8690f35d1
   ```
3. Confirm status is `stopped`. S3 data remains durable at rest for future demonstrations.
