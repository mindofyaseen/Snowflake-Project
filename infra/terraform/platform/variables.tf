variable "aws_profile" {
  description = "Named AWS CLI profile used by Terraform."
  type        = string
  default     = "carematch-dev"
}

variable "aws_region" {
  description = "AWS region for the platform."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "repository_url" {
  description = "Git repository cloned onto the Airflow host."
  type        = string
  default     = "https://github.com/mindofyaseen/intelycare-snowflake.git"
}

variable "repository_ref" {
  description = "Git branch or tag deployed to Airflow."
  type        = string
  default     = "main"
}

variable "airflow_instance_type" {
  description = "EC2 instance type for Airflow."
  type        = string
  default     = "t3.large"
}

variable "enable_snowflake_s3_trust" {
  description = "Create the Snowflake-to-S3 IAM trust after Snowflake supplies its IAM ARN and external ID."
  type        = bool
  default     = false
}

variable "snowflake_iam_user_arn" {
  description = "Value returned by DESC INTEGRATION for STORAGE_AWS_IAM_USER_ARN."
  type        = string
  default     = ""
}

variable "snowflake_external_id" {
  description = "Value returned by DESC INTEGRATION for STORAGE_AWS_EXTERNAL_ID."
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_fivetran_schedule" {
  description = "Adopt and manage an already-authorized Fivetran connector."
  type        = bool
  default     = false
}

variable "fivetran_connector_id" {
  description = "Authorized Fivetran connector ID."
  type        = string
  default     = ""
}

variable "fivetran_sync_frequency" {
  description = "Fivetran incremental sync frequency in minutes."
  type        = string
  default     = "360"
}

variable "pause_fivetran_after_trial" {
  description = "Pause the Fivetran connector when its trial expires."
  type        = bool
  default     = true
}

