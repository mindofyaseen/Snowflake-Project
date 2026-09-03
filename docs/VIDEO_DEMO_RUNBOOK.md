# CareMatch pipeline video demo

This runbook records a clean initial and incremental demonstration without screenshots.

## Current live identifiers

- AWS profile: `default`
- AWS region: `us-east-1`
- Airflow EC2 instance: `i-02bdd56e8690f35d1`
- S3 bucket: `carematch-data-237657481511-dev`
- Hightouch sync: `8379886`
- Hightouch Slack channel: `C0BS2TQSS9M`
- Fivetran source: SurveyMonkey
- Fivetran Snowflake schema: `FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY`

## Before recording

1. Start the EC2 instance if it is stopped.
2. Open the Airflow UI through the SSM port forwarding command in the EC2 Terraform output.
3. Sign in to Snowflake, Fivetran, Hightouch, Slack, and SurveyMonkey.
4. In Slack, invite the Hightouch app to channel `C0BS2TQSS9M`.
5. Confirm the Hightouch destination health check passes.

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
3. Snowflake raw tables contain the initial snapshots.
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

Then show:

1. Airflow creates a later batch with a unique run identifier.
2. Snowflake `COPY INTO` loads only unseen S3 file names.
3. Raw history grows while dbt deduplication selects the latest record.
4. The current nurse result changes from 500 to 550.
5. dbt tests pass.

## Fivetran segment

1. Submit one new response to the SurveyMonkey collector.
2. Open the Fivetran SurveyMonkey connector.
3. Click `Sync now` in the UI.
4. Wait for the sync to succeed.
5. In Snowflake, show the increased `RESPONSE_HISTORY` and `RESPONSE_ANSWER` counts.

## Hightouch segment

1. Open Hightouch sync `8379886`.
2. Run the sync after the Hightouch app is a Slack channel member.
3. Confirm the run has zero rejected operations.
4. Open Slack channel `C0BS2TQSS9M` and show the delivered at risk nurse table.

## Verification command

```powershell
.\scripts\invoke_case_study_pipeline.ps1 `
  -Mode verify `
  -AwsProfile default `
  -S3BucketName carematch-data-237657481511-dev
```

The final video should explain that AWS and Snowflake infrastructure is reproducible with Terraform, while OAuth consent for SurveyMonkey, Fivetran, Hightouch, and Slack remains a one time account owner action.
