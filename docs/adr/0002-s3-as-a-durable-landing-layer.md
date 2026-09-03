# ADR-0002: Amazon S3 as an Immutable, Durable Data Lake Landing Layer

## Status
Accepted

## Context
Operational and synthetic healthcare systems produce batched snapshots across 6 source families. Direct ingestion into the
data warehouse without a durable file-based buffer risks data loss during network disruptions and impairs re-playability.

## Decision
Establish Amazon S3 as the authoritative landing layer. Files are partitioned by `source=<family>/entity=<name>/load_date=<YYYY-MM-DD>/batch_id=<id>/`
accompanied by a cryptographic `manifest.json`.

## Benefits
- Complete separation of durable storage from warehouse compute.
- Immutable, audit-ready historical snapshots allowing point-in-time replays.
- S3 Object Versioning and server-side AES-256 encryption guarantee data durability and security.
- Standardized external stage for high-throughput Snowflake bulk loading (`COPY INTO`).

## Drawbacks
- Adds a storage hop prior to querying data in SQL.
- Requires lifecycle management to prevent indefinite storage accumulation.

## Risks
- Potential prefix sprawl without organized partitioning. Mitigated by Hive-style partitioning schema.

## Alternatives Considered
- Direct Streaming API to Snowflake (Snowpipe Streaming): Rejected due to lack of an external durable audit trail and higher operational overhead for batch datasets.
- Local EC2 Shared Disk: Rejected due to lack of durability and scalability.
