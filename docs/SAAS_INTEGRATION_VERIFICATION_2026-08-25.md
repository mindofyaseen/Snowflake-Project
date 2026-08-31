# SaaS integration verification — 2026-08-25

## Selected flows

```text
CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES -> Hightouch -> Slack
SurveyMonkey -> Fivetran -> FIVETRAN_LANDING
```

OneDrive is retained as an optional secondary file-export destination and is not required for the primary live demonstration.

## Snowflake service identities

The idempotent provisioning SQL created and verified two RSA-authenticated service users:

- `HIGHTOUCH_USER` with `HIGHTOUCH_ROLE`
- `FIVETRAN_USER` with `FIVETRAN_ROLE`

Both users were returned by the Snowflake verification query with their dedicated roles and warehouses.

## Fivetran destination result

The Fivetran destination named `Warehouse` is connected to:

- Host: `AGBKFYW-JO98858.snowflakecomputing.com`
- Database: `FIVETRAN_LANDING`
- User: `FIVETRAN_USER`
- Role: `FIVETRAN_ROLE`
- Authentication: RSA key pair
- Default warehouse: `FIVETRAN_WAREHOUSE`
- Connection: direct, internal staging, AWS `us-east-1`

Fivetran reported **All connection tests passed** for:

1. Host Connection
2. Validate Passphrase
3. Default Warehouse Test
4. Database Connection
5. Validate Internal Stage Access Test
6. Permission Test

## SurveyMonkey connector

SurveyMonkey OAuth authorization succeeded and the connector is configured with destination schema `survey_monkey_case_study`.

The demonstration survey `CareMatch Healthcare Staffing Experience 2026` contains three questions, 15 answer choices, and one synthetic response. Its public collector is:

`https://www.surveymonkey.com/r/QHFR7TD`

Fivetran connector `prohibited_every` completed its first historical sync on 31 August 2026. The run took 31 seconds and loaded 51 rows into Snowflake. A direct RSA-authenticated Snowflake query confirmed these exact counts:

| Snowflake table | Rows |
|---|---:|
| `COLLECTOR` | 1 |
| `QUESTION_HEADING_HISTORY` | 3 |
| `QUESTION_HISTORY` | 3 |
| `QUESTION_OPTION_HISTORY` | 15 |
| `RESPONSE_ANSWER` | 3 |
| `RESPONSE_HISTORY` | 1 |
| `RESPONSE_PAGE` | 1 |
| `SURVEY_CATEGORY` | 22 |
| `SURVEY_HISTORY` | 1 |
| `SURVEY_PAGE_HISTORY` | 1 |
| **Total** | **51** |

The connector is active and scheduled for incremental syncs. Fivetran will use its source cursors and history tables to fetch later SurveyMonkey changes without repeating a full historical reload.

## Marketo connector

A Marketo connector draft was created with destination schema `marketo`. Final testing and initial sync require credentials from a Marketo Admin account:

- REST API Endpoint
- REST API Identity
- Client ID
- Client Secret

The connector is configured to use `FIVETRAN_WAREHOUSE` and defaults to full historical sync. Incremental sync is managed by Fivetran after the initial load.

## Additional Fivetran connector drafts

The Fivetran `Connections` page now contains four Snowflake-bound application connector drafts, all targeting the connected `Warehouse` destination:

| Connection | Destination schema | Current state | Required next action |
|---|---|---|---|
| `marketo` | `marketo` | Incomplete | Supply Marketo Admin REST endpoint, identity URL, client ID, and client secret, then Save & Test |
| `pendo` | `pendo` | Incomplete | Supply a Pendo integration key (or enable/configure Pendo Data Sync), verify it, then Save & Test |
| `salesforce` | `salesforce` | Incomplete | Complete Salesforce OAuth authorization, then Save & Test |
| `survey_monkey` | `survey_monkey` | Incomplete | Authorize Fivetran to read owned/shared surveys; an active SurveyMonkey subscription is required |

`fivetran_metadata` is present but paused. The separate `survey_monkey_case_study` connector is active and its initial sync has completed successfully. Marketo, Pendo, and Salesforce remain connector drafts until their account authorization requirements are satisfied.

## Hightouch source result

The Hightouch source `CareMatch Snowflake` is connected through RSA key-pair authentication. Hightouch reported **All tests passed** for:

1. Validate Snowflake credentials
2. Verify permission to list schemas and tables
3. Verify permission to write to the planner schema
4. Verify permission to write to the audit schema

The private key was uploaded only to Hightouch and remains excluded from Git. Slack OAuth is authorized, the destination health test passes, and the `At Risk Nurses` model reads `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` with `NURSE_ID` as its primary key. Sync `8379886` is enabled for Slack channel `C0BS2TQSS9M`.

The first live run on 29 August 2026 queried 257 model rows. Slack rejected all 257 operations with `not_in_channel`; the Hightouch Slack app must be invited to the selected channel before rerunning.

After the channel membership fix:

1. Rerun sync `8379886`.
2. Confirm 257 successful operations and zero rejected operations.
3. Open Slack channel `C0BS2TQSS9M` and verify the delivered table.
4. Generate the next Airflow batch and rerun the sync to demonstrate changed-row activation.

## Completion boundary

The production-style core pipeline (EC2/Airflow -> S3 -> Snowflake -> dbt), the SurveyMonkey -> Fivetran -> Snowflake path, and both Snowflake SaaS service connections are complete. A fresh `2026-08-30` batch is present in S3, Snowflake contains 4,000 raw nurse snapshots and 500 unique nurses, all seven core data quality checks pass, and the Fivetran landing database contains 51 verified SurveyMonkey rows.

The remaining live-demo work is adding the Hightouch app to the selected Slack channel and rerunning sync `8379886`. Marketo and Pendo remain optional because their APIs require subscription-level credentials. The new Fivetran Terraform schedule module defaults to `pause_after_trial = true`, but applying that live guardrail requires a Fivetran API key and secret.
