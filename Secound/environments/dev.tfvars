# ╔══════════════════════════════════════════════════════════════╗
# ║         DEV - FREE ACCOUNT                                  ║
# ║         ONE SUBSCRIPTION = ONE VAULT (enforced)              ║
# ╚══════════════════════════════════════════════════════════════╝

# ─── REQUIRED ────────────────────────────────────────────────────
environment  = "dev"
organization = "contoso"
location     = "eastus"

# ─── FREE ACCOUNT SAFE SETTINGS ─────────────────────────────────
sku_name                      = "standard"
soft_delete_retention_days    = 7
purge_protection_enabled      = false
public_network_access_enabled = true
enable_lock                   = false
enable_diagnostics            = false

network_acls = {
  bypass         = "AzureServices"
  default_action = "Allow"
}

# ─── KEYS ────────────────────────────────────────────────────────
keys_input = {
  "encryption-001" = {
    key_type = "RSA"
    key_size = 2048
    key_opts = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
  }
  "signing-001" = {
    key_type = "RSA"
    key_size = 2048
    key_opts = ["sign", "verify"]
  }
}

# ─── SECRETS ─────────────────────────────────────────────────────
secrets_input = {
  "webapp-db-password" = {
    value        = "AUTO_GENERATE"
    content_type = "password"
  }
  "admin-password" = {
    value        = "AUTO_GENERATE"
    content_type = "password"
  }
  "webapp-db-username" = {
    value        = "dbadmin"
    content_type = "username"
  }
  "sendgrid-apikey" = {
    value        = "SG.test-key-12345"
    content_type = "api-key"
  }
  "storage-connstring" = {
    value        = "DefaultEndpointsProtocol=https;AccountName=devstore;AccountKey=xxxxx"
    content_type = "connection-string"
  }
}

tags = {
  Team    = "Development"
  Project = "WebApp-POC"
}