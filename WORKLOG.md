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
  - Added 12 mocked behavioral tests for Fivetran and Hightouch covering success, remote failure,
    timeout, transient network errors, missing environment variables, and non-runnable states.

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

### A. Locally Verified (All Automated Checks Passed)

| Check | Command | Result | Details |
|---|---|---|---|
| Python Test Suite | `python -m unittest discover -s tests -v` | **PASS** | 43 tests passed in ~17s (14 original + 29 contract/behavioral) |
| Credential-Free dbt Parse | `dbt --no-version-check parse --project-dir dbt --profiles-dir <mock_dir>` | **PASS** | Exit code 0, 0 compilation errors, no database connection required |
| dbt Source Uniqueness | `test_no_duplicate_sources_across_project` | **PASS** | 0 duplicate source/table pairs across all project YAMLs |
| PowerShell Syntax | `[System.Management.Automation.Language.Parser]::ParseFile(...)` | **PASS** | 0 parse errors on `scripts/invoke_case_study_pipeline.ps1` |
| Terraform Formatting | `terraform fmt -check -recursive infra/terraform` | **PASS** | Exit code 0, all HCL files cleanly formatted |
| Terraform Platform Validation | `terraform -chdir=infra/terraform/platform validate` | **PASS** | `Success! The configuration is valid.` |
| Git Whitespace Check | `git diff --check` | **PASS** | 0 whitespace or syntax errors |
| UTF-8 BOM Scan | Byte-level scan on all repository text files | **PASS** | All files verified `Has BOM: False` |
| Security & State Leak Check | `git status --short` | **PASS** | 0 `.tfstate`, 0 private keys, 0 `.env` files tracked or staged |

### B. CLI Verified Against Live Services (Previous Sessions / Read-Only Inspection)

1. **AWS Infrastructure State (Read-Only CLI):**
   - Verified via `terraform state list -state="infra/terraform/s3/terraform.tfstate"`:
     - S3 Bucket: `carematch-data-237657481511-dev`
     - Security policies, versioning, server-side encryption, ownership controls.
   - Verified via `terraform state list -state="infra/terraform/ec2-airflow/terraform.tfstate"`:
     - EC2 Instance ID: `i-02bdd56e8690f35d1`
     - VPC: `vpc-06f2b35276e5960a6`, Subnet: `subnet-08db96d60aa233607`, SG: `sg-065e44fa631d5df4c`
     - IAM Role & Profile: `carematch-dev-airflow`
     - S3 VPC Endpoint: `vpce-06e7663082dc90b92`
2. **Snowflake Service Identities (From Prior Authenticated CLI Query):**
   - Service users `FIVETRAN_USER` and `HIGHTOUCH_USER` provisioned with RSA key-pair authentication.
   - Roles `FIVETRAN_ROLE` and `HIGHTOUCH_ROLE` granted required permissions.
3. **Fivetran Destination & Landing Data (From Prior CLI Query):**
   - Destination schema `FIVETRAN_LANDING` contains 51 verified SurveyMonkey survey records loaded by connector `prohibited_every`.
4. **Git Remote Connectivity (CLI Dry-Run):**
   - `git push origin main --dry-run` authenticated and verified clean fast-forward to `https://github.com/mindofyaseen/intelycare-snowflake.git`.

> *Note:* In accordance with instructions, no live modifying cloud operations, live EC2 SSM commands,
> or live SaaS API triggers were initiated during this correction pass.

### C. Browser-Only Work Still Remaining

The following tasks strictly require human browser interaction and cannot be performed via CLI:

1. **SurveyMonkey OAuth Authorization:**
   - Authorizing or renewing Fivetran's access token to SurveyMonkey via the SurveyMonkey browser login and OAuth consent screen.
2. **Hightouch Slack App Installation / Channel Invitation:**
   - Adding the Hightouch Slack application to private/demo Slack channel `C0BS2TQSS9M` in the Slack desktop/web UI.
3. **Visual Verification in SaaS Dashboards:**
   - Viewing the delivered sync table in the Slack channel.
   - Viewing Fivetran connector sync history graphs in the Fivetran web console.
   - Inspecting Snowsight worksheets or dashboards in the Snowflake web UI (optional manual review).

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
