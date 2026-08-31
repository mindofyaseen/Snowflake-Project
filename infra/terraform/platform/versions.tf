terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    fivetran = {
      source  = "fivetran/fivetran"
      version = "~> 1.9"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "carematch-snowflake"
      Environment = var.environment
      ManagedBy   = "terraform"
      DataClass   = "synthetic"
    }
  }
}

provider "fivetran" {
  # Credentials come only from FIVETRAN_APIKEY and FIVETRAN_APISECRET.
}
