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

## Five-minute live showcase

This demo proves partition-based incremental ingestion and idempotency without
deleting or resetting any existing data.

1. In Airflow, open `carematch_synthetic_sources_to_s3`, select **Trigger DAG w/ config**.
   Omit `load_date` to use today's UTC date, and request a visibly different
   source size:

   ```json
   {"nurse_count": 525}
   ```

2. Trigger the run and show the graph. The expected result is eight green tasks:
   one generator, six parallel source uploads, and one manifest upload.
3. In S3, open the bucket and show the new keys under
   `raw/source=.../entity=.../load_date=YYYY-MM-DD/batch_id=RUN_ID/` plus
   `manifests/load_date=YYYY-MM-DD/batch_id=RUN_ID/manifest.json`.

   If `load_date` is omitted, the DAG uses the actual current UTC date. The
   optional `nurse_count` setting makes a before-and-after demonstration easy.
4. In Snowsight, record a simple RAW count before loading:

   ```sql
   USE ROLE ACCOUNTADMIN;
   USE WAREHOUSE CAREMATCH_INGEST_WH;
   USE DATABASE CAREMATCH;
   SELECT COUNT(*) AS nurses_before FROM RAW.NURSES;
   ```

5. Run `snowflake/sql/02_s3_stage_and_raw_load.sql`. Its `COPY INTO` results should
   show rows loaded for the newly created files. Run the count again and show that it
   increased.
6. Immediately rerun the same SQL file without `FORCE = TRUE`. Snowflake load history
   skips those filenames, so the count remains unchanged and the second-run delta is
   zero.
7. Run dbt, then show that RAW retains every batch while the current-state model is
   deduplicated by business key:

   ```sql
   SELECT COUNT(*) AS raw_nurse_rows FROM CAREMATCH.RAW.NURSES;
   SELECT COUNT(*) AS current_nurses FROM CAREMATCH.ANALYTICS.DIM_NURSES;
   SELECT nurse_id, COUNT(*) AS copies
   FROM CAREMATCH.ANALYTICS.DIM_NURSES
   GROUP BY nurse_id
   HAVING COUNT(*) > 1;
   ```

   The final query must return no rows.

### What to say during the demo

“Airflow creates a deterministic batch for a new business date. S3 stores it in a
new immutable date partition. Snowflake loads only filenames absent from its COPY
history, so a new partition adds rows but rerunning the same partition adds zero.
RAW remains append-only for auditability; dbt staging ranks records by business key
and keeps the newest version for the analytics models.”

This is file/partition-level incremental loading. The synthetic demo intentionally
generates a complete daily source snapshot; dbt deduplication prevents those daily
snapshots from multiplying current-state entities downstream.

## Same-day batch verification on 2026-08-29

The updated DAG was deployed to the EC2 Airflow server and run with this config:

```json
{"nurse_count": 525}
```

The run ID was `manual__same_day_incremental_20260829_525`. Airflow completed the
run successfully and stored the files under a unique `batch_id` path for the actual
UTC date. Snowflake then loaded the new files and the transformation models were
refreshed.

| Check | Before | After |
| --- | ---: | ---: |
| RAW nurse rows | 4,500 | 5,025 |
| Distinct nurse IDs in RAW | 500 | 525 |
| Current nurses in `STAGING.STG_NURSES` | 500 | 525 |
| At-risk nurses for Hightouch | 245 | 257 |

Snowflake COPY history contained one nurse file for this run. An immediate rerun
of the same `COPY INTO NURSES` statement left the counts at 5,025 RAW rows and 525
distinct nurses, proving that the same file was not duplicated. The final quality
summary was 7 tests run, 0 failed tests, and 0 failing rows.
