variable "aws_region" {
  description = "AWS region containing the CareMatch S3 bucket."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used by Terraform."
  type        = string
  default     = "default"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "bucket_name" {
  description = "Existing S3 data-lake bucket Snowflake may read."
  type        = string
  default     = "carematch-data-237657481511-dev"
}

variable "role_name" {
  description = "IAM role assumed by the Snowflake storage integration."
  type        = string
  default     = "carematch-dev-snowflake-s3"
}

variable "snowflake_iam_user_arn" {
  description = "Snowflake-generated AWS IAM user ARN from DESC INTEGRATION."
  type        = string
}

variable "snowflake_external_id" {
  description = "Snowflake-generated external ID from DESC INTEGRATION."
  type        = string
  sensitive   = true
}
