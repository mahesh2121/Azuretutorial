# ╔══════════════════════════════════════════════════════════════════╗
# ║  AZURE NOTIFICATION HUBS                                         ║
# ║                                                                  ║
# ║  One shared namespace + one hub per entry in var.hubs, with      ║
# ║  token based APNs and FCM/Google credentials and SKU guardrails  ║
# ║  that keep the Free tier out of production.                      ║
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
