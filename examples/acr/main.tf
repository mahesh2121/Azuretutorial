# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE: ACR ONLY - custom modules/acr in action                ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.organization}-${var.environment}-acr-${var.location}"
  location = var.location

  tags = merge(
    {
      Environment  = var.environment
      Organization = var.organization
      ManagedBy    = "Terraform"
      Service      = "ContainerRegistry"
    },
    var.tags
  )
}

# ─── TRANSLATE THE SIMPLE EXAMPLE INPUTS INTO MODULE INPUTS ────────
locals {
  private_endpoints = {
    for index, subnet_id in var.private_endpoint_subnet_ids : "primary-${index}" => {
      subnet_id            = subnet_id
      private_dns_zone_ids = var.private_dns_zone_id == null ? [] : [var.private_dns_zone_id]
    }
  }

  tokens = var.enable_ci_tokens ? {
    # `ci-push` is handed to the build pipeline; it can write manifests but
    # cannot delete tags or read unrelated repositories.
    "ci-push" = {
      actions = ["repositories/*/manifest/write/read", "*"]
      description = "Azure DevOps / GitHub Actions build agent"
    }
    # `runtime-pull` is what the container host authenticates with when tokens
    # are preferred over RBAC (e.g. docker daemon on a VM).
    "runtime-pull" = {
      actions = ["repositories/*/manifest/read", "catalog"]
      description = "Runtime pull credential for app hosts"
    }
  } : {}

  # Azure only accepts a retention policy on Premium registries.
  retention_policy = var.registry_sku == "Premium" && var.retention_days > 0 ? { enabled = true, days = var.retention_days } : null

  # Never replicate into the primary region; pick the first available peer.
  secondary_regions = [for region in ["northeurope", "westeurope", "uksouth", "westus2"] : region if region != var.location]

  # Content Trust cannot be switched off once enabled and blocks unsigned pulls,
  # so it stays off here and is documented in the module README.
  trust_policy_enabled = false

  diagnostics = {
    enabled               = var.enable_diagnostics && var.log_analytics_workspace_id != ""
    workspace_resource_id = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : null
    retention_days        = 0
  }

  lock = var.enable_lock ? { kind = "CanNotDelete" } : null
}

module "acr" {
  source = "../../modules/acr"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  sku                                 = var.registry_sku
  admin_enabled                       = false
  public_network_access_enabled       = true
  enforce_private_endpoints_for_production = var.enforce_private_endpoints_for_production

  network_rule_bypass_option = "AzureServices"
  retention_policy            = local.retention_policy
  trust_policy_enabled        = local.trust_policy_enabled
  quarantine_policy_enabled   = false
  zone_redundancy_enabled     = var.environment == "prod"
  anonymous_pull_enabled      = false
  export_policy_enabled       = true

  georeplications = var.registry_sku == "Premium" && var.environment == "prod" && length(local.secondary_regions) > 0 ? [
    { location = local.secondary_regions[0], zone_redundancy_enabled = false, regional_endpoint_enabled = false }
  ] : []

  private_endpoints = local.private_endpoints
  tokens            = local.tokens
  diagnostics       = local.diagnostics
  lock              = local.lock

  tags = var.tags
}
