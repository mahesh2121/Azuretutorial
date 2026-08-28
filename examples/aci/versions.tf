# ╔══════════════════════════════════════════════════════════════════╗
# ║  versions.tf                                                     ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Required providers and Terraform / azurerm version pins.        ║
# ╚══════════════════════════════════════════════════════════════════╝

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0, < 4.0.0"
    }
  }

  # State location. For real teams switch this to azurerm and point it at a
  # storage account + container that is created by the Key Vault stack.
  backend "local" {
    path = "terraform.tfstate"
  }
}
