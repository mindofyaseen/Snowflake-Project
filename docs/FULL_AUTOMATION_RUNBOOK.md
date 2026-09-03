# Full automation runbook

The platform separates infrastructure provisioning from data movement. This keeps
initial history, incremental changes, and a UI demonstration easy to explain.

## Environment variables

All secrets are passed as environment variables and must never be committed.
Set them in the current PowerShell session before running any mode.

### Snowflake (required for initial, incremental, and verify modes)

```powershell
$env:SNOWFLAKE_ACCOUNT  = "AGBKFYW-JO98858"
$env:SNOWFLAKE_USER     = "CAREMATCH_TRANSFORMER"
$env:SNOWFLAKE_ROLE     = "ACCOUNTADMIN"
# Prefer key-pair authentication:
$env:SNOWFLAKE_PRIVATE_KEY_FILE = ".secrets/snowflake_rsa_key.p8"
# Password is accepted as a fallback if no key file is set:
# $env:SNOWFLAKE_PASSWORD = (Read-Host -MaskInput)
```

### SaaS triggers (only required when -RunFivetran or -RunHightouch is passed)

```powershell
$env:FIVETRAN_APIKEY       = "<key>"
$env:FIVETRAN_APISECRET    = "<secret>"
$env:FIVETRAN_CONNECTOR_ID = "prohibited_every"

$env:HIGHTOUCH_API_KEY = "<key>"
$env:HIGHTOUCH_SYNC_ID = "8379886"
# Note: Destination channel in Hightouch UI must be configured to #first-project (ID: C0BSC5B2743), not stale channel C0BS2TQSS9M.
```

Do not put any of these values in a committed file or Terraform variable file.

## Script flags

| Flag | Default | Description |
|------|---------|-------------|
| `-Mode` | required | `infrastructure`, `initial`, `incremental`, or `verify` |
| `-AwsProfile` | `default` | Named AWS CLI profile |
| `-AwsRegion` | `us-east-1` | AWS region |
| `-Environment` | `dev` | Deployment environment (`dev`, `test`, `prod`) |
| `-LoadDate` | today UTC | Override the batch load date |
| `-InitialNurseCount` | `500` | Nurse count for the initial load |
| `-IncrementalNurseCount` | `550` | Nurse count for the incremental load |
| `-AirflowInstanceId` | Terraform output | Override EC2 instance ID |
| `-S3BucketName` | Terraform output | Override S3 bucket name |
| `-SnowflakeRoleArn` | Terraform output | Override Snowflake S3 IAM role ARN |
| `-ApplyInfrastructure` | off | Apply Terraform (default is plan-only) |
| `-RunFivetran` | off | Trigger and poll the Fivetran connector sync |
| `-RunHightouch` | off | Trigger and poll the Hightouch sync |
| `-SkipDbt` | off | Skip dbt build |
| `-SaasTimeoutSeconds` | `1800` | Maximum seconds to poll SaaS syncs |
| `-SaasPollIntervalSeconds` | `30` | Interval in seconds between SaaS status polls |
| `-DryRun` | off | Validate SQL and orchestrator steps without remote calls |
| `-ExistingBatchId` | none | Ingest an existing S3 batch without re-triggering Airflow (e.g. `manual__inc_550_20260903T085640Z`) |
| `-SkipAirflow` | off | Skip Airflow execution |
| `-SkipSnowflake` | off | Skip Snowflake ingestion and dbt build |
| `-SkipInfrastructure` | off | Skip Terraform platform output checks |

## One-time account authorization

Terraform provisions AWS, the Snowflake IAM trust, and the Fivetran schedule.
An account owner must still complete SurveyMonkey OAuth in Fivetran and Slack
OAuth in Hightouch. OAuth consent cannot safely be stored in Git or Terraform
state.

## Infrastructure

```powershell
# Plan only (safe, no changes):
.\scripts\invoke_case_study_pipeline.ps1 -Mode infrastructure

# Apply (creates or updates S3, EC2 Airflow, IAM, and optional modules):
.\scripts\invoke_case_study_pipeline.ps1 -Mode infrastructure -ApplyInfrastructure
```

## Initial load

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode initial -RunFivetran -RunHightouch
```

Initial mode generates 500 nurses and all related source domains on EC2, lands a
uniquely identified batch in S3, bootstraps Snowflake, loads every new S3 object,
runs dbt models and tests, then optionally triggers Fivetran and Hightouch.

The script polls both APIs until the sync completes or timeout expires, then reports
PASS or FAIL for each.

## Incremental load

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode incremental -IncrementalNurseCount 550 -RunFivetran -RunHightouch
```

Incremental mode generates a later 550-nurse snapshot. S3 uses a new batch path,
Snowflake `COPY INTO` loads only file names absent from copy history, dbt resolves
the latest record for each nurse, Fivetran fetches source changes, and Hightouch
change data capture sends only added, changed, or removed audience records.

When running directly against existing resources without the consolidated platform
state, pass resource identifiers explicitly:

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode incremental `
  -AwsProfile default `
  -AirflowInstanceId i-02bdd56e8690f35d1 `
  -S3BucketName carematch-data-237657481511-dev `
  -IncrementalNurseCount 550
```

## Before and after proof (read-only)

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode verify `
  -S3BucketName carematch-data-237657481511-dev
```

Alternatively, run in dry-run mode without active Snowflake credentials:
```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode verify -DryRun `
  -S3BucketName carematch-data-237657481511-dev
```

For manual interactive verification in Snowsight, see `docs/SNOWFLAKE_DEMO_QUERIES.sql`.
For SaaS browser reauthorization and Slack channel alignment, see `docs/BROWSER_ACTIONS.md`.

The `verify` mode is **read-only**. It executes `snowflake/sql/06_incremental_demo.sql`
which selects from RAW and STAGING/ANALYTICS views. It makes no writes to any
system. When `-S3BucketName` is passed, it requires no Terraform outputs.

## SaaS polling behaviour

When `-RunFivetran` is set, `scripts/saas_sync.py`:
1. Reads the connector status baseline `succeeded_at` and `failed_at`.
2. POSTs to `api.fivetran.com/v1/connectors/:id/force` to trigger a sync.
3. Polls `GET /v1/connectors/:id` checking whether `succeeded_at` has advanced.
4. Exits PASS when `succeeded_at` advances past the pre-trigger baseline.
5. Fails immediately if `failed_at` advances or if `sync_state` is `paused`/`rescheduled`.
6. Handles transient polling errors by warning and retrying until timeout.

When `-RunHightouch` is set, `scripts/saas_sync.py`:
1. POSTs to `api.hightouch.com/api/v1/syncs/:id/trigger` and extracts `id` (sync request ID).
2. Polls `GET /api/v1/syncs/:id/sync_requests` requiring an exact match on that request ID.
3. Exits PASS when `status` is `success`.
4. Fails immediately on `failed`, `cancelled`, or `interrupted`.
5. Rejects missing or non-matching sync request IDs (no silent fallbacks).

## dbt Package Handling

The dbt project requires no external packages (`packages.yml` is not needed).
The pipeline checks for the existence of `dbt/packages.yml` and skips `dbt deps`
gracefully if absent.

## Terraform state migration

See [TERRAFORM_MIGRATION.md](TERRAFORM_MIGRATION.md) for the safe, documented
import procedure to consolidate the separate S3 and EC2 Airflow states into
the composite platform state.