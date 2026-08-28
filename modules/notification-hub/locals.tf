# ╔══════════════════════════════════════════════════════════════════╗
# ║  LOCALS - NAMESPACES, HUB NAMES AND GUARDRAIL FACTS              ║
# ╚══════════════════════════════════════════════════════════════════╝

locals {
  # ─── REGION SHORT CODES (shared convention across this repo) ────
  region_short_codes = {
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "centralus"          = "cus"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "canadacentral"      = "caca"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "francecentral"      = "frc"
    "germanywestcentral" = "gwc"
    "switzerlandnorth"   = "swn"
    "swedencentral"      = "sec"
    "uaenorth"           = "uane"
    "southafricanorth"   = "safa"
    "eastasia"           = "eas"
    "southeastasia"      = "sea"
    "japaneast"          = "jae"
    "japanwest"          = "jaw"
    "koreacentral"       = "koc"
    "australiaeast"      = "aus"
    "centralindia"       = "cen"
  }

  location_normalized = replace(var.location, " ", "")
  region_short = try(
    lookup(local.region_short_codes, local.location_normalized, substr(local.location_normalized, 0, 4)),
    local.location_normalized
  )

  instance_suffix = format("%03d", var.instance_number)

  # Namespace names become part of a public DNS name
  # (<name>.servicebus.windows.net), so they must be globally unique.
  namespace_name    = coalesce(try(var.namespace_name, null), "ns-${var.organization}-${var.environment}-${local.region_short}${local.instance_suffix}")
  namespace_dns_name = "${local.namespace_name}.servicebus.windows.net"
  hub_name_prefix   = coalesce(try(var.hub_name_prefix, null), "nh-${var.organization}-${var.environment}")

  production_like = contains(["prod", "uat", "dr"], lower(var.environment))

  standard_tags = merge(
    {
      Environment        = var.environment
      Organization       = var.organization
      Service            = "NotificationHubs"
      ManagedBy          = "Terraform"
      Module             = "azure-notification-hub"
      NamespaceSku       = var.sku_name
      DataClassification = "Confidential"
    },
    var.tags
  )

  # ─── HUBS ─────────────────────────────────────────────────────────
  # `registration_ttl_seconds` is intentionally surfaced as a tag: the
  # `registration_ttl` argument was removed from azurerm_notification_hub in
  # v3.x, so the value is kept for audit instead of being silently dropped.
  hubs = {
    for key, hub in var.hubs : key => {
      key           = key
      name          = coalesce(try(hub.name, null), "${local.hub_name_prefix}-${key}")
      bundle_id     = try(hub.apns.bundle_id, null)
      apns_key_id   = try(hub.apns.key_id, null)
      apns_team_id  = try(hub.apns.team_id, null)
      apns_token    = try(hub.apns.token, null)
      apns_mode     = coalesce(try(hub.apns.application_mode, null), "Sandbox")
      apns_declared = try(hub.apns, null) != null
      apns_ready = (
        try(hub.apns, null) != null
        && try(hub.apns.token, null) != null
        && try(hub.apns.key_id, null) != null
        && try(hub.apns.team_id, null) != null
        && try(hub.apns.bundle_id, null) != null
      )
      fcm_api_key   = try(hub.fcm_api_key, null)
      fcm_ready     = try(hub.fcm_api_key, null) != null
      registration_ttl_seconds = try(hub.registration_ttl_seconds, null)
      tags = merge(
        local.standard_tags,
        coalesce(try(hub.tags, null), {}),
        {
          PushPlatform  = join("+", compact([try(hub.apns, null) != null ? "APNs" : "", try(hub.fcm_api_key, null) != null ? "FCM" : ""]))
          ApnsMode      = try(hub.apns, null) != null ? coalesce(try(hub.apns.application_mode, null), "Sandbox") : "n/a"
          RegistrationTtl = try(hub.registration_ttl_seconds, null) == null ? "default" : tostring(hub.registration_ttl_seconds)
        }
      )
    }
  }

  hub_keys                 = keys(local.hubs)
  hubs_without_credentials = [for key, hub in local.hubs : key if !hub.apns_ready && !hub.fcm_ready]
  hubs_in_sandbox          = [for key, hub in local.hubs : key if hub.apns_declared && hub.apns_mode == "Sandbox"]
  apns_incomplete_hubs     = [for key, hub in local.hubs : key if hub.apns_declared && !hub.apns_ready]

  # ─── LOCK ─────────────────────────────────────────────────────────
  lock_enabled = var.lock != null
  lock_kind    = try(var.lock.kind, "CanNotDelete")
  lock_name    = var.lock == null ? null : coalesce(var.lock.name, "lock-${local.namespace_name}")
}
