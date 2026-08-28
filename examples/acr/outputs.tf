# ╔══════════════════════════════════════════════════════════════════╗
# ║  outputs.tf                                                      ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  Generated outputs - the hand-off values for CI, DNS and develo  ║
# ╚══════════════════════════════════════════════════════════════════╝

output "resource_group_name" {
  description = "Resource group created for the registry."
  value       = azurerm_resource_group.this.name
}

output "registry_name" {
  description = "Registry name chosen by the module."
  value       = module.acr.name
}

output "login_server" {
  description = "Use this as the image prefix, e.g. `<login_server>/web:1.0.0`."
  value       = module.acr.login_server
}

output "registry_id" {
  description = "Registry resource ID (scope for ACRPull/ACRPush role assignments)."
  value       = module.acr.resource_id
}

output "token_names" {
  description = "Registry token names created by enable_ci_tokens, ready for `az acr credential show`."
  value       = { for key, token in module.acr.tokens : key => token.token_name }
}

output "docker_login_commands" {
  description = "Copy/paste commands to authenticate the Docker CLI against this registry."
  value = var.registry_sku == "Premium" && var.enable_ci_tokens ? {
    adminless_login = "az acr login --name ${module.acr.name}"
    token_login     = "az acr token generate-password --registry-name ${module.acr.name} --token-name ci-push --name password1 && docker login ${module.acr.login_server} --username ci-push"
    } : {
    adminless_login = "az acr login --name ${module.acr.name}"
  }
}
