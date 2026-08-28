# ╔══════════════════════════════════════════════════════════════════╗
# ║  examples/aci/outputs.tf                                         ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Generated outputs - the hand-off values for CI and developers. ║
# ╚══════════════════════════════════════════════════════════════════╝

output "resource_group_name" {
  description = "Resource group that hosts the container groups."
  value       = azurerm_resource_group.this.name
}

output "container_group_names" {
  description = "Names of the container groups created by the module."
  value       = module.aci.container_group_names
}

output "container_group_ids" {
  description = "Azure resource IDs of the container groups."
  value       = module.aci.container_group_ids
}

output "ip_addresses" {
  description = "IP address per container group (empty for VNet-injected groups)."
  value       = module.aci.ip_addresses
}

output "fqdns" {
  description = "FQDN per container group, present only where dns_name_label is set."
  value       = module.aci.fqdns
}

output "application_endpoints" {
  description = "Ready to click http(s) endpoints for every exposed port of every group."
  value       = module.aci.application_endpoints
}

output "image_reference" {
  description = "Image the workload runs; the CI pipeline pushes this tag."
  value       = var.container_image
}

output "user_assigned_identity_ids" {
  description = "User-assigned identity IDs granted to the groups (Key Vault / ACR access)."
  value       = module.aci.user_assigned_identity_ids
}

output "diagnostics_enabled_for" {
  description = "Container groups that ship logs to Log Analytics."
  value       = module.aci.diagnostics_enabled_for
}

output "hierarchy" {
  description = "Audit summary of what the module resolved (names, groups, VNet usage)."
  value       = module.aci.hierarchy
}

# ---------------------------------------------------------------------------
# Next steps (CLI guidance, intentionally not stored in state)
# ---------------------------------------------------------------------------
output "next_steps" {
  description = "Commands to run after apply to verify and use the deployment."
  value = [
    "az container show --resource-group ${azurerm_resource_group.this.name} --name <group> --query 'containers[0].instanceView.currentState'",
    "az container logs --resource-group ${azurerm_resource_group.this.name} --name <group> --container-name main",
    "terraform -chdir=examples/aci output application_endpoints",
  ]
}
