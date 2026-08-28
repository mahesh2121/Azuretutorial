# ╔══════════════════════════════════════════════════════════════════╗
# ║  AZURE CONTAINER INSTANCES (ACI)                                 ║
# ║                                                                  ║
# ║  One `azurerm_container_group` per entry in var.container_groups ║
# ║  with production wiring: private IP in a delegated subnet,       ║
# ║  managed identity image pulls, probes, init containers, volumes  ║
# ║  and Log Analytics.                                              ║
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
