# Account-portable deployment

The project is split into repeatable infrastructure and account-owned authorization.
Changing AWS, Snowflake, or Fivetran accounts does not require changing pipeline code.

## Repeatable layers

| Layer | Automation |
| --- | --- |
| S3 landing zone | `infra/terraform/s3` |
| EC2 Airflow server and IAM | `infra/terraform/ec2-airflow` |
| Snowflake access to S3 | `infra/terraform/snowflake-s3-integration` |
| Snowflake databases, roles, and tables | `snowflake/sql/01_platform_bootstrap.sql` through `05_service_integrations.sql` |
| Fivetran schedule and trial guardrail | `infra/terraform/fivetran-schedule` |
| dbt models and tests | `dbt/` |

## Values that change per account

- AWS CLI profile, region, and account-derived bucket name
- Snowflake organization, account, user, role, and generated RSA public keys
- Fivetran API key, API secret, destination group ID, and connector ID
- SurveyMonkey OAuth authorization
- Hightouch and Slack OAuth authorization

Passwords, OAuth tokens, API secrets, and private keys must stay in environment
variables, an approved secret manager, or ignored `.secrets` files. They must never
be committed to Git or placed in Terraform variable files.

## Fivetran account change

1. Bootstrap the new Snowflake account with the SQL scripts.
2. Generate a new Fivetran key pair and configure the Snowflake destination.
3. Create a SurveyMonkey connector and authorize the desired source account.
4. Copy its connector ID.
5. Export `FIVETRAN_APIKEY` and `FIVETRAN_APISECRET` for the new account.
6. Run:

   ```powershell
   .\scripts\configure_fivetran_schedule.ps1 -ConnectorId "new-connector-id"
   ```

The schedule module enables six-hour syncs and sets `pause_after_trial = true` by
default. OAuth still requires one browser authorization because Terraform must not
store a reusable SurveyMonkey access token.

## Current verified Fivetran deployment

- Connector ID: `prohibited_every`
- Source: SurveyMonkey
- Destination: `FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY`
- Initial historical sync: successful on 31 August 2026
- Verified objects: 10 tables and 51 rows
- Incremental schedule: six hours in the Fivetran connection

The Terraform files are portable, but the live connector is not yet imported into
Terraform state. Export a Fivetran API key and secret, then run the configuration
script. This separation prevents credentials and OAuth tokens from entering Git.
