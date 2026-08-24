# CareMatch Modern Data Stack

An end-to-end healthcare staffing data platform inspired by the IntelyCare case-study pattern:

```text
Synthetic operational sources -> Airflow on EC2 -> Amazon S3 -> Snowflake
SaaS sources -> Fivetran -> Snowflake -> dbt -> Hightouch -> Salesforce/Slack
```

The current milestone creates deterministic, privacy-safe source data and a small-scale Airflow deployment on EC2 that uploads six source families to the secure Amazon S3 landing zone. Later milestones add Snowflake, Fivetran, dbt, Hightouch, and downstream destinations.

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
.\scripts\deploy_s3.ps1 -AwsProfile carematch-dev -Region us-east-1
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

## Repository layout

```text
src/                      synthetic source-data generator
tests/                    integrity and reproducibility tests
data/                     local generated data (ignored by Git)
infra/terraform/s3/       secure S3 landing-zone infrastructure
infra/terraform/ec2-airflow/ EC2, networking, IAM, and Airflow bootstrap
airflow/                  pinned image, Compose stack, and six-source S3 DAG
scripts/                  deployment and upload entry points
docs/                     architecture and data documentation
.github/workflows/        continuous validation
```

## Security rules

- Never commit AWS credentials, Snowflake private keys, OAuth tokens, `.env` files, or Terraform state.
- Never use the AWS root user for deployment.
- Use a dedicated named AWS profile or an IAM Identity Center/assumable role session.
- Synthetic identities use reserved `.example` email domains and contain no real patient or workforce data.
- The S3 bucket blocks all public access, enforces TLS, enables versioning, and uses server-side encryption.
