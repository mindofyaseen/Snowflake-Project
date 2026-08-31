terraform {
  required_version = ">= 1.6.0"

  required_providers {
    fivetran = {
      source  = "fivetran/fivetran"
      version = "~> 1.9"
    }
  }
}

provider "fivetran" {
  # Set FIVETRAN_APIKEY and FIVETRAN_APISECRET in the process environment.
  # Provider credentials are deliberately never written to tfvars or state.
}
