# Incremental pipeline verification — 2026-08-24

## Architecture contract

```text
Operational / External / Data Science / Appcast / App Stream / Spreadsheets
                                |
                         EC2 Airflow Server
                                |
                           S3 Data Lake
                                |
                            Snowflake
                                |
                               dbt
                                |
                            Hightouch
                                |
                    Salesforce / Slack / OneDrive

SurveyMonkey / Marketo / Pendo -> Fivetran -> Snowflake
```

The six-source Airflow branch, S3 landing zone, Snowflake ingestion, and dbt-equivalent transformation branch were run live. Hightouch and Fivetran remain activation milestones and are not reported here as live data movement.

## Live execution evidence

| Check | Result |
| --- | --- |
| EC2 instance | `i-02bdd56e8690f35d1`, running |
| Airflow DAG run | `manual__incremental_20260825` |
| Airflow task states | 8 of 8 succeeded |
| S3 batch partition | `load_date=2026-08-25` |
| S3 batch objects | 11 source files plus manifest |
| S3 batch rows | 20,086 |
| S3 batch bytes | 1,727,178 |
| Local automated tests | 8 of 8 passed |
| Snowflake RAW before | 20,082 rows |
| Snowflake RAW after first COPY | 40,168 rows |
| Expected/actual RAW delta | 20,086 / 20,086 |
| Snowflake RAW after identical COPY rerun | 40,168 rows |
| Duplicate rows added by rerun | 0 |
| Snowflake data-quality checks | 7 of 7 returned zero failures |

## Post-transform counts

| Model | Rows |
| --- | ---: |
| `ANALYTICS.DIM_NURSES` | 500 |
| `ANALYTICS.FCT_SHIFT_PERFORMANCE` | 3,000 |
| `ANALYTICS.MART_MARKETING_EFFICIENCY` | 8 |
| `ANALYTICS.MART_MARKET_SUPPLY_DEMAND` | 30 |
| `ANALYTICS.AUDIENCE_AT_RISK_NURSES` | 295 |

The stable dimensions/facts remain at 500 nurses and 3,000 shifts even though RAW contains two append-only batches. Date-grained marketing and market marts correctly contain both daily batches.

## Incremental guarantees verified

1. Airflow supports an explicit `dag_run.conf.load_date` for deterministic backfills and incremental tests.
2. Each batch lands under a new immutable S3 date partition.
3. Snowflake COPY history prevents a previously loaded file from being loaded again.
4. RAW preserves both batches as append-only audit history.
5. STAGING deduplicates business keys before analytics models are built.
6. Relationship, uniqueness, and activation-policy checks all pass after the second batch.
