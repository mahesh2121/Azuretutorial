# ╔══════════════════════════════════════════════════════════════════╗
# ║  NAMESPACE (SHARED, ONE PER APP)                                 ║
# ║                                                                  ║
# ║  Guardrails:                                                     ║
# ║  • the Free tier is refused outside dev/staging                  ║
# ║  • a namespace may never be disabled in prod/uat/dr              ║
# ║  • hubs must carry at least one usable platform credential       ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_notification_hub_namespace" "this" {
  name                = local.namespace_name
  resource_group_name = var.resource_group_name
  location            = var.location

  # The API only accepts this value for notification hubs; pinning it keeps
  # copy/pasted Service Bus examples from producing a broken namespace.
  namespace_type = "NotificationHub"
  sku_name       = var.sku_name
  enabled        = var.enabled

  tags = local.standard_tags

  lifecycle {
    precondition {
      condition     = var.sku_name == "Free" ? !local.production_like : true
      error_message = "sku_name = \"Free\" is not allowed for prod, uat or dr: it caps traffic at 1M notifications/month, has no SLA and only supports a single hub. Use Standard."
    }

    precondition {
      condition     = var.enabled || !local.production_like
      error_message = "enabled = false suspends every hub in this namespace and is refused for prod, uat and dr."
    }

    precondition {
      condition     = length(regexall("^[a-zA-Z0-9][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$", local.namespace_name)) > 0
      error_message = "The resolved namespace name \"${local.namespace_name}\" is invalid: 6-50 characters of [a-zA-Z0-9-], not starting or ending with a hyphen. Namespace names are globally unique because they form ${local.namespace_dns_name}."
    }

    precondition {
      condition     = length(local.hubs) > 0
      error_message = "At least one hub must be declared; a namespace without hubs is billed idle."
    }

    # Free/Basic limit the number of hubs inside a namespace.
    precondition {
      condition = (
        var.sku_name == "Standard"
        || (var.sku_name == "Free" && length(local.hub_keys) <= 1)
        || (var.sku_name == "Basic" && length(local.hub_keys) <= 10)
      )
      error_message = "Hub count exceeds the namespace tier limit: Free allows 1 hub, Basic 10, Standard 10. Current: ${length(local.hub_keys)} hub(s) on ${var.sku_name}."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  THE HUBS                                                        ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_notification_hub" "this" {
  for_each = local.hubs

  name                = each.value.name
  namespace_name      = azurerm_notification_hub_namespace.this.name
  resource_group_name = var.resource_group_name
  location            = var.location

  # Apple (iOS / macOS) - token based (.p8) authentication, the only mode
  # Azure still accepts (certificate based `apns_certificate` was removed).
  dynamic "apns_credential" {
    for_each = each.value.apns_ready ? [1] : []
    content {
      application_mode = each.value.apns_mode
      bundle_id        = each.value.bundle_id
      key_id           = each.value.apns_key_id
      team_id          = each.value.apns_team_id
      token            = each.value.apns_token
    }
  }

  # Google / Android (FCM legacy server key accepted by Notification Hubs).
  dynamic "gcm_credential" {
    for_each = each.value.fcm_ready ? [1] : []
    content {
      api_key = each.value.fcm_api_key
    }
  }

  tags = each.value.tags

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,258}[a-zA-Z0-9._:-]?$", each.value.name))
      error_message = "Hub name \"${each.value.name}\" must be 1-260 characters of [a-zA-Z0-9._:-] and may not start with a hyphen."
    }

    # A hub with no platform credential can register devices but can never
    # deliver - surface that at plan time instead of in production.
    precondition {
      condition     = each.value.apns_ready || each.value.fcm_ready
      error_message = "hubs[\"${each.key}\"] has no usable platform credential: provide a complete apns block (bundle_id, key_id, team_id, token) or fcm_api_key."
    }

    precondition {
      condition     = !each.value.apns_declared || each.value.apns_ready
      error_message = "hubs[\"${each.key}\"]: the apns block is incomplete - bundle_id, key_id, team_id and token are all required by Azure."
    }

    precondition {
      condition     = each.value.apns_mode == "Production" || !local.production_like || var.allow_sandbox_apns_in_production
      error_message = "hubs[\"${each.key}\"]: apns.application_mode = \"Sandbox\" only delivers to development builds; use \"Production\" in prod/uat/dr (or set allow_sandbox_apns_in_production = true)."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  DELETION PROTECTION  (namespace level)                          ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_management_lock" "this" {
  count = local.lock_enabled ? 1 : 0

  name       = local.lock_name
  lock_level = local.lock_kind
  notes      = "Managed by Terraform (modules/notification-hub). Remove the lock variable before deleting ${local.namespace_name}."

  resource_name       = azurerm_notification_hub_namespace.this.name
  resource_group_name = var.resource_group_name
  type                = "Microsoft.NotificationHubs/namespaces"
}
