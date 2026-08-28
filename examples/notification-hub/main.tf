# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE: NOTIFICATION HUBS ONLY - modules/notification-hub      ║
# ║                                                                  ║
# ║  One namespace (Service Bus backed, globally unique DNS name)    ║
# ║  with one hub per mobile app. Credentials are optional so the    ║
# ║  infrastructure can be applied before the Apple/Google paper-    ║
# ║  work is finished; the module then refuses a hub that has no     ║
# ║  usable credential.                                              ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.organization}-${var.environment}-notifications-${var.location}"
  location = var.location

  tags = merge(
    {
      Environment  = var.environment
      Organization = var.organization
      ManagedBy    = "Terraform"
      Service      = "NotificationHubs"
    },
    var.tags
  )
}

locals {
  apns_mode = var.environment == "prod" || var.environment == "uat" || var.environment == "dr" ? "Production" : "Sandbox"

  # The Apple credential only makes sense when all four pieces exist; the
  # module raises a clear error for a half-configured apns block.
  apns_complete = var.apns_key_id != null && var.apns_team_id != null && var.apns_private_key != null
}

module "notifications" {
  source = "../../modules/notification-hub"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  sku_name    = var.sku_name
  enabled     = true
  lock        = var.enable_lock ? { kind = "CanNotDelete" } : null

  hubs = {
    ios = {
      apns = local.apns_complete ? {
        bundle_id        = var.ios_bundle_id
        key_id           = var.apns_key_id
        team_id          = var.apns_team_id
        token            = var.apns_private_key
        application_mode = local.apns_mode
      } : null
      # Android delivery doubles as the fallback while APNs is not wired yet,
      # so the hub always has at least one usable credential.
      fcm_api_key            = var.fcm_api_key
      registration_ttl_seconds = 86400
    }

    android = {
      fcm_api_key              = var.fcm_api_key
      registration_ttl_seconds = 604800
    }
  }

  tags = var.tags
}
