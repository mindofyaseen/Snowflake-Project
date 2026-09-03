# Full automation runbook

The platform separates infrastructure provisioning from data movement. This keeps
initial history, incremental changes, and a UI demonstration easy to explain.

## Environment variables

All secrets are passed as environment variables and must never be committed.
Set them in the current PowerShell session before running any mode.

### Snowflake (required for initial, incremental, and verify modes)

```powershell
$env:SNOWFLAKE_ACCOUNT  = "organization-account"
$env:SNOWFLAKE_USER     = "deployment-user"
$env:SNOWFLAKE_ROLE     = "ACCOUNTADMIN"
# Prefer key-pair authentication:
$env:SNOWFLAKE_PRIVATE_KEY_FILE = "C:\secure\snowflake_key.p8"
# Password is accepted as a fallback if no key file is set:
# $env:SNOWFLAKE_PASSWORD = (Read-Host -MaskInput)
```

### SaaS triggers (only required when -RunFivetran or -RunHightouch is passed)

```powershell
$env:FIVETRAN_APIKEY       = "<key>"
$env:FIVETRAN_APISECRET    = "<secret>"
$env:FIVETRAN_CONNECTOR_ID = "<connector-id>"

$env:HIGHTOUCH_API_KEY = "<key>"
$env:HIGHTOUCH_SYNC_ID = "<sync-id>"
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
| `-ApplyInfrastructure` | off | Apply Terraform (default is plan-only) |
| `-RunFivetran` | off | Trigger and poll the Fivetran connector sync |
| `-RunHightouch` | off | Trigger and poll the Hightouch sync |
| `-SkipDbt` | off | Skip dbt deps and build |

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

The script polls both APIs until the sync completes or a 30-minute timeout
expires, then reports PASS or FAIL for each.

## Incremental load

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode incremental -IncrementalNurseCount 550 -RunFivetran -RunHightouch
```

Incremental mode generates a later 550-nurse snapshot. S3 uses a new batch path,
Snowflake `COPY INTO` loads only file names absent from copy history, dbt resolves
the latest record for each nurse, Fivetran fetches source changes, and Hightouch
change data capture sends only added, changed, or removed audience records.

When the combined Terraform state has not yet been migrated, pass the existing
resource identifiers explicitly so the data run does not try to discover them
from the new composite state:

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

The `verify` mode is **read-only**. It executes `snowflake/sql/06_incremental_demo.sql`
which selects from RAW and STAGING/ANALYTICS views. It makes no writes to any
system. The expected demonstration shows 500 current nurses before the incremental
run and 550 after it, while raw snapshot row counts continue to grow.

## SaaS polling behaviour

When `-RunFivetran` is set, the script:
1. POSTs to `api.fivetran.com/v1/connectors/:id/force` to trigger a sync.
2. Polls `GET /v1/connectors/:id` every 30 seconds checking `status.sync_state`.
3. Exits PASS when `sync_state` reaches `connected`.
4. Throws FAIL on `broken`, `incomplete`, or `paused` states, or after 30 minutes.

When `-RunHightouch` is set, the script:
1. POSTs to `api.hightouch.com/api/v1/syncs/:id/trigger`.
2. Polls `GET /api/v1/syncs/:id/sync_requests` every 30 seconds for the triggered request.
3. Exits PASS when `status` is `success`.
4. Throws FAIL on `failed`, `interrupted`, or `cancelled`, or after 30 minutes.

Neither SaaS flow blocks a data demo if the flags are omitted.

## Terraform state migration

See [TERRAFORM_MIGRATION.md](TERRAFORM_MIGRATION.md) for the safe `terraform import`
procedure to consolidate the separate S3 and EC2 Airflow states into the composite
platform state.
