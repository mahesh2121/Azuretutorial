# ╔══════════════════════════════════════════════════════════════════╗
# ║  LOCALS - NAMING, TAGS AND DERIVED CONFIGURATION                 ║
# ║                                                                  ║
# ║  Every value here is deterministic: the same inputs always       ║
# ║  produce the same resource names, which keeps plans reviewable.  ║
# ╚══════════════════════════════════════════════════════════════════╝

locals {
  # ─── REGION SHORT CODES (shared convention across this repo) ────
  region_short_codes = {
    "eastus"           = "eus"
    "eastus2"           = "eus2"
    "centralus"         = "cus"
    "northcentralus"    = "ncus"
    "southcentralus"    = "scus"
    "westus2"           = "wus2"
    "westus3"           = "wus3"
    "canadacentral"     = "caca"
    "northeurope"       = "neu"
    "westeurope"        = "weu"
    "uksouth"           = "uks"
    "ukwest"            = "ukw"
    "francecentral"     = "frc"
    "germanywestcentral" = "gwc"
    "switzerlandnorth"  = "swn"
    "swedencentral"     = "sec"
    "uaenorth"          = "uane"
    "southafricanorth"  = "safa"
    "eastasia"          = "eas"
    "southeastasia"     = "sea"
    "japaneast"         = "jae"
    "japanwest"         = "jaw"
    "koreacentral"      = "koc"
    "australiaeast"     = "aus"
    "centralindia"      = "cen"
  }

  location_normalized = replace(var.location, " ", "")
  region_short = try(
    lookup(local.region_short_codes, local.location_normalized, substr(local.location_normalized, 0, 4)),
    local.location_normalized
  )

  # ─── NAMES ──────────────────────────────────────────────────────
  # Azure requires ACR names to be 3-50 (docs say 5-50 in practice)
  # lowercase alphanumeric - hyphens are NOT allowed.
  # NOTE: registry names are globally unique inside Azure.
  instance_suffix = format("%03d", var.instance_number)
  registry_name   = coalesce(var.name, "acr${var.organization}${var.environment}${local.region_short}${local.instance_suffix}")

  # ─── SCOPE FLAGS ────────────────────────────────────────────────
  is_premium      = var.sku == "Premium"
  is_standard_up  = contains(["Standard", "Premium"], var.sku)
  production_like = contains(["prod", "uat", "dr"], lower(var.environment))

  # ─── STANDARD TAGS ──────────────────────────────────────────────
  standard_tags = merge(
    {
      Environment        = var.environment
      Organization       = var.organization
      Service            = "ContainerRegistry"
      ManagedBy          = "Terraform"
      Module             = "azure-acr"
      Sku                = var.sku
      DataClassification = "Confidential"
    },
    var.tags
  )

  # ─── NETWORK RULES ──────────────────────────────────────────────
  network_rule_set = var.network_rule_set == null ? null : {
    default_action = var.network_rule_set.default_action
    ip_rules       = [for ip in var.network_rule_set.ip_rules : ip if ip != null]
  }

  # ─── GEO REPLICATIONS ───────────────────────────────────────────
  # Keyed by location so Terraform applies them in alphabetical order,
  # which is what the Azure API requires (duplicate locations fail loudly
  # as a duplicate object key instead of silently creating one replica).
  georeplications = { for g in var.georeplications : g.location => g }

  # ─── PREMIUM-ONLY BOOLEANS ──────────────────────────────────────
  # Azure rejects these attributes on Basic/Standard registries, so they are
  # written as null (i.e. omitted from the API payload) unless requested.
  anonymous_pull_enabled    = var.anonymous_pull_enabled ? true : null
  data_endpoint_enabled     = var.data_endpoint_enabled ? true : null
  quarantine_policy_enabled = var.quarantine_policy_enabled ? true : null
  zone_redundancy_enabled   = var.zone_redundancy_enabled ? true : null
  export_policy_enabled     = var.export_policy_enabled ? null : false

  # ─── MANAGED IDENTITY ───────────────────────────────────────────
  identity_type    = var.managed_identity_type
  identity_enabled = var.managed_identity_type != "None"

  # ─── CUSTOMER MANAGED KEY ───────────────────────────────────────
  encryption_enabled  = var.encryption != null
  encryption_key_id   = try(var.encryption.key_vault_key_id, null)
  encryption_client_id = try(var.encryption.identity_client_id, null)

  # ─── PRIVATE ENDPOINTS ──────────────────────────────────────────
  private_endpoints = {
    for key, endpoint in var.private_endpoints : key => {
      name                 = coalesce(endpoint.name, "pe-${key}-${local.registry_name}")
      subnet_id            = endpoint.subnet_id
      private_dns_zone_ids = endpoint.private_dns_zone_ids
      subresource_names     = endpoint.subresource_names
      tags                 = merge(local.standard_tags, endpoint.tags)
    }
  }

  private_endpoints_enabled = length(local.private_endpoints) > 0

  # ─── TOKENS & SCOPE MAPS ────────────────────────────────────────
  tokens = {
    for key, token in var.tokens : key => {
      token_name     = coalesce(token.token_name, replace(key, "/[^a-zA-Z0-9_-]/", "-"))
      scope_map_name = coalesce(token.scope_map_name, replace("${key}-scope-map", "/[^a-zA-Z0-9_-]/", "-"))
      actions        = token.actions
      description    = coalesce(token.description, "Scoped access managed by Terraform (modules/acr)")
      enabled        = token.enabled
    }
  }

  # ─── DIAGNOSTICS ────────────────────────────────────────────────
  diagnostics_enabled = try(var.diagnostics.enabled, false) && try(var.diagnostics.workspace_resource_id, null) != null

  diagnostics_workspace_id = try(var.diagnostics.workspace_resource_id, null)
  diagnostics_log_categories = coalesce(
    try(var.diagnostics.log_categories, null),
    ["ContainerRegistryRepositoryEvents", "ContainerRegistryLoginEvents"]
  )
  diagnostics_metric_categories = coalesce(try(var.diagnostics.metric_categories, null), ["AllMetrics"])
  diagnostics_retention_days    = try(var.diagnostics.retention_days, 0)
  diagnostics_name              = coalesce(try(var.diagnostics.name, null), "diag-${local.registry_name}")

  # ─── LOCK ───────────────────────────────────────────────────────
  lock_enabled = var.lock != null
  lock_kind    = try(var.lock.kind, "CanNotDelete")
  lock_name    = var.lock == null ? null : coalesce(var.lock.name, "lock-${local.registry_name}")

  # ─── FEATURES THAT REQUIRE PREMIUM ──────────────────────────────
  # Consumed by the lifecycle preconditions in main.tf and asserted by
  # the unit tests, so the list of guarded features lives in one place.
  premium_only_features = {
    "zone_redundancy_enabled"   = var.zone_redundancy_enabled
    "data_endpoint_enabled"     = var.data_endpoint_enabled
    "quarantine_policy_enabled" = var.quarantine_policy_enabled
    "trust_policy_enabled"      = var.trust_policy_enabled
    "retention_policy"          = var.retention_policy != null
    "export_policy_enabled"     = !var.export_policy_enabled
    "network_rule_set"          = local.network_rule_set != null
    "georeplications"           = length(local.georeplications) > 0
    "private_endpoints"         = local.private_endpoints_enabled
    "tokens"                    = length(local.tokens) > 0
    "customer_managed_key"      = local.encryption_enabled
  }

  premium_only_violations = [
    for feature, requested in local.premium_only_features :
    feature if requested && !local.is_premium
  ]
}
