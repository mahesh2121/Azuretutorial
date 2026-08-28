# ╔══════════════════════════════════════════════════════════════════╗
# ║  providers.tf                                                    ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Provider configuration for the root (example) module.           ║
# ╚══════════════════════════════════════════════════════════════════╝

provider "azurerm" {
  features {}

  # Registration is done once per subscription by the platform team; skipping
  # the check keeps `terraform plan` fast and offline-friendly.
  skip_provider_registration = true
}
