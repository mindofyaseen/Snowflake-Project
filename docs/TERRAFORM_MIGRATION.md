# Terraform Platform State Migration Procedure

> **Status Notice:** This procedure document is designed for consolidating separate
> module states into the composite platform root. **This migration has NOT been
> executed live against AWS resources.** Do not execute `terraform apply` without
> verifying a clean plan showing zero resources destroyed.

---

## Overview

The CareMatch data platform was initially provisioned across separate Terraform roots:
- `infra/terraform/s3`: S3 landing bucket and security policies
- `infra/terraform/ec2-airflow`: VPC, subnets, EC2 instance, IAM roles, and VPC endpoints

The composite module at `infra/terraform/platform` references these as child modules:
`module.s3` and `module.airflow`.

This runbook specifies the safe, non-destructive migration procedure to import the
existing live resources into the unified platform state using `default` AWS profile.

---

## Safety Rules and Pre-flight Checks

1. **Explicit No-Destroy Safeguard:** Every plan must be evaluated with `terraform show`
   or visual inspection to ensure `0 to destroy` and `0 to replace`.
2. **State Backups First:** Never modify or run state commands without creating timestamped
   copies of all `.tfstate` files.
3. **No Whole-State Deletions on Rollback:** If an import fails or exhibits diffs, roll
   back using state backup restoration or targeted `terraform state rm`, never delete
   active state files.
4. **Read-Only Inspection:** Never run `terraform destroy` during migration.

---

## Step 1 - Backup Existing State Files

Before touching any state:

```powershell
$timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
Copy-Item "infra/terraform/s3/terraform.tfstate" "infra/terraform/s3/terraform.tfstate.backup.$timestamp"
Copy-Item "infra/terraform/ec2-airflow/terraform.tfstate" "infra/terraform/ec2-airflow/terraform.tfstate.backup.$timestamp"
```

Verify that backups exist and are non-empty before proceeding.

---

## Step 2 - Initialize Platform Root

Set environment variables and initialize platform working directory without connecting to backend:

```powershell
$env:AWS_PROFILE = "default"
$env:AWS_REGION = "us-east-1"
$env:TF_DATA_DIR = ".terraform-data-platform"

terraform -chdir=infra/terraform/platform init -backend=false
terraform -chdir=infra/terraform/platform validate
```

---

## Step 3 - Create Untracked Variables Configuration

Create a local, untracked `terraform.tfvars` file for the platform root:

```powershell
Copy-Item "infra/terraform/platform/terraform.tfvars.example" "infra/terraform/platform/terraform.tfvars"
```

Configure the variables to match the live infrastructure:

```hcl
aws_profile = "default"
aws_region  = "us-east-1"
environment = "dev"

enable_snowflake_s3_trust = false
enable_fivetran_schedule  = false
```

---

## Step 4 - Import S3 Resources (module.s3)

All resource addresses and IDs match the live state in `infra/terraform/s3/terraform.tfstate`:

```powershell
$bucket = "carematch-data-237657481511-dev"

terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_ownership_controls.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_public_access_block.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_versioning.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_server_side_encryption_configuration.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_lifecycle_configuration.landing $bucket
terraform -chdir=infra/terraform/platform import module.s3.aws_s3_bucket_policy.landing $bucket
```

---

## Step 5 - Import EC2 & Airflow Resources (module.airflow)

All resource addresses and IDs match the live state in `infra/terraform/ec2-airflow/terraform.tfstate`:

```powershell
# Networking
terraform -chdir=infra/terraform/platform import module.airflow.aws_vpc.airflow vpc-06f2b35276e5960a6
terraform -chdir=infra/terraform/platform import module.airflow.aws_subnet.public subnet-08db96d60aa233607
terraform -chdir=infra/terraform/platform import module.airflow.aws_internet_gateway.airflow igw-08fa38fbe5205d8b7
terraform -chdir=infra/terraform/platform import module.airflow.aws_route_table.public rtb-0af517f038b29e630
terraform -chdir=infra/terraform/platform import module.airflow.aws_route_table_association.public subnet-08db96d60aa233607/rtb-0af517f038b29e630
terraform -chdir=infra/terraform/platform import module.airflow.aws_security_group.airflow sg-065e44fa631d5df4c
terraform -chdir=infra/terraform/platform import module.airflow.aws_vpc_endpoint.s3 vpce-06e7663082dc90b92

# IAM Roles and Policies
terraform -chdir=infra/terraform/platform import module.airflow.aws_iam_role.airflow carematch-dev-airflow
terraform -chdir=infra/terraform/platform import module.airflow.aws_iam_instance_profile.airflow carematch-dev-airflow
terraform -chdir=infra/terraform/platform import module.airflow.aws_iam_role_policy.airflow_data carematch-dev-airflow:carematch-s3-and-bootstrap
terraform -chdir=infra/terraform/platform import module.airflow.aws_iam_role_policy_attachment.ssm_core carematch-dev-airflow/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Compute Instance
terraform -chdir=infra/terraform/platform import module.airflow.aws_instance.airflow i-02bdd56e8690f35d1
```

---

## Step 6 - Verification Plan with No-Destroy Enforcement

Generate an execution plan and inspect it:

```powershell
terraform -chdir=infra/terraform/platform plan -out=migration.tfplan
```

Evaluate the plan output:
- **Expected:** `Plan: 0 to add, 0 to change, 0 to destroy` (or only non-destructive in-place tag updates).
- **Strict Rule:** If the plan shows any resource `to destroy` or `to replace`, **DO NOT APPLY**. Abort and diagnose attribute mismatches.

---

## Step 7 - Controlled Apply

Only when Step 6 confirms zero destructive actions:

```powershell
terraform -chdir=infra/terraform/platform apply migration.tfplan
```

Verify outputs:

```powershell
terraform -chdir=infra/terraform/platform output s3_bucket_name
terraform -chdir=infra/terraform/platform output airflow_instance_id
```

---

## Safe Rollback Procedure

If the migration process encounters unexpected diffs or errors during import:

1. **Do NOT delete state files:** Deleting state files causes Terraform to lose awareness
   of managed infrastructure, potentially leading to abandoned resources or duplicate creations.
2. **Targeted State Removal:** If a single resource was imported incorrectly, remove only
   that address from the platform state:
   ```powershell
   terraform -chdir=infra/terraform/platform state rm <resource_address>
   ```
3. **Backup Restoration:** To return to the pre-migration baseline, restore the backed-up
   state files created in Step 1:
   ```powershell
   Copy-Item "infra/terraform/s3/terraform.tfstate.backup.$timestamp" "infra/terraform/s3/terraform.tfstate"
   Copy-Item "infra/terraform/ec2-airflow/terraform.tfstate.backup.$timestamp" "infra/terraform/ec2-airflow/terraform.tfstate"
   ```
   Remove any temporary platform state file generated during the failed trial.