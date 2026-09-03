# CareMatch Modern Data Stack

An end-to-end healthcare staffing data platform inspired by the IntelyCare case-study pattern:

```text
Synthetic operational sources -> Airflow on EC2 -> Amazon S3 -> Snowflake
SaaS sources -> Fivetran -> Snowflake -> dbt -> Hightouch -> Salesforce/Slack
```

The deployed small-scale pipeline covers deterministic synthetic sources, Airflow on EC2, a secure S3 landing zone, Snowflake ingestion, dbt transformation models, and least-privilege service identities for Hightouch and Fivetran.

The account-portable entry point is `infra/terraform/platform`. It composes the
AWS infrastructure with optional Snowflake trust and Fivetran scheduling. Use
`scripts/invoke_case_study_pipeline.ps1` to run explicit `initial`, `incremental`,
or `verify` modes. See [the full automation runbook](docs/FULL_AUTOMATION_RUNBOOK.md).

The full business/technical narrative and demo sequence are documented in [the case study](docs/CASE_STUDY.md). The final three-batch core-pipeline evidence is in [the final verification report](docs/FINAL_VERIFICATION_2026-08-25.md). Hightouch and Fivetran connection settings are recorded in [the SaaS integrations runbook](docs/SAAS_INTEGRATIONS_RUNBOOK.md), with live connection evidence in [the SaaS verification report](docs/SAAS_INTEGRATION_VERIFICATION_2026-08-25.md).

## Milestone 1: generate source data

Requirements: Python 3.11 or newer. No third-party Python packages are required.

```powershell
python -m src.generate_healthcare_data --output data/generated
python -m unittest discover -s tests -v
```

The generator creates S3-ready Hive-style folders under `data/generated` and writes a manifest containing row counts, schemas, SHA-256 checksums, and object keys.

## Milestone 1: provision S3

Configure a named AWS profile securely, then:

```powershell
.\scripts\deploy_s3.ps1 -AwsProfile default -Region us-east-1
```

The script generates data, runs tests, provisions the S3 landing bucket with Terraform, uploads source files, and verifies the remote manifest. It does not accept or write AWS credentials.

See [AWS access setup](docs/AWS_ACCESS_SETUP.md) for the dedicated role/user policy and safe profile configuration.

## Milestone 2: EC2 Airflow to S3

After the S3 stack is applied:

```powershell
.\scripts\deploy_airflow.ps1 -BucketName "YOUR_BUCKET" -Action plan
.\scripts\deploy_airflow.ps1 -BucketName "YOUR_BUCKET" -Action apply
```

See [the EC2 Airflow runbook](docs/EC2_AIRFLOW_RUNBOOK.md) for SSM-only UI access,
pipeline execution, and S3 verification.

## Milestone 3: S3 to Snowflake and dbt

The deployed Snowflake layer contains:

- `CAREMATCH.RAW`: 11 source tables loaded from the S3 external stage.
- `CAREMATCH.STAGING`: five cleaned dbt views.
- `CAREMATCH.ANALYTICS`: nurse, shift, marketing, market, and activation models.
- `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES`: consent-safe Hightouch source model.

Terraform creates the AWS role trusted by Snowflake and restricts it to read-only access under the bucket's `raw/` prefix. Snowflake SQL bootstraps the warehouse, RBAC, storage integration, stage, source tables, and validation queries. The dbt project is under `dbt/`.

See [the Snowflake and dbt runbook](docs/SNOWFLAKE_DBT_RUNBOOK.md) for deployed row counts, rerun order, tests, and secure local dbt configuration.

For a live before-and-after demonstration, run `snowflake/sql/06_incremental_demo.sql`
before and after the S3 load. It uses `COPY_HISTORY` for filename evidence because
`METADATA$FILENAME` is a stage-only pseudo column and cannot be selected from a table.

The live two-batch proof, including zero-row COPY rerun and post-deduplication QA, is recorded in [the incremental verification report](docs/INCREMENTAL_VERIFICATION_2026-08-24.md).

## Repository layout

```text
src/                      synthetic source-data generator
tests/                    integrity and reproducibility tests
data/                     local generated data (ignored by Git)
infra/terraform/s3/       secure S3 landing-zone infrastructure
infra/terraform/ec2-airflow/ EC2, networking, IAM, and Airflow bootstrap
infra/terraform/snowflake-s3-integration/ scoped Snowflake IAM trust and S3 read policy
infra/terraform/platform/ composite, account-portable infrastructure entry point
airflow/                  pinned image, Compose stack, and six-source S3 DAG
snowflake/sql/            idempotent platform, ingestion, transformation, and QA SQL
dbt/                      staging, analytics, activation models, and tests
scripts/                  deployment and upload entry points
docs/                     architecture and data documentation
.github/workflows/        continuous validation
```

## Milestone 4: Hightouch and Fivetran

Generate local RSA keys and apply the idempotent Snowflake integration SQL before configuring the two SaaS applications:

```powershell
.\scripts\generate_service_keys.ps1
```

Then render and run `snowflake/sql/05_service_integrations.sql` with the generated public keys. Private keys must remain under `.secrets/` and are supplied only to the corresponding SaaS connection form. See [the integrations runbook](docs/SAAS_INTEGRATIONS_RUNBOOK.md) for the exact settings and verification queries.

## Security rules

- Never commit AWS credentials, Snowflake private keys, OAuth tokens, `.env` files, or Terraform state.
- Pass Snowflake secrets through the environment or an approved secret manager; never write them into `profiles.yml`.
- Never use the AWS root user for deployment.
- Use a dedicated named AWS profile or an IAM Identity Center/assumable role session.
- Synthetic identities use reserved `.example` email domains and contain no real patient or workforce data.
- The S3 bucket blocks all public access, enforces TLS, enables versioning, and uses server-side encryption.
