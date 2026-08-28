# ╔══════════════════════════════════════════════════════════════════╗
# ║  DEV - cheapest usable registry (free account safe)          ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment = "dev"
organization = "contoso"
location     = "eastus"

# Basic keeps the example free; everything Premium-only below stays off.
registry_sku   = "Basic"
enable_ci_tokens = false
enable_diagnostics = false
log_analytics_workspace_id = ""
private_endpoint_subnet_ids = []
private_dns_zone_id = null
enforce_private_endpoints_for_production = false
enable_lock  = false
retention_days = 7

tags = {
  Team    = "Platform"
  Project = "ACR-Quickstart"
}
