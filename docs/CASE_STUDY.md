# CareMatch Modern Data Stack — Case Study

## Executive summary

CareMatch is a small-scale, production-shaped healthcare staffing data platform inspired by the IntelyCare modern-data-stack pattern. It consolidates six synthetic operational and engagement sources, orchestrates incremental delivery through Apache Airflow on Amazon EC2, lands immutable batches in Amazon S3, loads them into Snowflake, transforms them with dbt, and prepares governed audiences for reverse ETL through Hightouch. A separate Fivetran landing database demonstrates the managed-SaaS ingestion path into the same Snowflake account.

The implementation is intentionally small enough to demonstrate live, but uses the same separation of duties, idempotency, security boundaries, and observability expected in a larger platform.

## Business problem

Healthcare staffing teams need a consistent view of workforce supply, shift demand, application activity, assignment outcomes, marketing efficiency, and product engagement. When these datasets stay in separate operational tools and spreadsheets, teams cannot reliably answer questions such as:

- Which qualified nurses are at risk of disengaging?
- Where is staffing demand outpacing available supply?
- Which campaigns generate completed assignments rather than low-quality leads?
- Can activation data be delivered safely to customer-facing tools without copying unrestricted raw data?

## Target architecture

```text
Operational / external / data-science / app / spreadsheet sources
                              |
                              v
                    Airflow on Amazon EC2
                              |
                              v
                    Amazon S3 data lake
                              |
                              v
                         Snowflake RAW
                              |
                              v
                   dbt STAGING + ANALYTICS
                              |
                              v
               Hightouch governed activation model
                              |
                              v
                 Salesforce / Slack / other SaaS

Survey / marketing / product SaaS -> Fivetran -> Snowflake landing schemas
```

## Implemented solution

### Source simulation

The deterministic Python generator creates six source domains using synthetic identities only:

1. Nurses and workforce profiles
2. Shifts and facility demand
3. Applications
4. Assignments
5. Marketing and market-supply signals
6. Application/product events and spreadsheet-style reference data

Each generated batch includes a manifest containing object keys, schemas, row counts, and SHA-256 checksums. This makes every pipeline run independently verifiable.

### Orchestration and landing

Apache Airflow runs on a dedicated EC2 host and writes date-partitioned, Hive-style objects to the private S3 bucket `carematch-data-237657481511-dev`. The DAG is safe to rerun: immutable object keys and manifests prevent accidental overwrites, while Snowflake COPY metadata prevents duplicate ingestion.

The S3 landing zone blocks public access, enforces TLS, enables versioning, and encrypts objects at rest. EC2 access uses Systems Manager rather than an internet-exposed SSH port.

### Snowflake ingestion

Snowflake uses a scoped AWS storage integration with read-only access to the bucket's `raw/` prefix. The `CAREMATCH.RAW` layer contains 11 source tables. COPY operations preserve batch metadata and can be rerun without duplicating files.

A live two-batch verification loaded 40,168 raw rows. Rerunning the same COPY operations added zero rows, proving file-level incremental behavior.

### dbt transformation

dbt separates reusable cleanup logic from business models:

- `CAREMATCH.STAGING`: five views for typed, standardized source data.
- `CAREMATCH.ANALYTICS`: five materialized analytics tables.
- `AUDIENCE_AT_RISK_NURSES`: a consent-safe activation table with 295 eligible nurses in the verified run.

The marts cover nurse dimensions, shift performance, marketing efficiency, market supply-demand, and activation. Seven automated data-quality checks passed, including relationship tests, uniqueness expectations, and activation-policy assertions.

### Reverse ETL and managed ingestion

Snowflake service accounts use RSA key-pair authentication and dedicated least-privilege roles:

- `HIGHTOUCH_USER` / `HIGHTOUCH_ROLE` can read governed analytics objects and own only the Hightouch audit/planner schemas.
- `FIVETRAN_USER` / `FIVETRAN_ROLE` can write only to `FIVETRAN_LANDING` through the dedicated auto-suspending `FIVETRAN_WAREHOUSE`.

Private keys stay in the local, Git-ignored `.secrets/` directory. No passwords, private keys, OAuth tokens, or Terraform state are committed.

The selected activation destination is **Slack**, producing the primary path `Snowflake/dbt -> Hightouch -> Slack`. The selected Fivetran source is **Marketo**, producing the managed-ingestion path `Marketo -> Fivetran -> FIVETRAN_LANDING`. OneDrive remains an optional secondary export rather than a dependency of the main demonstration.

## Incremental-loading design

| Layer | Incremental mechanism | Duplicate protection |
|---|---|---|
| Generator | Batch timestamp and deterministic seed | Manifest and checksums |
| Airflow to S3 | Partitioned object keys | Immutable batch paths |
| S3 to Snowflake | COPY file metadata | Previously loaded files skipped |
| dbt staging | Stable business keys and typed views | Source-level deduplication |
| dbt marts | Deterministic model builds | Unique-key and relationship tests |
| Hightouch | Primary key `NURSE_ID` | Change-aware reverse ETL |
| Fivetran | Connector-managed cursors | Source-specific incremental state |

## Verified results

| Check | Result |
|---|---:|
| Snowflake RAW tables | 11 |
| Verified RAW rows | 40,168 |
| Duplicate rows added by COPY rerun | 0 |
| dbt staging views | 5 |
| dbt analytics tables | 5 |
| dbt/data-quality checks | 7/7 passed |
| Consent-safe at-risk audience | 295 rows |
| Fivetran Snowflake destination tests | 6/6 passed |

The live SaaS connection evidence and remaining account-authorization fields are recorded in [the SaaS integration verification report](SAAS_INTEGRATION_VERIFICATION_2026-08-25.md).

## Operational value

The platform creates one governed analytics layer for staffing, marketing, and activation use cases. The design reduces manual spreadsheet movement, makes every batch auditable, keeps raw data out of customer-facing tools, and allows downstream teams to receive only approved audience fields. Infrastructure and SQL are idempotent, so the demonstration can be repeated without rebuilding the environment by hand.

## Live demonstration flow

1. Open the Airflow DAG `carematch_synthetic_sources_to_s3` and show the successful task graph.
2. Open the S3 bucket and drill into `raw/` to show partitioned source objects and manifests.
3. In Snowflake, show the 11 RAW tables and run the row-count query.
4. Open the repository's `dbt/models` folder, then show the corresponding STAGING views and ANALYTICS tables in Snowflake.
5. Query `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` and explain its consent filters.
6. In Hightouch, show the Snowflake source, the `NURSE_ID` model key, destination mapping, and latest sync run.
7. In Fivetran, show the Snowflake destination test, connector schema, cursor-based incremental settings, and latest sync.
8. Rerun the Airflow/Snowflake load and show that already-loaded files contribute zero additional rows.

## Reproducibility

Infrastructure definitions, the generator, Airflow DAG, Snowflake SQL, dbt models, tests, and runbooks are version controlled in this repository. Start with the root README, then use the EC2/Airflow, Snowflake/dbt, and incremental-verification runbooks under `docs/`.
