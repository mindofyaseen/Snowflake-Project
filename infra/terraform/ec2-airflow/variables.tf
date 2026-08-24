variable "aws_region" {
  description = "AWS region containing the S3 bucket and EC2 instance."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used only by Terraform. EC2 uses its IAM role."
  type        = string
  default     = "carematch-dev"
}

variable "environment" {
  description = "Short environment name."
  type        = string
  default     = "dev"
}

variable "s3_bucket_name" {
  description = "Existing private landing bucket created by the S3 Terraform stack."
  type        = string
}

variable "instance_type" {
  description = "Airflow host size. t3.large provides 8 GiB for the small Docker Compose stack."
  type        = string
  default     = "t3.large"
}

variable "root_volume_gib" {
  description = "Encrypted gp3 root volume size."
  type        = number
  default     = 30
}

variable "repository_url" {
  description = "Public Git repository cloned by cloud-init."
  type        = string
  default     = "https://github.com/mindofyaseen/intelycare-snowflake.git"
}

variable "repository_ref" {
  description = "Git branch or tag deployed to EC2."
  type        = string
  default     = "main"
}

