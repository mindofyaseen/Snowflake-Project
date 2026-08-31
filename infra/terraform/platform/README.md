# Composite CareMatch platform

This root stack composes the S3, EC2 Airflow, optional Snowflake IAM trust, and
optional Fivetran schedule modules. It is the portable infrastructure entry point
for a new development account.

OAuth is intentionally outside Terraform. Authorize SurveyMonkey in Fivetran and
Slack in Hightouch once, then provide only connector IDs and API credentials to
automation. Secrets belong in environment variables or an approved secret store,
never in `terraform.tfvars` or Terraform state.

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

Use `scripts/invoke_case_study_pipeline.ps1` after provisioning. Its `initial`
mode creates the baseline batch; `incremental` creates a later batch with a larger
nurse population and triggers downstream processing.

