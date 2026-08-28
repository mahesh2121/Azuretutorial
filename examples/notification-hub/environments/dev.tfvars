# ╔══════════════════════════════════════════════════════════════════╗
# ║  DEV - Basic namespace, Apple sandbox, Android only for now  ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "dev"
organization = "contoso"
location     = "eastus"

# Free is capped at one hub and has no SLA; Basic is the cheapest real tier.
sku_name = "Basic"

ios_bundle_id = "com.contoso.myapp"

# Leave the APNs trio null while the Apple Developer artefacts do not exist
# yet - the hub still becomes usable through the FCM credential below.
apns_key_id      = null
apns_team_id     = null
apns_private_key = null

# Placeholder only. Real keys come from Key Vault / CI secrets:
#   export TF_VAR_fcm_api_key=$(az keyvault secret show --query value -o tsv)
fcm_api_key = "AA-placeholder-fcm-server-key-change-me"

enable_lock = false

tags = {
  Team    = "Mobile"
  Project = "Push-Notifications"
}
