# ╔══════════════════════════════════════════════════════════════════╗
# ║  DEV - cheapest end-to-end path, public IPs, no locks            ║
# ║  terraform plan -var-file=environments/dev.tfvars -out dev.tfplan║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "dev"
organization = "contoso"
location     = "eastus"
app_name     = "shopping"

image_repository = "web"
image_tag        = "1.0.0"

# Keep the free tier usable: Basic registry, public endpoint, no Log Analytics.
registry_sku      = "Basic"
enable_private_link = false

virtual_network_address_space  = "10.40.0.0/16"
aci_subnet_prefix              = "10.40.1.0/24"
private_endpoint_subnet_prefix = "10.40.9.0/28"

aci_cpu_cores = 0.5
aci_memory_gb = 1.5
web_port      = 8080

enable_monitoring   = false
log_retention_days  = 30

# Free tier is fine in dev; the module refuses it outside dev/staging.
notification_sku = "Free"
ios_bundle_id    = "com.contoso.shopping"

apns_key_id      = null
apns_team_id     = null
apns_private_key = null

fcm_api_key = "AA-placeholder-fcm-server-key-change-me"

enforce_probes_for_production    = true
enforce_private_link_for_production = true

tags = {
  Team    = "Platform"
  Project = "FullStack-Tutorial"
}
