# ╔══════════════════════════════════════════════════════════════════╗
# ║                    KEY VAULT                                     ║
# ╚══════════════════════════════════════════════════════════════════╝

output "key_vault_id" {
  description = "Key Vault Resource ID."
  value       = module.key_vault.resource_id
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = module.key_vault.resource_uri
}

output "subscription_id" {
  description = "Subscription this vault belongs to."
  value       = local.subscription_id
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                    KEYS                                          ║
# ╚══════════════════════════════════════════════════════════════════╝

output "keys" {
  description = "All keys in this subscription's vault."
  value       = module.key_vault.keys
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                    SECRETS                                       ║
# ╚══════════════════════════════════════════════════════════════════╝

output "secrets" {
  description = "All secrets metadata (values NOT exposed)."
  value       = module.key_vault.secrets
  sensitive   = true
}

output "secret_references" {
  description = "App Service ready references."
  value = {
    for original_key, standardized_name in local.secret_name_map :
    original_key => try(
      "@Microsoft.KeyVault(SecretUri=${module.key_vault.secrets[standardized_name].versionless_id})",
      "NOT_FOUND"
    )
  }
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                    NAMING MAP                                    ║
# ╚══════════════════════════════════════════════════════════════════╝

output "naming_map" {
  description = "Input names → standardized names."
  value = {
    vault   = local.key_vault_name
    keys    = local.key_name_map
    secrets = local.secret_name_map
  }
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                    ONE VAULT ENFORCEMENT                         ║
# ╚══════════════════════════════════════════════════════════════════╝

output "vault_policy" {
  description = "Vault policy enforcement details."
  value = {
    subscription_id = local.subscription_id
    vault_name      = local.key_vault_name
    enforced        = "ONE vault per subscription"
    total_keys      = length(var.keys_input)
    total_secrets   = length(var.secrets_input)
    auto_generated  = length(local.auto_secrets)
    manual_secrets  = length(local.manual_secrets)
  }
}