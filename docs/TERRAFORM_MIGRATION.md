# Terraform state migration guide

The CareMatch platform was initially deployed using two independent Terraform roots:

- `infra/terraform/s3` – owns the S3 landing bucket and its security policies.
- `infra/terraform/ec2-airflow` – owns the VPC, EC2 instance, IAM roles, and SSM.

The composite `infra/terraform/platform` root composes these as child modules so
new accounts need only one `terraform apply`. This guide explains how to migrate
the **existing** live resources from the separate states into the composite state
without destroying or recreating any infrastructure.

> **Important** – Read this document completely before executing any command.
> Do not run `terraform apply` until you have verified that `terraform plan`
> shows only import operations and no replacements.

---

## Prerequisites

- Terraform >= 1.8.0 installed locally.
- AWS CLI profile `carematch-dev` or equivalent with read-only access to the
  account.
- Existing separate state files present:
  - `infra/terraform/s3/terraform.tfstate`
  - `infra/terraform/ec2-airflow/terraform.tfstate`
- No `terraform.tfvars` committed (use environment variables or a local,
  untracked `terraform.tfvars` file).

---

## Step 1 – Gather the live resource IDs

Read these values from the existing state files. Do not query the AWS API
directly; use `terraform output` from the child roots.

```powershell
# S3 bucket name
terraform -chdir=infra/terraform/s3 output -raw bucket_name
# Expected: carematch-data-237657481511-dev

# EC2 instance ID
terraform -chdir=infra/terraform/ec2-airflow output -raw instance_id
# Expected: i-02bdd56e8690f35d1
```

Collect any other resource IDs referenced in the state that the platform module
must own (VPC, subnets, IAM roles, etc.).

---

## Step 2 – Initialise the platform root without a backend

The composite root has not yet been applied in the target account. Initialise
it without applying:

```powershell
terraform -chdir=infra/terraform/platform init -backend=false
terraform -chdir=infra/terraform/platform validate
```

Resolve any validation errors before proceeding.

---

## Step 3 – Create a `terraform.tfvars` for the platform root (local, untracked)

Copy the example and fill in account-specific values. This file must NOT be
committed.

```powershell
Copy-Item infra/terraform/platform/terraform.tfvars.example `
         infra/terraform/platform/terraform.tfvars
```

Edit `infra/terraform/platform/terraform.tfvars`:

```hcl
aws_profile = "carematch-dev"
aws_region  = "us-east-1"
environment = "dev"

# Leave Snowflake trust and Fivetran schedule disabled during import.
enable_snowflake_s3_trust  = false
enable_fivetran_schedule   = false
```

---

## Step 4 – Import S3 module resources

The platform's S3 child module address prefix is `module.s3`.

```powershell
$bucket = "carematch-data-237657481511-dev"

terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket.landing               $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_ownership_controls.landing   $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_public_access_block.landing  $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_versioning.landing           $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_server_side_encryption_configuration.landing  $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_lifecycle_configuration.landing               $bucket
terraform -chdir=infra/terraform/platform import `
  module.s3.aws_s3_bucket_policy.landing                                $bucket
```

After all imports, verify:

```powershell
terraform -chdir=infra/terraform/platform plan
```

The plan must show **0 to add, 0 to change, 0 to destroy** for the S3 resources.
If any in-place updates appear, review the attribute diff and adjust the
`terraform.tfvars` to match the live configuration before continuing.

---

## Step 5 – Import EC2 Airflow module resources

The platform's Airflow child module address prefix is `module.airflow`.
Read the resource IDs from `infra/terraform/ec2-airflow/terraform.tfstate`
or from `terraform -chdir=infra/terraform/ec2-airflow output`.

```powershell
$instanceId = "i-02bdd56e8690f35d1"
$vpcId      = "vpc-06f2b35276e5960a6"
$subnetId   = "subnet-08db96d60aa233607"
$sgId       = "sg-065e44fa631d5df4c"
$igwId      = "<internet-gateway-id>"        # read from ec2-airflow state
$rtbId      = "<route-table-id>"             # read from ec2-airflow state
$endpointId = "vpce-06e7663082dc90b92"

terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_instance.airflow          $instanceId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_vpc.airflow               $vpcId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_subnet.public             $subnetId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_security_group.airflow    $sgId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_internet_gateway.airflow  $igwId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_route_table.public        $rtbId
terraform -chdir=infra/terraform/platform import `
  module.airflow.aws_vpc_endpoint.s3           $endpointId
# Import IAM resources (role, instance profile, policy attachments) similarly.
```

Run `terraform plan` after each batch of imports and confirm no destructive
changes appear.

---

## Step 6 – Final plan review

After all resources are imported:

```powershell
terraform -chdir=infra/terraform/platform plan -out=platform.tfplan
```

Review the output carefully. Accept only:

- `~ update in-place` for tag or minor metadata changes.
- No `- destroy` or `-/+ replace` operations.

If replacements appear, do not apply. Investigate the diff, add missing import
addresses, or adjust the module inputs to match the live configuration.

---

## Step 7 – Apply (guarded)

Only after a clean plan with no replacements:

```powershell
terraform -chdir=infra/terraform/platform apply platform.tfplan
```

Verify outputs match the pre-migration values:

```powershell
terraform -chdir=infra/terraform/platform output s3_bucket_name
terraform -chdir=infra/terraform/platform output airflow_instance_id
```

---

## Step 8 – Archive the separate state files

Once the platform state is the authoritative source:

1. Move (do not delete) `infra/terraform/s3/terraform.tfstate` and
   `infra/terraform/ec2-airflow/terraform.tfstate` to a backup location outside
   the repository.
2. Add a `README.md` note to the child roots explaining they are now managed
   by the composite platform root.
3. Do not commit the state files or their backups.

---

## Rollback

If the migration is abandoned after imports but before apply:

1. Delete the partially-built platform state file.
2. The child root state files remain untouched and are still authoritative.

---

## Notes

- The `snowflake-s3-integration` and `fivetran-schedule` modules have their own
  separate states. Import them into the platform root only after the S3 and
  EC2 modules are successfully migrated and verified.
- The Fivetran connector (`prohibited_every`) is not yet in any Terraform state.
  Import it into the platform root's `fivetran_schedule` module using:
  ```
  terraform -chdir=infra/terraform/platform import \
    module.fivetran_schedule[0].fivetran_connector_schedule.selected \
    prohibited_every
  ```
  Set `enable_fivetran_schedule = true` and provide `fivetran_connector_id`
  in `terraform.tfvars` before importing.
