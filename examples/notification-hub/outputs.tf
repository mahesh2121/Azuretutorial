# ╔══════════════════════════════════════════════════════════════════╗
# ║  outputs.tf                                                      ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Generated outputs - the hand-off values for CI, DNS and develo  ║
# ╚══════════════════════════════════════════════════════════════════╝

output "resource_group_name" {
  description = "Resource group holding the namespace and hubs."
  value       = azurerm_resource_group.this.name
}

output "namespace_name" {
  description = "Namespace name (globally unique, also the DNS prefix)."
  value       = module.notifications.namespace_name
}

output "namespace_sku" {
  description = "Namespace pricing tier."
  value       = module.notifications.namespace_sku
}

output "hub_names" {
  description = "Hub names to give to the mobile apps and to the backend sender."
  value       = module.notifications.hub_names
}

output "hub_ids" {
  description = "Hub resource IDs, useful for `az notification-hub keys list`."
  value       = module.notifications.hub_ids
  sensitive   = false
}

output "credential_status" {
  description = "Which hubs still lack a platform credential / still use the Apple sandbox."
  value       = module.notifications.credential_status
}

output "next_steps" {
  description = "How to retrieve the Send/Listen keys without writing them into state."
  value       = module.notifications.connection_string_guidance
}
