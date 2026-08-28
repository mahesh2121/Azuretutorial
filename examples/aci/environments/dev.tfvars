# ╔══════════════════════════════════════════════════════════════════╗
# ║  DEV - public IP, smallest ACI shape, no locks               ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "dev"
organization = "contoso"
location     = "eastus"

container_image = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
cron_image      = "mcr.microsoft.com/azure-cli:latest"

# Cheapest billable ACI shape (0.5 vCPU / 1.5 GB).
cpu_cores = 0.5
memory_gb = 1.5

use_private_ip = false
subnet_ids     = []

# Any globally unique label works in dev, e.g. "contoso-dev-web".
dns_name_label = null

# Fill these two in to pull from a private registry (see examples/full-stack).
user_assigned_identity_id = null
registry_server           = null

# Container logs stay off unless a workspace is supplied.
log_analytics_workspace_id     = ""
log_analytics_workspace_key     = null

enable_lock = false

tags = {
  Team    = "Platform"
  Project = "ACI-Quickstart"
}
