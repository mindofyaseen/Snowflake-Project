# AWS access setup for the S3 milestone

Do not send AWS credentials through chat, email, GitHub, source files, screenshots, or issue comments.

## Preferred: IAM Identity Center or assumable role

Create a deployment identity that can obtain temporary credentials and attach the policy in:

```text
infra/iam/carematch-s3-bootstrap-policy.json
```

Suggested role name:

```text
CareMatchS3BootstrapRole
```

Configure the local profile using your organization's IAM Identity Center process and name the profile:

```text
carematch-dev
```

## Fallback: dedicated IAM user

If a role is not possible for this proof of concept, create a dedicated user:

```text
carematch-terraform-s3
```

Requirements:

- No AWS Console password unless a human must use the console.
- No AdministratorAccess policy.
- Attach only the supplied S3 bootstrap policy.
- Create one access key for the local deployment profile.
- Rotate or delete the key after replacing it with a role.

On the local machine, configure the profile yourself so the secret is entered directly into AWS CLI and is not exposed to project tooling:

```powershell
aws configure --profile carematch-dev
```

Enter:

```text
AWS Access Key ID: <enter locally>
AWS Secret Access Key: <enter locally>
Default region name: us-east-1
Default output format: json
```

Verify without revealing secrets:

```powershell
aws sts get-caller-identity --profile carematch-dev
```

The safe information to share after verification is:

- AWS account ID
- IAM user or role ARN
- Region
- Output of `aws sts get-caller-identity` with no credentials included

## Deploy the first milestone

After the profile works:

```powershell
.\scripts\deploy_s3.ps1 -AwsProfile carematch-dev -Region us-east-1 -Environment dev
```

The script will:

1. Generate the deterministic local dataset.
2. Run integrity tests.
3. Initialize and validate Terraform.
4. Create the private, encrypted, versioned S3 bucket.
5. Upload source files under `raw/`.
6. Upload and verify `raw/manifest.json`.

## Expected bucket name

```text
carematch-data-<AWS_ACCOUNT_ID>-dev
```

Public access remains blocked. TLS is required. Current objects use S3-managed server-side encryption and versioning.
