# ADR-0006: Hightouch for Reverse ETL to Slack

## Status
Accepted

## Context
Analytical insights (e.g. nurses at risk of churn identified in `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES`) must be
operationalized by alerting healthcare staffing recruiters in Slack.

## Decision
Deploy Hightouch to sync governed nurse retention audiences from Snowflake directly to Slack channel `#first-project` (`C0BSC5B2743`).

## Benefits
- Reverse ETL paradigm keeps the warehouse as the single source of truth.
- Built-in Change Data Capture (CDC): Only newly eligible or updated at-risk nurses trigger Slack notifications.
- Visual auditability: Tracks queried rows, successful deliveries, and rejected operations.

## Drawbacks
- Additional SaaS platform in the stack.
- Slack bot invitation (`/invite @Hightouch`) required prior to execution.

## Risks
- Stale channel references could cause delivery failures. Mitigated by explicit channel validation (`C0BSC5B2743`) and error handling.

## Alternatives Considered
- Custom Slack Webhook script: Lacks state tracking, change data capture, retry handling, and governance controls.
