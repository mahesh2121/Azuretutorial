# ╔══════════════════════════════════════════════════════════════════╗
# ║  PROD - VNet injected private IPs, identity pulls, probes    ║   ║
# ╚══════════════════════════════════════════════════════════════════╝

environment  = "prod"
organization = "contoso"
location     = "westeurope"

container_image = "acrcontosoprodeus001.azurecr.io/web:1.4.2"
cron_image      = "acrcontosoprodeus001.azurecr.io/batch:1.4.2"

cpu_cores = 1.0
memory_gb = 2.0

# VNet injection: subnets must be delegated to
# Microsoft.ContainerInstance/containerGroups (see examples/full-stack).
use_private_ip = true
subnet_ids = [
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso-prod-network-westeurope/providers/Microsoft.Network/virtualNetworks/vnet-contoso-prod/providers/Microsoft.Network/subnets/snet-aci"
]

# dns_name_label is refused with a private IP, so it stays null here.
dns_name_label = null

# Identity-based pulls: no registry secret in state.
user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-contoso-prod-aci-westeurope/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-contoso-prod-aci"
registry_server           = "acrcontosoprodeus001.azurecr.io"

log_analytics_workspace_id = ""
log_analytics_workspace_key = null

enable_lock = true

tags = {
  Team        = "Platform"
  Project     = "ACI-Quickstart"
  Criticality = "high"
}
