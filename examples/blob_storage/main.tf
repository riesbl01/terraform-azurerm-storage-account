terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.53.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=2.3.0"
    }
  }
  required_version = ">=0.14.8"
}

provider "azurerm" {
  features {}
}

data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"
}

data "azurerm_subscription" "current" {
}

resource "random_string" "random" {
  length  = 12
  upper   = false
  special = false
}

module "subscription" {
  source          = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = data.azurerm_subscription.current.subscription_id
}

module "naming" {
  source = "git@github.com:Azure-Terraform/example-naming-template.git?ref=v1.0.0"
}

module "metadata" {
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.1.0"

  naming_rules = module.naming.yaml

  market              = "us"
  project             = "https://github.com/Azure-Terraform/terraform-azurerm-storage-account/tree/main/example"
  location            = "eastus2"
  environment         = "sandbox"
  product_name        = random_string.random.result
  business_unit       = "infra"
  product_group       = "contoso"
  subscription_id     = module.subscription.output.subscription_id
  subscription_type   = "dev"
  resource_group_type = "app"
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v1.0.0"

  location = module.metadata.location
  names    = module.metadata.names
  tags     = module.metadata.tags
}

module "virtual_network" {
  source = "github.com/Azure-Terraform/terraform-azurerm-virtual-network.git?ref=v2.6.0"

  naming_rules = module.naming.yaml

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  names               = module.metadata.names
  tags                = module.metadata.tags

  address_space = ["10.1.1.0/24"]

  subnets = {
    iaas-outbound = {
      cidrs                                          = ["10.1.1.0/27"]
      service_endpoints                              = ["Microsoft.Storage"]
      enforce_private_link_endpoint_network_policies = true
    }
  }
}

module "storage_account" {
  source = "../../"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  names               = module.metadata.names
  tags                = module.metadata.tags

  account_kind     = "StorageV2"
  replication_type = "LRS"

  blob_cors = {
    test = {
      allowed_headers    = []
      allowed_methods    = ["GET", "DELETE"]
      allowed_origins    = ["*"]
      exposed_headers    = []
      max_age_in_seconds = 5
    }
  }

  private_link = {
    subnet_name   = module.virtual_network.subnets["iaas-outbound"].name
    vnet_name     = module.virtual_network.vnet.name
    dns_zone_name = "example.blob.storageaccount.privatelink.azure.com"
  }
}
