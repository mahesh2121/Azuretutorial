# ╔══════════════════════════════════════════════════════════════════╗
# ║  PROD - private registry, private IPs, identity pulls, SLA   ║   ║
# ║  tier hubs, locks and Log Analytics                          ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "prod"
organization = "contoso"
location     = "westeurope"
app_name     = "shopping"

image_repository = "web"
# Pin an immutable tag produced by the build; `latest` makes rollbacks guesswork.
image_tag = "1.4.2"

# Premium is required for private endpoints, tokens and retention; the module
# also refuses a prod registry without a private endpoint.
registry_sku        = "Premium"
enable_private_link = true

virtual_network_address_space  = "10.41.0.0/16"
aci_subnet_prefix              = "10.41.1.0/24"
private_endpoint_subnet_prefix = "10.41.9.0/28"

aci_cpu_cores = 1.0
aci_memory_gb = 2.0
web_port      = 8080

enable_monitoring  = true
log_retention_days = 90

# Standard: no notification cap, 10 hubs, 99.9% SLA.
notification_sku = "Standard"
ios_bundle_id    = "com.contoso.shopping"

apns_key_id  = "2X9R4HXF34"
apns_team_id = "APPNJTV5QQ"

# The .p8 body must come from the pipeline, never from a file in git:
#   export TF_VAR_apns_private_key="$(az keyvault secret show \
#       --vault-name kv-contoso-prod-weu-001 -n apns-p8 --query value -o tsv)"
apns_private_key = null

fcm_api_key = "AA-replace-me-from-key-vault-000000"

enforce_probes_for_production       = true
enforce_private_link_for_production = true

tags = {
  Team        = "Platform"
  Project     = "FullStack-Tutorial"
  Criticality = "high"
  Runbook     = "https://wiki.contoso.example/runbooks/shopping"
}
