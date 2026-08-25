# Final core-pipeline verification — 2026-08-25

## Verified execution

The EC2-generated branch was resumed and executed as a controlled historical backfill:

```text
EC2 Airflow -> S3 raw/load_date=2026-08-23 -> Snowflake RAW
            -> dbt-equivalent STAGING/ANALYTICS deployment -> QA
```

| Check | Verified result |
| --- | --- |
| EC2 instance | `i-02bdd56e8690f35d1`, running and SSM online |
| Airflow DAG | `carematch_synthetic_sources_to_s3` |
| Final run ID | `manual__case_study_final_20260823` |
| Airflow tasks | 8/8 succeeded |
| Added S3 partition | `load_date=2026-08-23` |
| Added S3 source files | 11 plus one manifest |
| Added batch rows | 20,122 |
| Added batch bytes | 1,721,655 |
| S3 partitions now verified | `2026-08-23`, `2026-08-24`, `2026-08-25` |
| Snowflake RAW rows | 60,290 |
| Data-quality tests | 7 executed, 0 failures |
| Local repository tests | 8/8 passed |

The final manifest records all six source families, per-file row and byte counts,
and SHA-256 checksums. Snowflake loaded only the previously unseen S3 filenames.

## Post-transformation counts

| Relation | Rows |
| --- | ---: |
| `STAGING.STG_NURSES` | 500 |
| `STAGING.STG_SHIFTS` | 3,000 |
| `STAGING.STG_APPLICATIONS` | 10,615 |
| `STAGING.STG_ASSIGNMENTS` | 2,007 |
| `STAGING.STG_APP_EVENTS` | 3,018 |
| `ANALYTICS.DIM_NURSES` | 500 |
| `ANALYTICS.FCT_SHIFT_PERFORMANCE` | 3,000 |
| `ANALYTICS.MART_MARKETING_EFFICIENCY` | 12 |
| `ANALYTICS.MART_MARKET_SUPPLY_DEMAND` | 45 |
| `ANALYTICS.AUDIENCE_AT_RISK_NURSES` | 286 |

RAW grew from 40,168 to 60,290 rows, while the current-state nurse and shift
models remained at 500 and 3,000 rows. This is the expected result of append-only
batch history followed by business-key deduplication.

## External integration boundary

The core data pipeline is live and verified. The SaaS accounts are prepared but
the following authorization-owned steps remain:

- Hightouch: `CareMatch Snowflake` source is connected. Slack is selected and the
  setup is paused at **Add to Slack**, which requires Slack workspace OAuth approval.
- Fivetran: Snowflake destination tests passed. The Marketo connector is paused at
  the required REST endpoint, identity endpoint, client ID, and client secret fields.

No Slack delivery or Marketo initial sync is claimed until those external-account
permissions are supplied and a successful run is recorded.
