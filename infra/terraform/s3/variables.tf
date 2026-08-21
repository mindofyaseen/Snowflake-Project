variable "aws_region" {
  description = "AWS region for the S3 landing zone."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile. Credentials are never stored in Terraform."
  type        = string
  default     = "carematch-dev"
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

variable "project_name" {
  description = "Lowercase project name used in resource names."
  type        = string
  default     = "carematch-data"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name may contain lowercase letters, numbers, and hyphens only."
  }
}

variable "force_destroy" {
  description = "Permit bucket deletion when it contains objects. Keep false outside disposable tests."
  type        = bool
  default     = false
}

variable "raw_retention_days" {
  description = "Days to retain current raw objects before expiration."
  type        = number
  default     = 365

  validation {
    condition     = var.raw_retention_days >= 30
    error_message = "raw_retention_days must be at least 30."
  }
}
