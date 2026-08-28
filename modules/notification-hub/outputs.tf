# ╔══════════════════════════════════════════════════════════════════╗
# ║  NAMESPACE                                                       ║
# ╚══════════════════════════════════════════════════════════════════╝

output "namespace_id" {
  description = "Resource ID of the notification hub namespace."
  value       = azurerm_notification_hub_namespace.this.id
}

output "namespace_name" {
  description = "Name of the namespace (resolved, may be generated)."
  value       = azurerm_notification_hub_namespace.this.name
}

output "namespace_sku" {
  description = "Namespace pricing tier in use."
  value       = azurerm_notification_hub_namespace.this.sku_name
}

output "service_endpoint" {
  description = "Service Bus endpoint exposed by the namespace, e.g. `https://ns-contoso-prod-eus001.servicebus.windows.net:443/`."
  value       = azurerm_notification_hub_namespace.this.servicebus_endpoint
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  HUBS                                                            ║
# ╚════════════════════════════════════════════════════════════════╝

output "hub_ids" {
  description = "Resource ID of every hub, keyed by the var.hubs key."
  value       = { for key, hub in azurerm_notification_hub.this : key => hub.id }
}

output "hub_names" {
  description = "Resolved hub names - hand these to the mobile app / backend sender configuration."
  value       = { for key, hub in azurerm_notification_hub.this : key => hub.name }
}

output "hubs" {
  description = "Per hub summary. Deliberately excludes platform credentials: only the fact that a credential is configured is reported."
  value = {
    for key, hub in local.hubs : key => {
      id                 = azurerm_notification_hub.this[key].id
      name               = azurerm_notification_hub.this[key].name
      namespace_name     = azurerm_notification_hub_namespace.this.name
      apns_configured    = hub.apns_ready
      apns_bundle_id     = hub.bundle_id
      apns_mode          = hub.apns_ready ? hub.apns_mode : null
      fcm_configured     = hub.fcm_ready
      registration_ttl   = hub.registration_ttl_seconds
      tags               = hub.tags
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPERATIONS / AUDIT                                              ║
# ╚════════════════════════════════════════════════════════════════╝

output "credential_status" {
  description = "Audit report: which hubs still lack a platform credential and which still point at the Apple sandbox endpoint."
  value = {
    hubs_without_credentials = local.hubs_without_credentials
    hubs_in_apns_sandbox     = local.hubs_in_sandbox
    apns_incomplete          = local.apns_incomplete_hubs
    production_like          = local.production_like
  }
}

output "connection_string_guidance" {
  description = "How to obtain the Send/Listen connection strings without putting them in state."
  value = join(" ", [
    "Shared access policy keys are intentionally not managed by this module.",
    "Fetch them at runtime with:",
    "  az notification-hub namespace list-keys -g ${var.resource_group_name} -n ${local.namespace_name}",
    "  az notification-hub keys list -g ${var.resource_group_name} -n ${local.namespace_name} --namespace-name ${local.namespace_name}",
    "then store the result in Key Vault; the hub names to use are ${jsonencode(local.hub_keys)}.",
  ])
}

output "lock_id" {
  description = "Resource ID of the management lock, or null when var.lock is not set."
  value       = try(azurerm_management_lock.this[0].id, null)
}

output "hierarchy" {
  description = "Resolved naming inputs - handy for `terraform output -json` in pipelines."
  value = {
    organization     = var.organization
    environment    = var.environment
    location         = var.location
    region_short     = local.region_short
    instance         = local.instance_suffix
    namespace_name   = local.namespace_name
    namespace_dns    = local.namespace_dns_name
    hub_name_prefix  = local.hub_name_prefix
    hub_count        = length(local.hub_keys)
    sku              = var.sku_name
    production_like  = local.production_like
  }
}
