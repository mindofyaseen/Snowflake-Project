# ADR-0004: dbt (Data Build Tool) for Transformations

## Status
Accepted

## Context
Raw data loaded into Snowflake contains duplicate snapshots, raw strings, and denormalized JSON. Transformations must be
version-controlled, modular, tested, and documented.

## Decision
Utilize dbt for all in-warehouse transformations across Staging views and Analytics reporting marts.

## Benefits
- Declarative SQL with Jinja templating enables DRY (Don't Repeat Yourself) code patterns.
- Built-in data quality testing (unique, not_null, accepted_values, relationships).
- Automated lineage graph and documentation generation.
- Staging views (`stg_nurses`) cleanly separate deduplication logic (`QUALIFY ROW_NUMBER() = 1`) from dimensional presentation (`dim_nurses`).

## Drawbacks
- Requires dbt runtime environment and profile configuration.
- dbt is ELT-only (operates after data lands in the warehouse).

## Risks
- Model build dependencies could fail if staging contracts change. Mitigated by rigorous dbt source declarations and contract tests.

## Alternatives Considered
- Snowflake Stored Procedures / Streams and Tasks: Difficult to version control, test, and document; lacks automated lineage tracking.
- Python ETL scripts: Pulling data out of the warehouse to transform in memory wastes network bandwidth and compute power.
