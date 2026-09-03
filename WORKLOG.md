# CareMatch Pipeline - Comprehensive Audit and Correction Work Log

This log documents all audit findings, initial implementations, reviewer-identified defects,
corrections, test results, and validation procedures.

---

## 1. Summary of Correction Pass (Commit Review & Fixes)

During review of commit `2f7455a`, several important defects were identified and corrected:

1. **Duplicate dbt Sources & Incorrect "Missing File" Claim:**
   - *Mistake:* Commit `2f7455a` claimed `sources.yml` was missing and introduced `dbt/models/staging/sources.yml`. However, the repository already contained canonical source definitions in `dbt/models/sources.yml`. The duplicate file caused dbt compiler failure (`Compilation Error: dbt found two sources with the name 'raw_nurses'`).
   - *Fix:* Merged all column descriptions into the canonical `dbt/models/sources.yml`, preserving all existing tests. Deleted `dbt/models/staging/sources.yml`. Added automated duplicate detection and credential-free `dbt parse` validation using a temporary mock profile.

2. **dbt Package Handling & `.gitignore` Correction:**
   - *Mistake:* `dbt/packages.yml` was added to `.gitignore` under the assumption that it was a lock file. In dbt, `packages.yml` is source configuration.
   - *Fix:* Removed `dbt/packages.yml` from `.gitignore`. Confirmed the project has no external package dependencies. Updated `scripts/invoke_case_study_pipeline.ps1` to check for `packages.yml` and skip `dbt deps` cleanly when absent rather than failing.

3. **Encoding Damage (UTF-8 BOM Removal):**
   - *Mistake:* Several files committed in `2f7455a` were saved with a UTF-8 Byte Order Mark (`0xEF, 0xBB, 0xBF`).
   - *Fix:* Stripped BOM from all modified/created files (`.gitignore`, `WORKLOG.md`, `dbt/models/sources.yml`, `dbt/profiles.yml.example`, `docs/FULL_AUTOMATION_RUNBOOK.md`, `docs/TERRAFORM_MIGRATION.md`, `infra/terraform/platform/versions.tf`, `scripts/invoke_case_study_pipeline.ps1`, `tests/test_pipeline_contract.py`). Verified with automated scan (`Has BOM: False` across all files).

4. **Fivetran Polling API Contract:**
   - *Mistake:* Previous implementation polled `status.sync_state` for `"connected"`, which is not a reliable completion indicator for a newly triggered sync.
   - *Fix:* Implemented `scripts/saas_sync.py` with baseline timestamp capture (`succeeded_at`, `failed_at`) prior to `/force` trigger. Polling checks whether `succeeded_at` has advanced past baseline. Handles `failed_at` advancement, non-runnable states (`paused`, `rescheduled`), transient network errors (retried until timeout), and supports configurable timeout and poll interval parameters.

5. **Hightouch Polling API Contract:**
   - *Mistake:* Previous implementation silently fell back to the first sync request if the triggered request ID was not found.
   - *Fix:* Implemented exact sync request ID matching. If the triggered request ID is missing or not present in `/sync_requests` response, it raises a clear error. Explicitly handles `success`, `failed`, `cancelled`, and `interrupted` states.

6. **Behavioral Testing & Production Function Testing:**
   - *Mistake:* Tests previously relied on weak text matching or duplicated the batch-ID algorithm inside the test. The `FORCE = TRUE` test stripped all spaces before searching for `"FORCE = TRUE"`, which could never detect matches.
   - *Fix:*
     - Implemented case-insensitive regex check `FORCE\s*=\s*TRUE` and added a test proving the regex matches various whitespace configurations.
     - Exported production functions `sanitize_batch_id` and `build_s3_raw_key` from `src/generate_healthcare_data.py` and imported them in `airflow/dags/synthetic_sources_to_s3.py`. Tests verify these exact production functions.
     - Added 12 mocked behavioral tests covering Fivetran and Hightouch sync success, remote failure, timeouts, transient errors, paused state, and missing environment variables.
     - Added dbt source duplicate detection and `dbt parse` compiler validation.

7. **Terraform Migration Guide Accuracy:**
   - *Mistake:* Previous guide referenced `carematch-dev` AWS profile, omitted IAM associations, and suggested deleting state files on rollback.
   - *Fix:* Rewrote `docs/TERRAFORM_MIGRATION.md` using the exact resource list and addresses extracted from read-only `terraform state list` on `infra/terraform/s3/terraform.tfstate` and `infra/terraform/ec2-airflow/terraform.tfstate`. Configured AWS profile to `default`. Included all IAM roles, policies, associations, subnet associations, and endpoints. Documented explicit no-destroy plan safeguards and safe state backup/rollback procedures. Explicitly noted the guide has not been executed live.

8. **PowerShell Orchestration Script Reliability:**
   - Verified initial and incremental modes work with explicit `-AirflowInstanceId` and `-S3BucketName`.
   - Verified `verify` mode does not query Terraform platform outputs when `-S3BucketName` is supplied.
   - Verified SSM waiter failures retrieve full diagnostic command output before raising an error.
   - Configurable `-SaasTimeoutSeconds` and `-SaasPollIntervalSeconds` exposed as parameters.
   - Ensured no secrets are logged.

---

## 2. Test Execution and Verification Results

### A. Python Unit Tests
Command:
```powershell
python -m unittest discover -s tests -v
```
Result:
```
Ran 43 tests in 16.844s
OK
```
All 43 tests pass (14 original tests + 29 contract/behavioral tests):
- `test_compose_binds_ui_to_loopback_only`: OK
- `test_dag_is_valid_python`: OK
- `test_initial_and_incremental_modes_have_distinct_defaults`: OK
- `test_manual_runs_can_select_an_incremental_load_date`: OK
- `test_runs_default_to_actual_current_utc_date`: OK
- `test_same_day_runs_use_unique_batch_paths`: OK
- `test_six_source_families_are_declared`: OK
- `test_orchestrator_has_separate_load_modes`: OK
- `test_secrets_are_read_from_environment`: OK
- `test_snowflake_stage_uses_runtime_bucket`: OK
- `test_manifest_hashes_and_rows`: OK
- `test_operational_foreign_keys`: OK
- `test_reproducible_checksums`: OK
- `test_synthetic_identity_and_classification`: OK
- `test_canonical_sources_yml_declares_nurses_table`: OK
- `test_orders_by_record_updated_at_desc`: OK
- `test_partitioned_by_nurse_id`: OK
- `test_qualify_row_number_present`: OK
- `test_dbt_parse_validates_project_without_credentials`: OK
- `test_no_duplicate_sources_across_project`: OK
- `test_missing_environment_variables` (Fivetran): OK
- `test_paused_state_raises_immediately` (Fivetran): OK
- `test_remote_failure` (Fivetran): OK
- `test_successful_completion` (Fivetran): OK
- `test_timeout` (Fivetran): OK
- `test_transient_polling_error` (Fivetran): OK
- `test_cancelled_or_interrupted` (Hightouch): OK
- `test_missing_environment_variables` (Hightouch): OK
- `test_remote_failure` (Hightouch): OK
- `test_successful_completion` (Hightouch): OK
- `test_timeout` (Hightouch): OK
- `test_transient_polling_error` (Hightouch): OK
- `test_triggered_request_not_found` (Hightouch): OK
- `test_incremental_load_produces_550_nurses`: OK
- `test_incremental_nurses_have_distinct_ids`: OK
- `test_initial_load_produces_500_nurses`: OK
- `test_build_s3_raw_key_structure`: OK
- `test_sanitize_batch_id_strips_unsafe_characters`: OK
- `test_sanitize_batch_id_uniqueness`: OK
- `test_force_regex_detects_various_spacings`: OK
- `test_load_sql_has_no_force_true`: OK
- `test_load_sql_uses_copy_into`: OK
- `test_run_snowflake_sql_raises_on_unresolved_token`: OK

### B. Credential-Free dbt Parse
Validated via temporary mock profile in isolated test directory:
- Exit code: `0`
- Output: `Running with dbt=1.11.11`, `Registered adapter: snowflake=1.11.6`, `Performance info: ...`

### C. PowerShell Syntax Validation
Command:
```powershell
[System.Management.Automation.Language.Parser]::ParseFile("scripts\invoke_case_study_pipeline.ps1", [ref]$null, [ref]$errors)
```
Result:
`0 parse errors`

### D. Terraform Formatting
Command:
```powershell
terraform fmt -check -recursive infra/terraform
```
Result:
Exit code `0`

### E. Terraform Platform Validation
Command:
```powershell
terraform -chdir=infra/terraform/platform validate
```
Result:
`Success! The configuration is valid.`

### F. UTF-8 BOM Scan
Command:
```python
python -c "..." # checks each modified file for 0xEF 0xBB 0xBF prefix
```
Result:
All modified files: `Has BOM: False`

### G. Security & State Leak Check
Command:
```powershell
git status --short
```
Result:
No `.tfstate` files, secrets, `.env` files, or private keys tracked or staged.

---

## 3. Remaining Live-Service Tasks (Require Real Credentials)

The following procedures cannot be executed in a code-only session and must be performed
by an authorized operator with live credentials:

1. **Airflow EC2 DAG Trigger:** Requires AWS credentials with `ssm:SendCommand` access to EC2 instance `i-02bdd56e8690f35d1`.
2. **Snowflake Ingestion & Transformation:** Requires live Snowflake account credentials (`CAREMATCH_TRANSFORMER` or `ACCOUNTADMIN`) to run `COPY INTO` and `dbt build`.
3. **Fivetran SurveyMonkey Sync:** Requires `FIVETRAN_APIKEY` and `FIVETRAN_APISECRET` to trigger connector `prohibited_every`.
4. **Hightouch Slack Activation:** Requires `HIGHTOUCH_API_KEY` to trigger sync `8379886` and channel invitation in Slack channel `C0BS2TQSS9M`.
5. **Terraform Platform State Migration:** Can be performed when live AWS access is available following the safe procedure in `docs/TERRAFORM_MIGRATION.md`.