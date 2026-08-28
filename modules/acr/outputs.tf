# ╔══════════════════════════════════════════════════════════════════╗
# ║  REGISTRY CORE                                                   ║
# ╚══════════════════════════════════════════════════════════════════╝

output "resource_id" {
  description = "Full resource ID of the container registry."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Name of the container registry (the value actually used by Azure)."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Registry login server, e.g. `myregistry.azurecr.io`. Use it as the image prefix."
  value       = azurerm_container_registry.this.login_server
}

output "sku" {
  description = "SKU the registry was created with."
  value       = azurerm_container_registry.this.sku
}

output "resource" {
  description = "Curated registry attributes for callers that need more than the individual outputs (never contains credentials)."
  value = {
    id                    = azurerm_container_registry.this.id
    name                  = azurerm_container_registry.this.name
    login_server          = azurerm_container_registry.this.login_server
    resource_group_name   = var.resource_group_name
    location              = azurerm_container_registry.this.location
    sku                   = azurerm_container_registry.this.sku
    admin_enabled         = var.admin_enabled
    public_network_access = var.public_network_access_enabled
    georeplications       = keys(local.georeplications)
    tags                  = local.standard_tags
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  ADMIN CREDENTIALS                                               ║
# ╚════════════════════════════════════════════════════════════════╝

output "admin_username" {
  description = "Admin username. Only populated when admin_enabled = true; discouraged in production."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_username : null
  sensitive   = true
}

output "admin_password" {
  description = "Admin password. Only populated when admin_enabled = true; discouraged in production."
  value       = var.admin_enabled ? azurerm_container_registry.this.admin_password : null
  sensitive   = true
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  IDENTITY                                                        ║
# ╚════════════════════════════════════════════════════════════════╝

output "identity_principal_id" {
  description = "System-assigned managed identity principal (object) ID, or null when no system-assigned identity exists."
  value = (
    strcontains(var.managed_identity_type, "SystemAssigned")
    ? try(azurerm_container_registry.this.identity[0].principal_id, null)
    : null
  )
}

output "identity_tenant_id" {
  description = "Tenant ID of the system-assigned managed identity, or null when no system-assigned identity exists."
  value = (
    strcontains(var.managed_identity_type, "SystemAssigned")
    ? try(azurerm_container_registry.this.identity[0].tenant_id, null)
    : null
  )
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  TOKENS & SCOPE MAPS                                             ║
# ╚════════════════════════════════════════════════════════════════╝

output "tokens" {
  description = <<-EOT
    Map of token key to the created token/scope map IDs.
    Rotate the password out of band (never in state):
      az acr credential show -g <rg> -n <registry> --username <token>
  EOT
  value = {
    for key, token in azurerm_container_registry_token.this : key => {
      token_id       = token.id
      token_name     = token.name
      scope_map_id   = azurerm_container_registry_scope_map.this[key].id
      scope_map_name = azurerm_container_registry_scope_map.this[key].name
      actions        = azurerm_container_registry_scope_map.this[key].actions
      enabled        = token.enabled
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NETWORKING & ACCESS                                             ║
# ╚════════════════════════════════════════════════════════════════╝

output "private_endpoints" {
  description = "Private endpoint IDs and the private IPs allocated to them."
  value = {
    for key, endpoint in azurerm_private_endpoint.this : key => {
      id                   = endpoint.id
      name                 = endpoint.name
      subnet_id            = endpoint.subnet_id
      private_ip_address   = try(endpoint.private_service_connection[0].private_ip_address, null)
      network_interface_id = try(endpoint.network_interface[0].id, null)
    }
  }
}

output "role_assignments" {
  description = "Created role assignment IDs keyed by the input map key."
  value = {
    for key, assignment in azurerm_role_assignment.this : key => {
      id                 = assignment.id
      role_definition_id = assignment.role_definition_id
      principal_id       = assignment.principal_id
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPERATIONS                                                      ║
# ╚════════════════════════════════════════════════════════════════╝

output "diagnostic_setting_id" {
  description = "Resource ID of the diagnostic setting, or null when diagnostics are disabled."
  value       = try(azurerm_monitor_diagnostic_setting.this[0].id, null)
}

output "lock_id" {
  description = "Resource ID of the management lock, or null when no lock is requested."
  value       = try(azurerm_management_lock.this[0].id, null)
}

output "hierarchy" {
  description = "Naming inputs and the resolved registry name - useful for `terraform output -json` in CI."
  value = {
    organization    = var.organization
    environment   = var.environment
    location      = var.location
    instance      = local.instance_suffix
    region_short    = local.region_short
    registry_name   = local.registry_name
    login_server    = azurerm_container_registry.this.login_server
    pull_command    = "docker pull ${azurerm_container_registry.this.login_server}/<repository>:<tag>"
    guardrails_seen = {
      production_like            = local.production_like
      premium_only_violations    = local.premium_only_violations
      private_endpoints_required = local.production_like && var.enforce_private_endpoints_for_production
    }
  }
}
