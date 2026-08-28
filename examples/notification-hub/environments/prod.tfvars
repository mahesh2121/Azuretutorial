# ╔══════════════════════════════════════════════════════════════════╗
# ║  PROD - Standard tier, delete lock, Apple Production mode    ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "prod"
organization = "contoso"
location     = "westeurope"

# Standard is required for production: no monthly notification cap, 10 hubs
# and a 99.9% SLA. The module refuses Free here.
sku_name = "Standard"

ios_bundle_id = "com.contoso.myapp"
apns_key_id   = "2X9R4HXF34"
apns_team_id  = "APPNJTV5QQ"

# Never commit the .p8 body. Inject it from the pipeline or read it from Key
# Vault with a data source wired into var.apns_private_key:
#   export TF_VAR_apns_private_key="$(az keyvault secret show -n apns-p8 --vault-name kv-contoso-prod-weu-001 --query value -o tsv)"
apns_private_key = null

fcm_api_key = "AA-placeholder-fcm-server-key-change-me"

enable_lock = true

tags = {
  Team        = "Mobile"
  Project     = "Push-Notifications"
  Criticality = "high"
}
