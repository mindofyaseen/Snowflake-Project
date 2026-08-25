# Hightouch and Fivetran integration runbook

## Security prerequisites

Generate independent RSA key pairs locally:

```powershell
.\scripts\generate_service_keys.ps1
```

The generated private keys are written under `.secrets/`, which is ignored by Git. Apply `snowflake/sql/05_service_integrations.sql` after replacing its two public-key placeholders. Never paste a private key into Snowflake.

## Hightouch source

Use the following connection settings:

| Setting | Value |
|---|---|
| Account identifier | `AGBKFYW-JO98858` |
| Warehouse | `CAREMATCH_INGEST_WH` |
| Database | `CAREMATCH` |
| Sync engine | Lightning |
| Username | `HIGHTOUCH_USER` |
| Role | `HIGHTOUCH_ROLE` |
| Authentication | RSA key pair |
| Private key file | `.secrets/hightouch_rsa_key.p8` |

Create a model from `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` and set `NURSE_ID` as the primary key. Map only the fields approved for the selected downstream destination.

## Fivetran destination

Use the following destination settings:

| Setting | Value |
|---|---|
| Host | `AGBKFYW-JO98858.snowflakecomputing.com` |
| Port | `443` |
| User | `FIVETRAN_USER` |
| Database | `FIVETRAN_LANDING` |
| Authentication | Key pair |
| Private key | Contents of `.secrets/fivetran_rsa_key.p8` |
| Private key encrypted | No |
| Role | `FIVETRAN_ROLE` |
| Connection method | Connect directly |
| Storage for unstructured files | Internal |
| Default warehouse | `FIVETRAN_WAREHOUSE` |

After `Save & Test` succeeds, connect one authorized SaaS source (SurveyMonkey, Marketo, or Pendo for the target architecture), select the minimum required schemas/tables, and run its initial sync. Verify that the connector creates its schema under `FIVETRAN_LANDING`, then rerun to demonstrate cursor-based incremental loading.

## Verification queries

```sql
USE ROLE ACCOUNTADMIN;

SHOW USERS LIKE 'HIGHTOUCH_USER';
SHOW GRANTS TO ROLE HIGHTOUCH_ROLE;

SHOW USERS LIKE 'FIVETRAN_USER';
SHOW GRANTS TO ROLE FIVETRAN_ROLE;

SHOW SCHEMAS IN DATABASE FIVETRAN_LANDING;

SELECT COUNT(*) AS activation_rows
FROM CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES;
```

