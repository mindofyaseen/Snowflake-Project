terraform {
  required_version = ">= 1.6.0"

  required_providers {
    fivetran = {
      source  = "fivetran/fivetran"
      version = "~> 1.9"
    }
  }
}
