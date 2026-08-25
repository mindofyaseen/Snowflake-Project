# SaaS integration verification — 2026-08-25

## Selected flows

```text
CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES -> Hightouch -> Slack
Marketo -> Fivetran -> FIVETRAN_LANDING
```

OneDrive is retained as an optional secondary file-export destination and is not required for the primary live demonstration.

## Snowflake service identities

The idempotent provisioning SQL created and verified two RSA-authenticated service users:

- `HIGHTOUCH_USER` with `HIGHTOUCH_ROLE`
- `FIVETRAN_USER` with `FIVETRAN_ROLE`

Both users were returned by the Snowflake verification query with their dedicated roles and warehouses.

## Fivetran destination result

The Fivetran destination named `Warehouse` is connected to:

- Host: `AGBKFYW-JO98858.snowflakecomputing.com`
- Database: `FIVETRAN_LANDING`
- User: `FIVETRAN_USER`
- Role: `FIVETRAN_ROLE`
- Authentication: RSA key pair
- Default warehouse: `FIVETRAN_WAREHOUSE`
- Connection: direct, internal staging, AWS `us-east-1`

Fivetran reported **All connection tests passed** for:

1. Host Connection
2. Validate Passphrase
3. Default Warehouse Test
4. Database Connection
5. Validate Internal Stage Access Test
6. Permission Test

## Marketo connector

A Marketo connector draft was created with destination schema `marketo`. Final testing and initial sync require credentials from a Marketo Admin account:

- REST API Endpoint
- REST API Identity
- Client ID
- Client Secret

The connector is configured to use `FIVETRAN_WAREHOUSE` and defaults to full historical sync. Incremental sync is managed by Fivetran after the initial load.

## Hightouch and Slack

The Snowflake account, warehouse, database, service user, and role were entered into the Hightouch Snowflake source form. The final RSA private-key upload requires Chrome extension permission to access local file URLs. After that browser permission is enabled, complete the source test, create the audience model with primary key `NURSE_ID`, authorize Slack, and run the first sync.

