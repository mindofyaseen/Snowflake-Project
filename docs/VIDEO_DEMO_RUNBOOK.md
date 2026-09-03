# CareMatch pipeline video demo

This runbook records a clean initial and incremental demonstration without screenshots.

## Current live identifiers

- AWS profile: `default`
- AWS region: `us-east-1`
- Airflow EC2 instance: `i-02bdd56e8690f35d1`
- S3 bucket: `carematch-data-237657481511-dev`
- Hightouch sync: `8379886`
- Intended Hightouch Slack channel: `#first-project` (ID: `C0BSC5B2743`)
  *(Note: Sync 8379886 historically referenced stale channel `C0BS2TQSS9M`. The destination must be set to `C0BSC5B2743` in the Hightouch UI prior to running.)*
- Fivetran source: SurveyMonkey
- Fivetran Snowflake schema: `FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY`
- Verified Incremental DAG Run: `manual__inc_550_20260903T085640Z`
- Verified S3 Manifest: `s3://carematch-data-237657481511-dev/manifests/load_date=2026-09-03/batch_id=manual__inc_550_20260903T085640Z/manifest.json`

## Before recording

1. Start the EC2 instance if it is stopped:
   `aws ec2 start-instances --instance-ids i-02bdd56e8690f35d1`
2. Open the Airflow UI through the SSM port forwarding command in the EC2 Terraform output.
3. Sign in to Snowflake, Fivetran, Hightouch, Slack, and SurveyMonkey.
4. In Slack channel `#first-project` (`C0BSC5B2743`), invite the Hightouch bot: `/invite @Hightouch`.
5. In Hightouch UI, confirm sync `8379886` points to channel `#first-project` (`C0BSC5B2743`) and destination health check passes.

## Initial load segment

Run from the repository root:

```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode initial `
  -AwsProfile default `
  -AirflowInstanceId i-02bdd56e8690f35d1 `
  -S3BucketName carematch-data-237657481511-dev
```

Show these stages in the video:

1. Airflow DAG `carematch_synthetic_sources_to_s3` succeeds.
2. S3 contains a new unique batch path under `raw`.
3. Snowflake raw tables contain the initial snapshots (500 nurses).
4. `dbt build` creates and tests the staging and analytics models.
5. The current nurse result contains 500 unique nurses.

## Incremental load segment

Run:

```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode incremental `
  -IncrementalNurseCount 550 `
  -AwsProfile default `
  -AirflowInstanceId i-02bdd56e8690f35d1 `
  -S3BucketName carematch-data-237657481511-dev
```

*(Verified execution reference: DAG run `manual__inc_550_20260903T085640Z`, generating 550 nurse records and 20,700 total raw rows).*

Then show:

1. Airflow creates a later batch with a unique run identifier.
2. Snowflake `COPY INTO` loads only unseen S3 file names.
3. Raw history grows (1,050 cumulative rows) while dbt deduplication selects the latest record.
4. The current nurse result changes from 500 to 550.
5. dbt tests pass.

## Fivetran segment

1. Submit one new response to the SurveyMonkey collector.
2. Open the Fivetran SurveyMonkey connector `prohibited_every`.
3. Click `Sync now` in the UI (or trigger via `python scripts/saas_sync.py fivetran`).
4. Wait for the sync to succeed (verified by timestamp advancement).
5. In Snowflake, show the increased `RESPONSE_HISTORY` and `RESPONSE_ANSWER` counts.

## Hightouch segment

1. Open Hightouch sync `8379886`.
2. Verify destination channel is `#first-project` (`C0BSC5B2743`).
3. Run the sync after the Hightouch app is a channel member.
4. Confirm the run has zero rejected operations.
5. Open Slack channel `#first-project` and show the delivered at-risk nurse table.

## Verification command

```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode verify `
  -AwsProfile default `
  -S3BucketName carematch-data-237657481511-dev
```

## After recording

Stop the EC2 instance to prevent compute charges:
```powershell
aws ec2 stop-instances --instance-ids i-02bdd56e8690f35d1
```

The final video explains that AWS and Snowflake infrastructure is reproducible with Terraform, while OAuth consent for SurveyMonkey, Fivetran, Hightouch, and Slack remains a one-time account owner action.
