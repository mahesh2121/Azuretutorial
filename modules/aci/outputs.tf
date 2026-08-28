# ╔══════════════════════════════════════════════════════════════════╗
# ║  GROUP IDENTIFIERS                                               ║
# ╚══════════════════════════════════════════════════════════════════╝

output "container_group_ids" {
  description = "Resource ID of every container group, keyed by the var.container_groups key."
  value       = { for key, group in azurerm_container_group.this : key => group.id }
}

output "container_group_names" {
  description = "Name of every container group (the resolved name, which may be generated)."
  value       = { for key, group in azurerm_container_group.this : key => group.name }
}

output "resource" {
  description = "Curated per-group summary for callers that need more than IDs."
  value = {
    for key, group in local.container_groups : key => {
      id              = azurerm_container_group.this[key].id
      name            = azurerm_container_group.this[key].name
      os_type         = group.os_type
      restart_policy  = azurerm_container_group.this[key].restart_policy
      ip_address_type = azurerm_container_group.this[key].ip_address_type
      sku             = group.sku
      priority        = group.priority
      zones           = group.zones
      subnet_ids      = group.subnet_ids
      containers      = [for container in group.containers : { name = container.name, image = container.image, cpu = container.cpu, memory = container.memory }]
      volumes         = [for volume in group.volumes : volume.name]
      tags            = group.tags
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NETWORKING                                                      ║
# ╚════════════════════════════════════════════════════════════════╝

output "ip_addresses" {
  description = "IP address assigned to each container group (public IP when ip_address_type = Public)."
  value       = { for key, group in azurerm_container_group.this : key => try(group.ip_address, null) }
}

output "fqdns" {
  description = "FQDN of each container group derived from dns_name_label (null when no label is set)."
  value       = { for key, group in azurerm_container_group.this : key => try(group.fqdn, null) }
}

output "application_endpoints" {
  description = "https:// endpoints for every group that exposes a public IP and ports. Handy for smoke tests in CI."
  value = {
    for key, group in local.container_groups : key => [
      for port in group.exposed_ports :
      "http://${try(azurerm_container_group.this[key].fqdn, azurerm_container_group.this[key].ip_address, "unassigned")}:${port.port}"
      if group.ip_address_type == "Public"
    ]
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  IDENTITY                                                        ║
# ╚════════════════════════════════════════════════════════════════╝

output "system_assigned_principal_ids" {
  description = "Object (principal) IDs of system-assigned identities, for granting RBAC such as AcrPull or Key Vault secrets user."
  value = {
    for key, group in azurerm_container_group.this : key =>
    try(group.identity[0].principal_id, null)
    if contains(keys(local.container_groups), key) && contains(["SystemAssigned", "SystemAssigned, UserAssigned"], try(local.container_groups[key].identity_type, "None"))
  }
}

output "user_assigned_identity_ids" {
  description = "User-assigned identity resource IDs actually attached to each group (after defaults are applied). The owning identity's principal_id is what needs the role assignment."
  value       = { for key, group in local.container_groups : key => group.identity_ids }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPERATIONS / AUDIT                                              ║
# ╚════════════════════════════════════════════════════════════════╝

output "diagnostics_enabled_for" {
  description = "Keys of the groups that ship container logs to Log Analytics, with the workspace used."
  value = {
    for key, group in local.container_groups : key => group.diagnostics_workspace_id
    if group.diagnostics_enabled
  }
}

output "lock_ids" {
  description = "Management lock IDs, when var.lock is set."
  value       = { for key, lock in azurerm_management_lock.this : key => lock.id }
}

output "hierarchy" {
  description = "Resolved naming inputs - handy for `terraform output -json` in pipelines."
  value = {
    name_prefix         = local.name_prefix
    organization        = var.organization
    environment         = var.environment
    location            = var.location
    region_short        = local.region_short
    production_like     = local.production_like
    groups              = local.group_keys
    vnet_injected       = local.groups_using_vnet
    public_ip_groups    = local.groups_with_public_ip
    identity_groups     = local.groups_with_identity
    dns_label_groups    = local.groups_with_dns_label
  }
}
