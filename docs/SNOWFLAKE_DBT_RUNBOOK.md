# Snowflake and dbt runbook

## Deployed development environment

As of 2026-08-24, the development pipeline is deployed and verified in AWS account `237657481511` and Snowflake account `AGBKFYW-JO98858`.

| Layer | Resource | Verified state |
| --- | --- | --- |
| AWS | `carematch-data-237657481511-dev/raw/` | 11 source objects |
| AWS | `carematch-dev-snowflake-s3` | Terraform-managed, read-only `raw/` access |
| Snowflake | `CAREMATCH_INGEST_WH` | X-Small, 60-second auto-suspend |
| Snowflake | `CAREMATCH.RAW` | 11 tables, 20,082 rows |
| Snowflake | `CAREMATCH.STAGING` | 5 transformation views |
| Snowflake | `CAREMATCH.ANALYTICS` | 5 analytics/activation tables |

Raw row counts:

| Table | Rows |
| --- | ---: |
| APPLICATIONS | 10,615 |
| APP_EVENTS | 2,920 |
| ASSIGNMENTS | 1,978 |
| CAMPAIGN_PERFORMANCE | 4 |
| FACILITIES | 40 |
| HEALTH_SCREENINGS | 500 |
| MANUAL_OVERRIDES | 10 |
| MARKET_CONDITIONS | 15 |
| NURSE_SCORES | 500 |
| NURSES | 500 |
| SHIFTS | 3,000 |

Analytics row counts:

| Model | Rows |
| --- | ---: |
| AUDIENCE_AT_RISK_NURSES | 296 |
| DIM_NURSES | 500 |
| FCT_SHIFT_PERFORMANCE | 3,000 |
| MART_MARKETING_EFFICIENCY | 4 |
| MART_MARKET_SUPPLY_DEMAND | 15 |

All seven deployed uniqueness, relationship, and activation-policy checks returned zero failing rows.

## Deployment order

1. Run `snowflake/sql/01_platform_bootstrap.sql` as `ACCOUNTADMIN`.
2. Copy the Snowflake IAM user ARN and external ID returned by `DESC INTEGRATION CAREMATCH_S3_INT` into temporary `TF_VAR_...` environment variables.
3. From `infra/terraform/snowflake-s3-integration`, run `terraform init`, `terraform plan`, and `terraform apply`.
4. Run `snowflake/sql/02_s3_stage_and_raw_load.sql`.
5. Run dbt, or use `snowflake/sql/03_transform_models.sql` for an immediate SQL deployment of the same relations.
6. Run `snowflake/sql/04_data_quality_tests.sql` and require every `failing_rows` value to equal zero.

The COPY statements are idempotent because Snowflake records previously loaded files. Do not add `FORCE = TRUE` to a routine rerun.

## Local dbt execution

Copy the example profile outside version control, rotate any password previously exposed in chat or logs, and set the rotated value only for the current shell session:

```powershell
Copy-Item .\dbt\profiles.yml.example .\dbt\profiles.yml
$env:SNOWFLAKE_PASSWORD = Read-Host -MaskInput
dbt deps --project-dir .\dbt --profiles-dir .\dbt
dbt build --project-dir .\dbt --profiles-dir .\dbt
Remove-Item Env:\SNOWFLAKE_PASSWORD
```

Never put the plaintext password in a command, source file, committed profile, or Terraform variable.

The production-preferred connection is Snowflake key-pair or workload-identity authentication with the `CAREMATCH_TRANSFORMER` role. Provision that credential only through an approved secret-management workflow.

## Hightouch handoff

Use `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` as the first Hightouch model. `NURSE_ID` is the stable primary key. The deployed model excludes opted-out nurses, active manual overrides, missing emails, and nurses not cleared to work.
