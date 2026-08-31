# Fivetran connector schedule

This stack adopts an existing authenticated Fivetran connector and controls its
schedule. OAuth authorization remains an account-owner action, so it is not stored
in Terraform. The connector ID is the only account-specific input.

Set provider credentials only in the current process:

```powershell
$env:FIVETRAN_APIKEY = Read-Host "Fivetran API key"
$env:FIVETRAN_APISECRET = Read-Host "Fivetran API secret" -MaskInput
```

Copy `terraform.tfvars.example` to an untracked `terraform.tfvars`, replace the
connector ID, then run:

```powershell
terraform init
terraform plan
terraform apply
```

`pause_after_trial` defaults to `true`. This makes a development connector stop
automatically at the end of its free trial instead of silently continuing into
billable usage.

For a new Fivetran account:

1. Run the Snowflake service bootstrap and create the Fivetran Snowflake destination.
2. Create the SurveyMonkey connector and complete OAuth in the browser.
3. Put the new connector ID in this stack.
4. Apply Terraform to enforce the sync interval and trial guardrail.

Remove the two Fivetran environment variables after use.
