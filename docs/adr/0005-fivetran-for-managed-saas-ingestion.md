# ADR-0005: Fivetran for Managed SaaS Ingestion (SurveyMonkey)

## Status
Accepted

## Context
Nurse satisfaction surveys collected via SurveyMonkey must be regularly ingested into Snowflake. Developing and maintaining
custom REST API connectors requires handling rate limiting, schema changes, pagination, and OAuth token refreshes.

## Decision
Use Fivetran to ingest SurveyMonkey survey and response data directly into Snowflake `FIVETRAN_LANDING` database.

## Benefits
- Automated schema migration, table creation, and normalization.
- Zero maintenance for upstream SurveyMonkey API changes.
- Least-privilege key-pair authentication into dedicated Snowflake landing database.

## Drawbacks
- SaaS subscription cost.
- Third-party OAuth connection requires account owner web browser authorization.

## Risks
- OAuth token expiration can pause syncs. Mitigated by automated failure alerts and clear runbook documentation.

## Alternatives Considered
- Custom Python Airflow DAG: Requires ongoing maintenance of API client, token persistence, and pagination logic.
