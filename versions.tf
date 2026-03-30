terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }
  }

  # Supply values at init time, e.g.:
  #   terraform init -backend-config=config/dev.backend.hcl
  # See config/*.backend.hcl.example and repository secrets for CI.
  backend "azurerm" {
    resource_group_name  = "rg-cc-infocomp-state-eus-01"
    storage_account_name = "tfstatedeveus"
    container_name       = "tfstate-container-dev"
    key                  = "infocomp/dev/terraform.tfstate"
    # Use managed identity or service principal if not using access keys
  }

}
