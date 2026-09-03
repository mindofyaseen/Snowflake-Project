# CareMatch SaaS Integrations - Account Owner Browser Handoff

This guide documents the exact minimal browser steps required by the account owner to complete
third-party OAuth authorization, verify SaaS connector health, and align destination channels.

---

## 1. SurveyMonkey OAuth Reauthorization in Fivetran

### Purpose
Fivetran synchronizes survey responses from the SurveyMonkey collector into the Snowflake
`FIVETRAN_LANDING` database. If the 30-day trial or OAuth refresh token expires, the connector
requires web-based reauthorization.

### Step-by-Step Instructions
1. Navigate to the Fivetran web dashboard: `https://fivetran.com/dashboard`.
2. In the left navigation menu, click **Connectors**.
3. Select connector **`prohibited_every`** (Source: SurveyMonkey).
4. In the connector details view, click the **Setup** tab.
5. Under **Authentication**, click the **Re-authorize Connection** or **Edit Connection Details** button.
6. A popup window will prompt for SurveyMonkey login:
   - Sign in with the survey creator credentials.
   - Click **Authorize** to grant Fivetran read access to surveys and responses.
7. Return to the connector **Status** tab.
8. Confirm the connector status displays **CONNECTED** and sync state is **Ready**.
9. Click **Sync Now** to test ingestion.
10. Expected Outcome: The sync completes within 1 to 2 minutes, and the `succeeded_at` timestamp advances.

---

## 2. Hightouch Slack Channel Destination Alignment

### Purpose
Hightouch sync `8379886` delivers the disengaging nurse retention audience from Snowflake model
`CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` to Slack. The sync historically targeted a stale channel
ID (`C0BS2TQSS9M`) which resulted in a `not_in_channel` error. The destination must be updated to the
intended demo channel `#first-project` (`C0BSC5B2743`).

### Step-by-Step Instructions
1. Open the Slack workspace in browser or desktop app:
   - Navigate to channel **`#first-project`** (Channel ID: `C0BSC5B2743`).
   - In the message composer, type `/invite @Hightouch` and press Enter.
   - Confirm the bot joins the channel (`@Hightouch has joined the channel`).
2. Open the Hightouch web dashboard: `https://app.hightouch.com/`.
3. In the left navigation menu, click **Syncs**.
4. Select sync **`8379886`** (Source: `CAREMATCH.ANALYTICS.AUDIENCE_AT_RISK_NURSES` -> Destination: Slack).
5. Click the **Configuration** tab.
6. Under **Destination Details**:
   - Locate the **Channel** field.
   - If the field contains `C0BS2TQSS9M`, clear it and select or paste **`#first-project`** (or ID `C0BSC5B2743`).
7. Click **Save Changes** at the top right.
8. Click the **Test** or **Health Check** button to verify destination connectivity.
9. Expected Outcome: "Destination test passed with 0 errors."

---

## 3. Triggering and Verifying Hightouch Delivery

### Step-by-Step Instructions
1. In the Hightouch sync `8379886` view, click **Run Sync** (or **Trigger Run**).
2. Monitor the live execution progress:
   - **Rows Queried:** ~280 - 310 rows (from `AUDIENCE_AT_RISK_NURSES`).
   - **Successful Operations:** ~280 - 310 operations.
   - **Rejected Operations:** **0 rejected**.
3. Open Slack and inspect channel **`#first-project`**:
   - Confirm tabular notification messages appear detailing nurse IDs, full names, specialties, and churn risk scores.
   - Confirm no messages were delivered to any unexpected channels.

---

## 4. Snowsight Query Verification (Read-Only)

### Step-by-Step Instructions
1. Open Snowflake Snowsight console: `https://app.snowflake.com/`.
2. Select account **`AGBKFYW-JO98858`**.
3. In the left menu, click **Projects** -> **Worksheets**.
4. Create a new SQL worksheet using role `ACCOUNTADMIN` and warehouse `CAREMATCH_INGEST_WH`.
5. Execute the verification queries in `docs/SNOWFLAKE_DEMO_QUERIES.sql` to confirm:
   - Baseline nurse count = 500
   - Post-incremental nurse count = 550
   - Cumulative raw snapshots = 1,050
   - Zero duplicate active nurses in `CAREMATCH.ANALYTICS.DIM_NURSES`.
