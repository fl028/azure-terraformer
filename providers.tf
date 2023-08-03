terraform {
  required_providers {
    azapi = {
      source = "Azure/azapi"
      version = "1.7.0"
    }
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.66.0"
    }
    random = {
      source = "hashicorp/random"
      version = "3.5.1"
    }
    local = {
      source = "hashicorp/local"
      version = "2.4.0"
    }
  }
}

provider "azapi" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  client_id       = var.client_id
  client_secret   = var.client_secret
}

provider "random" {
  # Configuration options
}

provider "local" {
  # Configuration options
}