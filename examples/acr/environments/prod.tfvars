# ╔══════════════════════════════════════════════════════════════════╗
# ║  PROD - hardened registry: Premium, tokens, lock, no admin   ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "prod"
organization = "contoso"
location     = "eastus"

registry_sku = "Premium"

# Admin user is refused by the module for prod - this line only documents it.
enable_ci_tokens = true
enable_lock      = true
retention_days   = 30

# Point these at the shared observability stack to enable log/metric shipping.
enable_diagnostics         = false
log_analytics_workspace_id = ""

# Fill these in (or copy examples/full-stack, which builds the network) to
# switch on private links, then flip the guardrail to true so no environment
# can be applied without one.
private_endpoint_subnet_ids                = []
private_dns_zone_id                        = null
enforce_private_endpoints_for_production   = false

tags = {
  Team       = "Platform"
  Project    = "ACR-Quickstart"
  Criticality = "high"
}
