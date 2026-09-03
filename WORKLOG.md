# CareMatch Pipeline – Work Log

This file is maintained by the AI agent working on this repository.
It records every task, what was done, errors encountered, and how they were fixed.
Codex or any downstream reviewer can read this to understand exactly what changed and why.

---

## Session: 2026-09-03 (UTC+5)

### Objective
Complete a 10-task code-only audit and improvement of the CareMatch
`intelycare-snowflake` pipeline repository. No live cloud resources are touched.

---

## Task 1 – Repository Audit

**What was done:**
- Read `README.md`, all docs under `docs/`, every script in `scripts/`,
  all Terraform modules under `infra/terraform/`, all dbt models, and all tests.
- Read both live Terraform state files to extract resource IDs
  (bucket `carematch-data-237657481511-dev`, EC2 `i-02bdd56e8690f35d1`).

**Issues found:**

| # | File | Problem |
|---|------|---------|
| 1 | `dbt/models/staging/sources.yml` | **Completely missing.** All staging models reference `source('raw', ...)` but no `sources.yml` existed. `dbt compile` and all downstream analytics models would fail without credentials even being needed. |
| 2 | `scripts/invoke_case_study_pipeline.ps1` – `Invoke-FivetranSync` | Fire-and-forget POST with no polling, no success/failure check, errors swallowed by `Out-Null`. |
| 3 | `scripts/invoke_case_study_pipeline.ps1` – `Invoke-HightouchSync` | Same – fire-and-forget, no polling, no status output. |
| 4 | `scripts/invoke_case_study_pipeline.ps1` – SSM output | `aws ssm wait` exit code was checked but output was never captured/printed. Silent on pass. |
| 5 | `.gitignore` | Missing entries: `airflow/.env`, `terraform.tfvars` (non-example), `dbt/packages.yml`. |
| 6 | Tests | No tests covering 500/550 nurse counts, S3 batch-path uniqueness, Snowflake COPY idempotency, dbt QUALIFY dedup logic, missing SaaS env vars. |
| 7 | `docs/FULL_AUTOMATION_RUNBOOK.md` | No env var table, no flag reference, no SaaS polling documentation, no note that `verify` mode is read-only. |
| 8 | `docs/` – Terraform migration | No `terraform import` procedure for consolidating separate S3 and EC2 states into the composite `platform` state. |
| 9 | `infra/terraform/platform/versions.tf` | `required_version >= 1.6.0` but child module `ec2-airflow` requires `>= 1.8.0`. Floor inconsistency. |
| 10 | `dbt/profiles.yml.example` | Only password auth documented; key-pair auth (production-preferred) not shown. |

---

## Task 2 – Create `dbt/models/staging/sources.yml`

**File:** `dbt/models/staging/sources.yml` [NEW]

**What was done:**
Wrote a full dbt v2 sources declaration covering all 11 RAW tables:
`nurses`, `facilities`, `shifts`, `applications`, `assignments`,
`health_screenings`, `market_conditions`, `nurse_scores`,
`campaign_performance`, `app_events`, `manual_overrides`.

**Why this matters:**
Without this file dbt cannot resolve any `{{ source('raw', 'X') }}` Jinja reference.
Every staging model and mart would fail at `dbt compile` (credential-free step)
and `dbt build`. This was the highest-impact single fix in the audit.

**Errors encountered:** None – created fresh file.

---

## Task 3 – Improve `scripts/invoke_case_study_pipeline.ps1`

**File:** `scripts/invoke_case_study_pipeline.ps1` [MODIFIED]

**What was done:**

### Fivetran polling (`Invoke-FivetranSync`)
- Added `$missing` array that collects all absent env vars before throwing a
  single descriptive error (instead of the old implicit null-string error).
- Added POST call wrapped in `try/catch` with explicit error message.
- Added 30-minute polling loop (30-second intervals) querying
  `GET /v1/connectors/:id` and reading `status.sync_state`.
- Reports elapsed time and final state on every check.
- Throws FAIL on `broken`, `incomplete`, `paused` terminal states.
- Prints `[Fivetran] PASS` on `connected`.

### Hightouch polling (`Invoke-HightouchSync`)
- Same missing-var guard pattern.
- Captures `syncRequestId` from trigger response.
- Polls `GET /api/v1/syncs/:id/sync_requests` (30-minute timeout, 30-second interval).
- Throws FAIL on `failed`, `interrupted`, `cancelled`.
- Prints `[Hightouch] PASS` on `success`.

### SSM output (`Invoke-AirflowBatch`)
- Captures SSM command status and stdout/stderr via
  `get-command-invocation` query with `ConvertFrom-Json`.
- Prints `[Airflow] SSM status`, stdout, and stderr.
- Throws with status string in the error message.
- Prints `[Airflow] PASS` when DAG succeeds.

### General
- Added `Write-Host "[Pipeline] Starting …"` and `PASS` lines for
  each major step so the operator can see progress without reading AWS CLI output.

**Error encountered during implementation:**
```
ERROR: At scripts\invoke_case_study_pipeline.ps1:70 char:19
+   echo "  attempt $attempt: DAG state=$state"
Variable reference is not valid. ':' was not followed by a valid variable name character.
```
The PowerShell parser interpreted `$attempt:` (colon immediately after variable
name) inside the double-quoted here-string as an invalid scope modifier.

**Fix applied:**
Replaced `$attempt:` and `$state` with `${attempt}` and `${state}` in the
bash `echo` line inside the here-string. Bash interprets these identically;
PowerShell no longer flags the ambiguity.

---

## Task 4 – Create `tests/test_pipeline_contract.py`

**File:** `tests/test_pipeline_contract.py` [NEW]

**What was done:**
Added 28 total tests (14 existing + 14 new in this file → counted as 28 total).
Actually: 8 logical scenarios with multiple assertion methods = 14 new test methods:

| Test class | Test method | What it verifies |
|---|---|---|
| `InitialLoad500NursesTest` | `test_initial_load_produces_500_nurses` | Generator manifest shows exactly 500 nurse rows |
| `IncrementalLoad550NursesTest` | `test_incremental_load_produces_550_nurses` | Generator manifest shows exactly 550 nurse rows |
| `IncrementalLoad550NursesTest` | `test_incremental_nurses_have_distinct_ids` | All 550 nurse_ids are unique (no duplicates) |
| `UniqueBatchPathTest` | `test_same_day_runs_produce_unique_batch_ids` | Different run IDs → different batch IDs |
| `UniqueBatchPathTest` | `test_batch_id_embedded_in_object_key` | S3 object keys use Hive-style `source=`/`entity=`/`load_date=` partitions |
| `SnowflakeIdempotentLoadTest` | `test_load_sql_has_no_force_true` | `02_s3_stage_and_raw_load.sql` has no `FORCE = TRUE` |
| `SnowflakeIdempotentLoadTest` | `test_load_sql_uses_copy_into` | Load SQL contains `COPY INTO` statements |
| `DbtDeduplicationContractTest` | `test_qualify_row_number_present` | `stg_nurses.sql` uses `QUALIFY ROW_NUMBER()` |
| `DbtDeduplicationContractTest` | `test_partitioned_by_nurse_id` | Dedup window is `PARTITION BY nurse_id` |
| `DbtDeduplicationContractTest` | `test_orders_by_record_updated_at_desc` | Latest-record selection uses `ORDER BY record_updated_at DESC` |
| `DbtDeduplicationContractTest` | `test_sources_yml_declares_nurses_table` | `sources.yml` exists and declares `nurses` |
| `MissingEnvVarTest` | `test_pipeline_script_checks_fivetran_apikey` | Script checks all 3 Fivetran vars and uses `$missing` pattern |
| `MissingEnvVarTest` | `test_pipeline_script_checks_hightouch_api_key` | Script checks both Hightouch vars |
| `MissingEnvVarTest` | `test_run_snowflake_sql_raises_on_unresolved_token` | `run_snowflake_sql.py` raises `RuntimeError` on `__CAREMATCH_` tokens |

**Test run result:**
```
Ran 28 tests in 1.909s
OK
```
All 28 pass, including all 14 pre-existing tests.

**Errors encountered:** None.

---

## Task 5 – Harden `.gitignore`

**File:** `.gitignore` [MODIFIED]

**What was added:**
```
# Airflow local env file – never commit
airflow/.env

# Terraform variable overrides – account-specific values must not be committed.
terraform.tfvars
!terraform.tfvars.example

# dbt dependency lock written by dbt deps – not committed (reproducible from packages.yml)
dbt/packages.yml
```

**Why:**
- `airflow/.env` holds `AIRFLOW_FERNET_KEY`, `POSTGRES_PASSWORD`,
  `AIRFLOW_ADMIN_PASSWORD`, and `CAREMATCH_S3_BUCKET`. Committing it would
  expose credentials.
- `terraform.tfvars` files contain account-specific values and potentially
  sensitive connector IDs or ARNs. The `.example` files are safe to commit.
- `dbt/packages.yml` is generated by `dbt deps`; committing it would create
  diff noise and is redundant with `packages.yml` (the source of truth).

---

## Task 6 – Fix Terraform version floor

**File:** `infra/terraform/platform/versions.tf` [MODIFIED]

**Change:**
```diff
- required_version = ">= 1.6.0"
+ required_version = ">= 1.8.0"
```

**Why:**
The child module `ec2-airflow/versions.tf` already requires `>= 1.8.0`.
The composite platform module calling it must enforce at least the same floor,
otherwise Terraform can initialise with 1.6.x or 1.7.x and fail mid-apply
when the child module constraint is evaluated.

**Error encountered:**
After writing the file, `terraform fmt -check` reported `versions.tf` was
not correctly formatted (the PowerShell heredoc added a Windows-style trailing
blank line).

**Fix applied:**
Ran `terraform fmt infra/terraform/platform/versions.tf` to auto-format.
`terraform fmt -check -recursive infra/terraform` then exits 0.

---

## Task 7 – Create `docs/TERRAFORM_MIGRATION.md`

**File:** `docs/TERRAFORM_MIGRATION.md` [NEW]

**What was done:**
Wrote an 8-step safe migration guide:
1. Gather live resource IDs from existing state files.
2. Init platform root without backend.
3. Create local (untracked) `terraform.tfvars`.
4. Import S3 module resources (7 `terraform import` commands with exact addresses).
5. Import EC2 Airflow module resources (VPC, subnet, SG, IGW, route table, VPC endpoint, instance).
6. Final plan review – accept only in-place updates, reject any destroy/replace.
7. Apply only after a clean plan.
8. Archive (not delete) separate state files.

Documented the Fivetran connector (`prohibited_every`) import path as a separate
step after the primary migration.

**Errors encountered:** None.

---

## Task 8 – Update `docs/FULL_AUTOMATION_RUNBOOK.md`

**File:** `docs/FULL_AUTOMATION_RUNBOOK.md` [MODIFIED]

**What was added:**
- **Environment variables table** covering Snowflake (ACCOUNT, USER, ROLE,
  PRIVATE_KEY_FILE or PASSWORD) and SaaS (FIVETRAN_APIKEY, FIVETRAN_APISECRET,
  FIVETRAN_CONNECTOR_ID, HIGHTOUCH_API_KEY, HIGHTOUCH_SYNC_ID).
- **Script flags table** documenting all 11 parameters with defaults.
- **SaaS polling behaviour** section explaining the 30-minute polling loop,
  30-second intervals, and terminal states for both Fivetran and Hightouch.
- **Clarification** that `verify` mode is read-only (no writes to any system).
- **Cross-reference** to `TERRAFORM_MIGRATION.md`.

---

## Task 9 – Improve `dbt/profiles.yml.example`

**File:** `dbt/profiles.yml.example` [MODIFIED]

**What was added:**
A second output target `dev_keypair` demonstrating RSA key-pair authentication
using `private_key_path: "{{ env_var('SNOWFLAKE_PRIVATE_KEY_FILE') }}"`.
The password target is retained as the development fallback.
Both targets are annotated with comments explaining when to use each.

---

## Task 10 – Verification runs

### Unit tests
```
Ran 28 tests in 1.909s
OK
```

### PowerShell syntax check
```
PowerShell syntax: OK (0 parse errors)
```

### Terraform validate
```
Success! The configuration is valid.
```

### Terraform fmt
```
terraform fmt -check -recursive infra/terraform → exit 0
```

### Git status (pre-commit)
```
M  .gitignore
A  dbt/models/staging/sources.yml
M  dbt/profiles.yml.example
M  docs/FULL_AUTOMATION_RUNBOOK.md
A  docs/TERRAFORM_MIGRATION.md
M  infra/terraform/platform/versions.tf
M  scripts/invoke_case_study_pipeline.ps1
A  tests/test_pipeline_contract.py
```
No secrets, state files, private keys, dbt target output, or generated data staged.

---

## Unresolved live-service dependencies

The following items require live cloud credentials and cannot be verified
in a code-only session:

| Dependency | Why unresolved | How to verify |
|---|---|---|
| Airflow DAG execution | Requires AWS SSM access to EC2 `i-02bdd56e8690f35d1` | Run `-Mode initial` with valid AWS profile |
| Snowflake COPY INTO | Requires Snowflake credentials | Set `SNOWFLAKE_ACCOUNT`, `SNOWFLAKE_USER`, `SNOWFLAKE_PRIVATE_KEY_FILE` and run `-Mode initial` |
| dbt build | Requires Snowflake credentials via `profiles.yml` | `dbt build --project-dir dbt --profiles-dir dbt` with env vars set |
| Fivetran sync status | Requires `FIVETRAN_APIKEY`, `FIVETRAN_APISECRET`, `FIVETRAN_CONNECTOR_ID` | Run `-Mode initial -RunFivetran` |
| Hightouch sync status | Requires `HIGHTOUCH_API_KEY`, `HIGHTOUCH_SYNC_ID` | Run `-Mode initial -RunHightouch` |
| Terraform platform import | Requires AWS credentials and live resources to match state | Follow `docs/TERRAFORM_MIGRATION.md` |

---

## Files changed summary

| File | Change type | Purpose |
|---|---|---|
| `.gitignore` | Modified | Added `airflow/.env`, `terraform.tfvars`, `dbt/packages.yml` |
| `dbt/models/staging/sources.yml` | **New** | Declares all 11 RAW source tables for dbt |
| `dbt/profiles.yml.example` | Modified | Added key-pair auth target block |
| `docs/FULL_AUTOMATION_RUNBOOK.md` | Modified | Env vars, flags, SaaS polling, verify-mode note |
| `docs/TERRAFORM_MIGRATION.md` | **New** | Safe 8-step `terraform import` migration guide |
| `infra/terraform/platform/versions.tf` | Modified | Raised `required_version` from `>= 1.6.0` to `>= 1.8.0` |
| `scripts/invoke_case_study_pipeline.ps1` | Modified | Fivetran/Hightouch polling, SSM output capture, PASS/FAIL lines |
| `tests/test_pipeline_contract.py` | **New** | 14 credential-free contract tests |
| `WORKLOG.md` | **New** | This file – running log of all work done |
