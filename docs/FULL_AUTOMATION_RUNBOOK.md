# Full automation runbook

The platform separates infrastructure provisioning from data movement. This keeps
initial history, incremental changes, and a UI demonstration easy to explain.

## One-time account authorization

Terraform provisions AWS, the Snowflake IAM trust, and the Fivetran schedule. An
account owner must still complete SurveyMonkey OAuth in Fivetran and Slack OAuth in
Hightouch. OAuth consent cannot safely be stored in Git or Terraform state.

Set Snowflake authentication in the current PowerShell process:

```powershell
$env:SNOWFLAKE_ACCOUNT = "organization-account"
$env:SNOWFLAKE_USER = "deployment-user"
$env:SNOWFLAKE_ROLE = "ACCOUNTADMIN"
$env:SNOWFLAKE_PRIVATE_KEY_FILE = "C:\secure\snowflake_key.p8"
```

For SaaS triggers, set `FIVETRAN_APIKEY`, `FIVETRAN_APISECRET`,
`FIVETRAN_CONNECTOR_ID`, `HIGHTOUCH_API_KEY`, and `HIGHTOUCH_SYNC_ID`. Do not put
these values in a committed file.

## Infrastructure

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode infrastructure
.\scripts\invoke_case_study_pipeline.ps1 -Mode infrastructure -ApplyInfrastructure
```

The first command plans. The second creates or updates S3, EC2 Airflow, IAM, and
the optional Snowflake and Fivetran modules enabled in `terraform.tfvars`.

## Initial load

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode initial -RunFivetran -RunHightouch
```

Initial mode generates 500 nurses and all related source domains on EC2, lands a
uniquely identified batch in S3, bootstraps Snowflake, loads every new S3 object,
runs dbt models and tests, then optionally triggers Fivetran and Hightouch.

## Incremental load

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode incremental -IncrementalNurseCount 550 -RunFivetran -RunHightouch
```

Incremental mode generates a later 550-nurse snapshot. S3 uses a new batch path,
Snowflake `COPY INTO` loads only file names absent from copy history, dbt resolves
the latest record for each nurse, Fivetran fetches source changes, and Hightouch
change data capture sends only added, changed, or removed audience records.

## Before and after proof

```powershell
.\scripts\invoke_case_study_pipeline.ps1 -Mode verify
```

The verification queries show raw snapshots, unique nurses, source dates,
Snowflake copy history, deduplicated dbt results, and the Hightouch audience count.
The expected nurse demonstration is 500 current nurses before the incremental run
and 550 after it, while raw snapshot rows continue to grow.

