# ╔══════════════════════════════════════════════════════════════════╗
# ║  AZURE CONTAINER REGISTRY                                        ║
# ║                                                                  ║
# ║  Production guardrails enforced at plan time by preconditions:   ║
# ║  • the admin user is refused for prod/uat/dr                     ║
# ║  • Premium-only features are refused on cheaper SKUs             ║
# ║  • a registry without a public endpoint must have a PE           ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_container_registry" "this" {
  name                = local.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku                           = var.sku
  admin_enabled                 = var.admin_enabled
  public_network_access_enabled = var.public_network_access_enabled
  network_rule_bypass_option    = var.network_rule_bypass_option

  # ─── PREMIUM POLICIES ───────────────────────────────────────────
  # These locals resolve to null when the flag is off, so Basic/Standard
  # registries never send premium-only attributes to the Azure API.
  anonymous_pull_enabled    = local.anonymous_pull_enabled
  data_endpoint_enabled     = local.data_endpoint_enabled
  quarantine_policy_enabled = local.quarantine_policy_enabled
  zone_redundancy_enabled   = local.zone_redundancy_enabled
  export_policy_enabled     = local.export_policy_enabled

  dynamic "retention_policy" {
    for_each = var.retention_policy == null ? [] : [var.retention_policy]
    content {
      enabled = retention_policy.value.enabled
      days    = retention_policy.value.days
    }
  }

  dynamic "trust_policy" {
    for_each = var.trust_policy_enabled ? [1] : []
    content {
      enabled = true
    }
  }

  dynamic "network_rule_set" {
    for_each = local.network_rule_set == null ? [] : [local.network_rule_set]
    content {
      default_action = network_rule_set.value.default_action

      dynamic "ip_rule" {
        for_each = toset(network_rule_set.value.ip_rules)
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }

  # Keys are locations, so Terraform's object iteration order gives the
  # alphabetical order the Azure API insists on.
  dynamic "georeplications" {
    for_each = local.georeplications
    content {
      location                  = georeplications.key
      zone_redundancy_enabled   = georeplications.value.zone_redundancy_enabled
      regional_endpoint_enabled = georeplications.value.regional_endpoint_enabled
    }
  }

  dynamic "identity" {
    for_each = local.identity_enabled ? [1] : []
    content {
      type         = local.identity_type
      identity_ids = length(var.user_assigned_identity_ids) > 0 ? var.user_assigned_identity_ids : null
    }
  }

  dynamic "encryption" {
    for_each = local.encryption_enabled ? [1] : []
    content {
      key_vault_key_id   = local.encryption_key_id
      identity_client_id = local.encryption_client_id
    }
  }

  tags = local.standard_tags

  # ─── GUARDRAILS (evaluated during plan) ─────────────────────────
  lifecycle {
    precondition {
      condition     = length(local.premium_only_violations) == 0
      error_message = "These features require sku = \"Premium\", but sku is \"${var.sku}\": ${join(", ", local.premium_only_violations)}. Change the SKU or disable the features."
    }

    precondition {
      condition     = !var.admin_enabled || !local.production_like
      error_message = "admin_enabled must be false for prod, uat and dr. Use registry tokens (var.tokens) or AcrPull/AcrPush role assignments instead of the shared admin account."
    }

    precondition {
      condition     = var.export_policy_enabled || !var.public_network_access_enabled
      error_message = "export_policy_enabled = false is only accepted by Azure when public_network_access_enabled = false."
    }

    precondition {
      condition     = !var.anonymous_pull_enabled || local.is_standard_up
      error_message = "anonymous_pull_enabled requires the Standard or Premium SKU."
    }

    precondition {
      condition     = var.public_network_access_enabled || local.private_endpoints_enabled
      error_message = "public_network_access_enabled = false with no private endpoints makes the registry unreachable. Declare at least one entry in var.private_endpoints."
    }

    precondition {
      condition     = !local.production_like || !var.enforce_private_endpoints_for_production || local.private_endpoints_enabled
      error_message = "prod/uat/dr registries must expose at least one private endpoint while enforce_private_endpoints_for_production = true. Add a var.private_endpoints entry or set the flag to false."
    }

    precondition {
      condition     = !local.encryption_enabled || (strcontains(var.managed_identity_type, "UserAssigned") && length(var.user_assigned_identity_ids) > 0 && try(local.encryption_client_id, "") != "")
      error_message = "encryption requires a user-assigned managed identity: managed_identity_type must include UserAssigned, user_assigned_identity_ids must contain that identity, and encryption.identity_client_id must be its client_id."
    }

    precondition {
      condition     = !local.encryption_enabled || alltrue([for id in var.user_assigned_identity_ids : can(regex("/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[^/]+$", id))])
      error_message = "every entry in user_assigned_identity_ids must be a user-assigned managed identity resource ID."
    }

    precondition {
      condition     = length(local.georeplications) == 0 || !contains(keys(local.georeplications), var.location)
      error_message = "georeplications must not contain the primary registry location (${var.location})."
    }

    precondition {
      condition     = can(regex("^[a-z0-9]{5,50}$", local.registry_name))
      error_message = "The resolved registry name \"${local.registry_name}\" is invalid: Azure requires 5-50 lowercase alphanumeric characters, no hyphens."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  PRIVATE ENDPOINTS  (Premium SKU, opt-in via var)                ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = each.value.subnet_id

  private_service_connection {
    name                           = "psc-${each.key}"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = each.value.subresource_names
  }

  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "pdzg-${each.key}"
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }

  tags = each.value.tags

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9-.]{1,80}$", each.value.name))
      error_message = "Private endpoint name \"${each.value.name}\" must be 1-80 characters of [a-zA-Z0-9-.]. Override it with private_endpoints[...].name."
    }

    precondition {
      condition     = can(regex("^/subscriptions/[0-9a-fA-F-]{36}/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", each.value.subnet_id))
      error_message = "private_endpoints[\"${each.key}\"].subnet_id must be a full subnet resource ID."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  SCOPE MAPS + TOKENS  (least privilege CI / runtime creds)       ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_container_registry_scope_map" "this" {
  for_each = local.tokens

  name                    = each.value.scope_map_name
  resource_group_name     = var.resource_group_name
  container_registry_name = azurerm_container_registry.this.name
  actions                 = each.value.actions
  description             = each.value.description

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9_-]{5,50}$", each.value.scope_map_name))
      error_message = "Scope map name \"${each.value.scope_map_name}\" must be 5-50 characters of [a-zA-Z0-9_-]."
    }

    precondition {
      condition     = length(each.value.actions) > 0 && alltrue([for action in each.value.actions : can(regex("^[a-zA-Z0-9*_/.-]+$", action))])
      error_message = "tokens[\"${each.key}\"].actions must be a non-empty list of ACR data-plane actions, e.g. \"repositories/foo/manifest/read\" or \"catalog\"."
    }
  }
}

resource "azurerm_container_registry_token" "this" {
  for_each = local.tokens

  name                    = each.value.token_name
  resource_group_name     = var.resource_group_name
  container_registry_name = azurerm_container_registry.this.name
  scope_map_id            = azurerm_container_registry_scope_map.this[each.key].id
  enabled                 = each.value.enabled

  lifecycle {
    precondition {
      condition     = can(regex("^[a-zA-Z0-9_-]{5,50}$", each.value.token_name))
      error_message = "Token name \"${each.value.token_name}\" must be 5-50 characters of [a-zA-Z0-9_-]."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  RBAC ON THE REGISTRY  (AcrPull / AcrPush ...)                   ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = azurerm_container_registry.this.id
  role_definition_name = try(each.value.role_definition_name, null)
  role_definition_id   = try(each.value.role_definition_id, null)
  principal_id         = each.value.principal_id
  principal_type       = try(each.value.principal_type, null)
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  DIAGNOSTIC SETTINGS                                             ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = local.diagnostics_enabled ? 1 : 0

  name                       = local.diagnostics_name
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = local.diagnostics_workspace_id

  dynamic "enabled_log" {
    for_each = toset(local.diagnostics_log_categories)
    content {
      category = enabled_log.value

      # Log retention is normally owned by the Log Analytics workspace, so a
      # retention policy is only written when a non-zero value is requested.
      dynamic "retention_policy" {
        for_each = local.diagnostics_retention_days > 0 ? [1] : []
        content {
          enabled = true
          days    = local.diagnostics_retention_days
        }
      }
    }
  }

  dynamic "metric" {
    for_each = toset(local.diagnostics_metric_categories)
    content {
      category = metric.value

      retention_policy {
        enabled = false
        days    = 0
      }
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  DELETION PROTECTION  (optional lock)                            ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_management_lock" "this" {
  count = local.lock_enabled ? 1 : 0

  name       = local.lock_name
  lock_level = local.lock_kind
  notes      = "Managed by Terraform (modules/acr). Remove the lock variable before deleting ${local.registry_name}."

  resource_name       = azurerm_container_registry.this.name
  resource_group_name = var.resource_group_name
  type                = "Microsoft.ContainerRegistry/registries"
}
