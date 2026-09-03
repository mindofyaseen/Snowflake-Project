# ADR-0009: Terraform for Account-Portable Infrastructure as Code

## Status
Accepted

## Context
The platform infrastructure spans AWS S3, EC2, IAM roles, and Snowflake integrations. Deployments must be reproducible across
different AWS accounts and environments (dev, test, prod).

## Decision
Manage all AWS and composite platform resources via modular Terraform configurations under `infra/terraform/`.

## Benefits
- Infrastructure is version-controlled, auditable, and repeatable.
- Clear separation into reusable modules (`s3`, `ec2-airflow`, `snowflake-s3-integration`, `platform`).
- Scoped IAM policies adhere strictly to least-privilege principles.

## Drawbacks
- Requires Terraform CLI and state management.

## Risks
- State file exposure. Mitigated by strict `.gitignore` patterns preventing `.tfstate` commits.

## Alternatives Considered
- AWS CloudFormation / CDK: Less cloud-agnostic and more proprietary than Terraform.
- Manual AWS Console clicks: Unreproducible, error-prone, and unmaintainable.
