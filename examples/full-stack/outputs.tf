# ╔══════════════════════════════════════════════════════════════════╗
# ║  outputs.tf                                                      ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Generated outputs - the hand-off values for CI, DNS and develo  ║
# ╚══════════════════════════════════════════════════════════════════╝

output "resource_group_name" {
  description = "Resource group holding the whole stack."
  value       = azurerm_resource_group.this.name
}

output "registry_login_server" {
  description = "Prefix your image tags with this value."
  value       = module.acr.login_server
}

output "registry_name" {
  description = "Registry name (used by `az acr login` and the CI task)."
  value       = module.acr.name
}

output "registry_id" {
  description = "Registry resource ID - the scope for extra role assignments."
  value       = module.acr.resource_id
}

output "image_reference" {
  description = "Fully qualified image the stack deploys."
  value       = local.image
}

output "registry_token_names" {
  description = "Scoped registry tokens created for CI; rotate the password outside of Terraform."
  value       = { for key, token in module.acr.tokens : key => token.token_name }
}

output "container_group_names" {
  description = "Name of every ACI container group (az container show / kubectl-less debugging starts here)."
  value       = module.aci.container_group_names
}

output "container_endpoints" {
  description = "Reachable endpoints for each container group."
  value       = module.aci.application_endpoints
}

output "container_ips" {
  description = "IP address of every container group (private when enable_private_link = true)."
  value       = module.aci.ip_addresses
}

output "aci_identity_id" {
  description = "User-assigned identity used by ACI. Grant it more roles here instead of adding secrets."
  value       = azurerm_user_assigned_identity.aci.id
}

output "aci_identity_principal_id" {
  description = "Object ID of the ACI identity (what az role assignment --assignee expects)."
  value       = azurerm_user_assigned_identity.aci.principal_id
}

output "notification_namespace_name" {
  description = "Notification hub namespace."
  value       = module.notifications.namespace_name
}

output "notification_hub_names" {
  description = "Hub names for the mobile clients and the backend sender."
  value       = module.notifications.hub_names
}

output "notification_hub_resource_ids" {
  description = "Hub resource IDs, used when fetching Send/Listen keys with the Azure CLI."
  value       = module.notifications.hub_ids
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving registry diagnostics and ACI container logs (null when enable_monitoring = false)."
  value       = try(azurerm_log_analytics_workspace.this[0].id, null)
}

output "virtual_network_id" {
  description = "Hub VNet created for private link / ACI injection."
  value       = try(azurerm_virtual_network.this[0].id, null)
}

output "private_endpoint_ips" {
  description = "Private IPs allocated to the registry private endpoints."
  value       = { for key, endpoint in module.acr.private_endpoints : key => endpoint.private_ip_address }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPERATOR NOTES                                                  ║
# ╚════════════════════════════════════════════════════════════════╝

output "next_steps" {
  description = "Commands to build, push and run the first image through this stack."
  value = [
    "az acr login --name ${module.acr.name}",
    "docker build -t ${module.acr.login_server}/${var.image_repository}:${var.image_tag} .",
    "docker push ${module.acr.login_server}/${var.image_repository}:${var.image_tag}",
    "terraform plan -var-file=environments/dev.tfvars -out dev.tfplan",
    "az container show --ids $(terraform output -json container_group_names | jq -r '.web') --query 'instanceView.state' -o tsv",
  ]
}
