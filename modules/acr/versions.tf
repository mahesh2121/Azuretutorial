# ╔══════════════════════════════════════════════════════════════════╗
# ║  versions.tf                                                     ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Terraform & azurerm provider constraints for this module.       ║
# ╚══════════════════════════════════════════════════════════════════╝

terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.80.0, < 4.0.0"
    }
  }
}
