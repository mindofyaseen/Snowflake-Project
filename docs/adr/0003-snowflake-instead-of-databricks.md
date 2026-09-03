# ADR-0003: Snowflake Data Cloud Instead of Databricks Lakehouse

## Status
Accepted

## Context
CareMatch needs a central analytics engine to ingest structured CSV and semi-structured JSONL data, perform ELT deduplication,
support SQL-first data transformations, and serve reverse ETL audiences.

## Decision
Adopt Snowflake as the data warehouse and analytical processing engine.

## Benefits
- Native, high-performance semi-structured data support (VARIANT type and dot-notation path querying for `events.jsonl`).
- Separation of compute and storage: Warehouses auto-suspend after 1 minute of inactivity, eliminating compute idle costs.
- Native `COPY_HISTORY` tracking guarantees file-level ingestion idempotency without custom deduplication code.
- Direct ecosystem integration with Fivetran (automated landing schemas) and Hightouch (SQL-based audience syncs).

## Drawbacks
- Proprietary cloud warehouse architecture compared to open-source Delta/Iceberg tables.
- Compute charges are billed in Snowflake credits.

## Risks
- Long-running unoptimized queries could consume credits. Mitigated by auto-suspend rules and warehouse statement timeouts.

## Alternatives Considered
- Databricks Lakehouse (Spark / Delta Lake): Highly capable, but introduces higher cluster management overhead and cluster spin-up latency compared to Snowflake's instant serverless warehouse start.
- Amazon Redshift: Less seamless semi-structured JSON handling and more rigid cluster provisioning.
