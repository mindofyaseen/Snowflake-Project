# CareMatch Pipeline - Final Correction & Validation Work Log

## Executive Summary
This document provides the complete, truthful record of the code audit, correction pass,
validation checks, and remaining tasks for the CareMatch IntelyCare-inspired data platform.

---

## 1. Audit Findings & Corrections Implemented

### A. dbt Sources & Uniqueness
- **Issue:** Commit `2f7455a` mistakenly claimed `sources.yml` was missing and created
  `dbt/models/staging/sources.yml`. However, `dbt/models/sources.yml` already existed.
  This caused dbt compilation failure with `Compilation Error: dbt found two sources with the name 'raw_nurses'`.
- **Correction:** Merged all column descriptions and update tracking fields into the canonical
  `dbt/models/sources.yml`, preserving all existing `not_null` tests. Deleted the duplicate
  `dbt/models/staging/sources.yml`. Added automated tests ensuring no duplicate source definitions
  exist across the project and validating that `dbt parse` succeeds without credentials.

### B. dbt Packages & `.gitignore`
- **Issue:** `dbt/packages.yml` was placed into `.gitignore` under the assumption that it was a
  generated lock file.
- **Correction:** Removed `dbt/packages.yml` from `.gitignore`. Confirmed the project does not require
  external packages. Updated `Invoke-SnowflakeAndDbt` in `scripts/invoke_case_study_pipeline.ps1`
  to check `Test-Path "dbt/packages.yml"` and skip `dbt deps` cleanly when absent.

### C. File Encodings (UTF-8 without BOM)
- **Issue:** Several text files had UTF-8 Byte Order Marks (`0xEF, 0xBB, 0xBF`) introduced.
- **Correction:** Stripped BOM characters from all repository files. Automated byte-level scan confirms
  `Has BOM: False` across all text files.

### D. Fivetran Polling Logic
- **Issue:** Previous script checked `status.sync_state == "connected"`, which does not reliably prove
  that a newly triggered sync finished.
- **Correction:** Implemented `scripts/saas_sync.py`. It captures baseline `succeeded_at` and `failed_at`
  timestamps prior to calling `/force`. Polling succeeds only when `succeeded_at` advances past baseline.
  It immediately fails if `failed_at` advances or if `sync_state` is `paused` or `rescheduled`. Transient
  HTTP errors are logged as warnings and retried until timeout. Timeout and poll interval are configurable.

### E. Hightouch Polling Logic
- **Issue:** Previous script fell back to the first request in the list if the triggered sync request ID
  could not be matched.
- **Correction:** Implemented exact request ID matching in `scripts/saas_sync.py`. If the triggered request
  ID is missing or not found in `sync_requests`, it raises a clear error. Explicitly handles `success`,
  `failed`, `cancelled`, and `interrupted` states.

### F. Behavioral Testing & Production Function Testing
- **Issue:** Tests relied on brittle string matching or duplicated production algorithms. The FORCE test
  stripped whitespace before searching for `"FORCE = TRUE"`, which could never match.
- **Correction:**
  - Exported `sanitize_batch_id` and `build_s3_raw_key` from `src/generate_healthcare_data.py` and
    imported them directly into `airflow/dags/synthetic_sources_to_s3.py`. Unit tests verify these
    exact production functions.
  - Implemented case-insensitive regex `FORCE\s*=\s*TRUE` and added a test proving the regex catches
    all spacing variants.
  - Added 14 mocked behavioral and CLI tests for Fivetran and Hightouch covering success, remote failure,
    timeout, transient network errors, missing environment variables, CLI exit codes, and non-runnable states.

### G. Terraform Migration Guide
- **Issue:** Migration guide used `carematch-dev` AWS profile, omitted IAM associations, and suggested
  deleting state files on rollback.
- **Correction:** Rewrote `docs/TERRAFORM_MIGRATION.md` with exact addresses and IDs discovered via
  read-only `terraform state list` from existing state files. Specified AWS profile `default`.
  Included all 7 S3 resources and 12 EC2/Airflow resources (including IAM instance profile, role policy,
  managed attachment, route table association, and VPC endpoint). Added explicit no-destroy plan checks
  and safe rollback via state backups or targeted `state rm`. Explicitly noted the guide has not been
  executed live.

### H. PowerShell Orchestration Script
- Supports explicit `-AirflowInstanceId`, `-S3BucketName`, and `-SnowflakeRoleArn`.
- In `verify` mode, does not query Terraform platform outputs when `-S3BucketName` is supplied.
- Always captures diagnostic output from SSM command invocations, even when `aws ssm wait` exits non-zero.
- Exposes `-SaasTimeoutSeconds` and `-SaasPollIntervalSeconds`.
- Validates required environment variables and never logs secret values.

---

## 2. Verification Results

### A. Locally Verified in This Pass (All Automated Checks Passed)

All of the following checks were executed directly in the local environment during this pass:

| Check | Command | Result | Details |
|---|---|---|---|
| Python Test Suite | `python -m unittest discover -s tests -v` | **PASS** | 45 tests passed in ~11.5s (14 original + 31 contract/behavioral/CLI) |
| Credential-Free dbt Parse | `dbt --no-version-check parse --project-dir dbt --profiles-dir <mock_dir>` | **PASS** | Exit code 0, 0 compilation errors, no database connection required |
| dbt Source Uniqueness | `test_no_duplicate_sources_across_project` | **PASS** | 0 duplicate source/table pairs across all project YAMLs |
| PowerShell Syntax | `[System.Management.Automation.Language.Parser]::ParseFile(...)` | **PASS** | 0 parse errors across all 7 `.ps1` scripts in `scripts/` |
| Terraform Formatting | `terraform fmt -check -recursive infra/terraform` | **PASS** | Exit code 0, all HCL files cleanly formatted |
| Terraform Platform Validation | `terraform -chdir=infra/terraform/platform validate` | **PASS** | `Success! The configuration is valid.` |
| Git Whitespace Check | `git diff --check` | **PASS** | 0 whitespace or syntax errors |
| UTF-8 BOM Scan | Byte-level scan across all 201 repository files | **PASS** | 0 files with BOM (`Has BOM: False` for all files) |
| Security & State Leak Check | `git ls-files` regex & pattern scan | **PASS** | 0 `.tfstate`, 0 private keys, 0 `.env` files tracked or staged |

---

### B. Historical Evidence (Not Reverified in This Pass)

The following items represent historical evidence recorded in prior sessions and documentation.
**They were NOT reverified against live services in this correction pass**, as live cloud mutations
and API calls were strictly disabled:

1. **AWS Infrastructure Live State (Historical):**
   - S3 Bucket `carematch-data-237657481511-dev` and EC2 instance `i-02bdd56e8690f35d1` are documented
     in existing local `.tfstate` files. Their live status in AWS was not pinged or modified in this pass.
2. **Snowflake Service Users and Grants (Historical):**
   - `FIVETRAN_USER` and `HIGHTOUCH_USER` RSA service accounts documented in `snowflake/sql/05_service_integrations.sql`
     and prior verification logs were not queried live against Snowflake in this pass.
3. **Fivetran Ingested Row Counts (Historical):**
   - The 51 rows recorded in `FIVETRAN_LANDING.SURVEY_MONKEY_CASE_STUDY` were documented from the
     historical run on 31 August 2026. No live query was run against Snowflake.

---

### C. Live Initial & Incremental Runs Status (Unverified in This Pass)

- **The live end-to-end initial (500 nurses) and incremental (550 nurses) pipeline executions
  remain unverified in this correction pass.**
- Executing the live runs requires active AWS credentials to dispatch SSM commands to EC2,
  live Snowflake connectivity for `COPY INTO` and `dbt build`, and live SaaS API keys for Fivetran
  and Hightouch.
- In accordance with the prompt constraints, no live services were invoked.

---

### D. SaaS Channel & Browser Configuration Tasks Remaining

1. **Hightouch Slack Channel Configuration:**
   - **Important Risk:** Hightouch sync `8379886` may still reference the stale Slack channel `C0BS2TQSS9M`.
   - The intended valid demo Slack channel is `#first-project` with ID `C0BSC5B2743`.
   - In accordance with the instruction not to alter live SaaS configurations, this mapping must be
     updated directly in the Hightouch UI by the account owner prior to demo execution.
   - The Hightouch app must also be invited to `#first-project` (`/invite @Hightouch`).
2. **SurveyMonkey OAuth Grant:**
   - Authorizing or renewing Fivetran's access token to SurveyMonkey requires completing the OAuth
     consent screen in a web browser.
3. **SaaS Web UI Dashboard Review:**
   - Visual inspection of the delivered audience in Slack, Fivetran connector sync graphs, and
     Snowsight query history worksheets.

---

## 3. Credential-Dependent Tasks (For Live Operator Execution)

When live credentials are provided to an authorized operator, execute the following:

```powershell
# 1. Set environment credentials
$env:AWS_PROFILE = "default"
$env:SNOWFLAKE_ACCOUNT = "AGBKFYW-JO98858"
$env:SNOWFLAKE_USER = "CAREMATCH_TRANSFORMER"
$env:SNOWFLAKE_PRIVATE_KEY_FILE = ".secrets/snowflake_rsa_key.p8"
$env:FIVETRAN_APIKEY = "<key>"
$env:FIVETRAN_APISECRET = "<secret>"
$env:FIVETRAN_CONNECTOR_ID = "prohibited_every"
$env:HIGHTOUCH_API_KEY = "<key>"
$env:HIGHTOUCH_SYNC_ID = "8379886"

# 2. Run initial load (500 nurses)
.\scripts\invoke_case_study_pipeline.ps1 -Mode initial `
    -AirflowInstanceId i-02bdd56e8690f35d1 `
    -S3BucketName carematch-data-237657481511-dev `
    -RunFivetran -RunHightouch

# 3. Run incremental load (550 nurses)
.\scripts\invoke_case_study_pipeline.ps1 -Mode incremental `
    -AirflowInstanceId i-02bdd56e8690f35d1 `
    -S3BucketName carematch-data-237657481511-dev `
    -IncrementalNurseCount 550 `
    -RunFivetran -RunHightouch

# 4. Verify results (read-only)
.\scripts\invoke_case_study_pipeline.ps1 -Mode verify `
    -S3BucketName carematch-data-237657481511-dev
```