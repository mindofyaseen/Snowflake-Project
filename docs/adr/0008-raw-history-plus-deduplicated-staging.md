# ADR-0008: Raw Cumulative History with Deduplicated Staging Models

## Status
Accepted

## Context
When incremental nurse snapshots arrive from operational systems, the platform must support both temporal auditability
(historical states) and current state reporting without data loss.

## Decision
Maintain raw tables as cumulative append-only snapshot logs. Implement deduplication in dbt staging models using:
`QUALIFY ROW_NUMBER() OVER (PARTITION BY <business_key> ORDER BY record_updated_at DESC) = 1`.

## Benefits
- Never destroys historical snapshots: Raw layer records all 1,050 cumulative nurse rows.
- Staging and Analytics layers always present the authoritative latest state (550 unique active nurses).
- Fully idempotent: Rerunning ingestion preserves historical integrity.

## Drawbacks
- Raw storage volume grows over time.

## Risks
- Querying raw tables directly without deduplication could double-count nurses. Mitigated by role-based access restricting reporting users to the `ANALYTICS` schema.

## Alternatives Considered
- Direct MERGE INTO / UPSERT in Raw Layer: Destroys historical audit trail and makes debugging incremental changes difficult.
