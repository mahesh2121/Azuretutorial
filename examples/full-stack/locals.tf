# ╔══════════════════════════════════════════════════════════════════╗
# ║  SHARED NAMING / TAGGING FOR THE THREE MODULES                   ║
# ╚══════════════════════════════════════════════════════════════════╝

locals {
  region_short_codes = {
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "centralus"          = "cus"
    "southcentralus"     = "scus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "uksouth"            = "uks"
    "francecentral"      = "frc"
    "germanywestcentral" = "gwc"
    "swedencentral"      = "sec"
    "eastasia"           = "eas"
    "southeastasia"      = "sea"
    "japaneast"          = "jae"
    "australiaeast"      = "aus"
    "centralindia"       = "cen"
  }

  location_normalized = replace(var.location, " ", "")
  region_short = try(
    lookup(local.region_short_codes, local.location_normalized, substr(local.location_normalized, 0, 4)),
    local.location_normalized
  )

  resource_group_name = "rg-${var.organization}-${var.environment}-platform-${var.location}"
  network_name        = "vnet-${var.organization}-${var.environment}-${local.region_short}"
  identity_name       = "id-${var.organization}-${var.environment}-${var.app_name}-aci"
  workspace_name      = "law-${var.organization}-${var.environment}-${local.region_short}"

  production_like = contains(["prod", "uat", "dr"], lower(var.environment))

  standard_tags = merge(
    {
      Environment        = var.environment
      Organization       = var.organization
      Application        = var.app_name
      ManagedBy          = "Terraform"
      DataClassification = "Confidential"
      CostCenter         = var.environment == "prod" ? "platform-prod" : "platform-lab"
    },
    var.tags
  )

  # The registry SKU has to satisfy private link when it is switched on.
  effective_registry_sku = var.enable_private_link ? "Premium" : var.registry_sku

  image = "${module.acr.login_server}/${var.image_repository}:${var.image_tag}"

  # ACR access for the container host: prefer RBAC on a managed identity, and
  # only fall back to registry tokens where an identity cannot be attached.
  registry_server = module.acr.login_server

  private_endpoints = var.enable_private_link ? {
    registry = {
      subnet_id            = azurerm_subnet.private_endpoints[0].id
      private_dns_zone_ids = [azurerm_private_dns_zone.registry[0].id]
    }
  } : {}

  aci_subnet_ids = var.enable_private_link ? [azurerm_subnet.aci[0].id] : []

  # iOS delivery only lights up once every Apple artefact is available; the
  # hub keeps working through the FCM credential in the meantime.
  apns_complete = var.apns_key_id != null && var.apns_team_id != null && var.apns_private_key != null
}
