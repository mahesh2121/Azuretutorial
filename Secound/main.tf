# ╔══════════════════════════════════════════════════════════════════╗
# ║                    RESOURCE GROUP                                ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.standard_tags
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║         RANDOM PASSWORDS FOR AUTO_GENERATE SECRETS               ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "random_password" "generated" {
  for_each = local.auto_secrets

  length           = 32
  special          = true
  override_special = "!@#$%&*()-_=+[]{}|"
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 2
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║    KEY VAULT - Azure Verified Module (AVM)                       ║
# ║                                                                  ║
# ║    ENFORCED: ONE Vault per Subscription                          ║
# ║    • Instance number hardcoded to "001"                          ║
# ║    • Vault name deterministic: kv-{org}-{env}-{region}-001      ║
# ║    • Same subscription + env = same vault (update, not create)   ║
# ║    • All keys & secrets go into THIS ONE vault                   ║
# ║                                                                  ║
# ║    Module handles everything:                                    ║
# ║    Key Vault + Keys + Secrets + RBAC + PE + Diagnostics + Lock  ║
# ╚══════════════════════════════════════════════════════════════════╝

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.9"

  # ─── REQUIRED ────────────────────────────────────────────────
  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  # ─── VAULT CONFIG ───────────────────────────────────────────
  sku_name                        = var.sku_name
  enabled_for_deployment          = var.enabled_for_deployment
  enabled_for_disk_encryption     = var.enabled_for_disk_encryption
  enabled_for_template_deployment = var.enabled_for_template_deployment
  enable_rbac_authorization       = var.enable_rbac_authorization
  purge_protection_enabled        = var.purge_protection_enabled
  soft_delete_retention_days      = var.soft_delete_retention_days
  public_network_access_enabled   = var.public_network_access_enabled

  # ─── NETWORK ACLs ──────────────────────────────────────────
  network_acls = var.network_acls

  # ─── ALL KEYS (multiple, all in ONE vault) ─────────────────
  keys = local.module_keys

  # ─── ALL SECRETS (multiple, all in ONE vault) ──────────────
  secrets = local.module_secrets

  # ─── CONTACTS ─────────────────────────────────────────────
  contacts = local.module_contacts

  # ─── RBAC ──────────────────────────────────────────────────
  role_assignments = local.module_role_assignments

  # ─── PRIVATE ENDPOINTS ─────────────────────────────────────
  private_endpoints = local.module_private_endpoints

  # ─── DIAGNOSTICS ───────────────────────────────────────────
  diagnostic_settings = local.module_diagnostic_settings

  # ─── LOCK ──────────────────────────────────────────────────
  lock = local.module_lock

  # ─── TAGS ──────────────────────────────────────────────────
  tags = local.standard_tags

  # ─── TELEMETRY ─────────────────────────────────────────────
  enable_telemetry = false
}