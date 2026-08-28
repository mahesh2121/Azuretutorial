# ╔══════════════════════════════════════════════════════════════════╗
# ║  REQUIRED INPUTS                                                 ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "environment" {
  description = "(REQUIRED) Environment name: dev, staging, uat, prod or dr. Drives naming, tagging and the production guardrails."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "dr"], lower(var.environment))
    error_message = "environment must be one of: dev, staging, uat, prod, dr."
  }
}

variable "organization" {
  description = "(REQUIRED) Organisation short code, used in the registry name and the `Organization` tag. Lowercase alphanumeric, max 10 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.organization))
    error_message = "organization must be 1-10 lowercase alphanumeric characters (a-z0-9)."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region for the registry, e.g. `eastus`. Changing this forces a new resource."
  type        = string

  validation {
    condition     = length(var.location) > 0 && var.location == lower(replace(var.location, " ", ""))
    error_message = "location must be a lowercase Azure region without spaces, e.g. `eastus` or `westeurope`."
  }
}

variable "resource_group_name" {
  description = "(REQUIRED) Existing resource group in which the registry will be created. Changing this forces a new resource."
  type        = string

  validation {
    condition     = can(regex("^[-a-zA-Z0-9._()]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid resource group name (1-90 chars, no underscore)."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NAMING                                                          ║
# ╚════════════════════════════════════════════════════════════════╝

variable "name" {
  description = "(OPTIONAL) Explicit registry name. When null, a deterministic name is generated: `acr{organization}{environment}{region_short}{instance_number}`."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "name must be 5-50 lowercase alphanumeric characters (Azure does not allow hyphens in ACR names)."
  }
}

variable "instance_number" {
  description = "(OPTIONAL) Numeric suffix (zero padded to 3) appended to the generated registry name. Used to keep names unique when several registries live in the same region."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_number >= 1 && var.instance_number <= 999
    error_message = "instance_number must be between 1 and 999."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  SKY & BASIC CONFIG                                              ║
# ╚════════════════════════════════════════════════════════════════╝

variable "sku" {
  description = "(OPTIONAL) Registry SKU. `Premium` is required for private endpoints, network rules, geo-replication, zone redundancy, retention/trust/quarantine policies and tokens."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "(OPTIONAL) Enable the registry admin user. Deprecated by Azure and hard-blocked for prod/staging/uat/dr by a lifecycle precondition - use tokens or ACRPull/ACRPush RBAC instead."
  type        = bool
  default     = false
}

variable "public_network_access_enabled" {
  description = "(OPTIONAL) Allow access to the registry over the public endpoint. Set to false for private-link-only registries."
  type        = bool
  default     = true
}

variable "enforce_private_endpoints_for_production" {
  description = "(OPTIONAL) When true, non-dev environments must declare at least one private endpoint. A recommended guardrail, enabled by default."
  type        = bool
  default     = true
}

variable "network_rule_bypass_option" {
  description = "(OPTIONAL) Which trusted Azure services may bypass network rules. Possible values: `None`, `AzureServices`."
  type        = string
  default     = "AzureServices"

  validation {
    condition     = contains(["None", "AzureServices"], var.network_rule_bypass_option)
    error_message = "network_rule_bypass_option must be either `None` or `AzureServices`."
  }
}

variable "network_rule_set" {
  description = <<-EOT
    (OPTIONAL) Firewall rules for the registry. Premium only.
    Set `default_action = "Deny"` to lock the registry down to the listed IP ranges.
  EOT
  type = object({
    default_action = optional(string, "Allow")
    ip_rules       = optional(list(string), [])
  })
  default = null

  validation {
    condition     = var.network_rule_set == null || contains(["Allow", "Deny"], coalesce(var.network_rule_set.default_action, "Allow"))
    error_message = "network_rule_set.default_action must be `Allow` or `Deny`."
  }
}

variable "anonymous_pull_enabled" {
  description = "(OPTIONAL) Allow unauthenticated image pulls. Standard/Premium only. Off by default - only enable for publicly distributable images."
  type        = bool
  default     = false
}

variable "data_endpoint_enabled" {
  description = "(OPTIONAL) Enable dedicated data endpoints for tiered login. Premium only."
  type        = bool
  default     = false
}

variable "export_policy_enabled" {
  description = "(OPTIONAL) Allow images to be exported from the registry. Set to false (with public_network_access_enabled = false) for hardened registries."
  type        = bool
  default     = true
}

variable "zone_redundancy_enabled" {
  description = "(OPTIONAL) Zone-redundant storage/metadata for the registry. Premium only. Changing this forces a new resource."
  type        = bool
  default     = false
}

variable "quarantine_policy_enabled" {
  description = "(OPTIONAL) Quarantine newly pushed images until they are scanned. Premium only."
  type        = bool
  default     = false
}

variable "trust_policy_enabled" {
  description = "(OPTIONAL) Enable Content Trust (Notary v2) so only signed images can be pulled. Premium only."
  type        = bool
  default     = false
}

variable "retention_policy" {
  description = "(OPTIONAL) Retention of untagged manifests. Configurable on Premium only - Azure fixes untagged manifest retention at 7 days for Basic/Standard registries."
  type = object({
    enabled = optional(bool, true)
    days    = optional(number, 7)
  })
  default = null

  validation {
    condition     = var.retention_policy == null || try(var.retention_policy.days, null) == null || var.retention_policy.days >= 1
    error_message = "retention_policy.days must be at least 1."
  }
}

variable "georeplications" {
  description = "(OPTIONAL) Geo-replicated registry locations. Premium only. The primary `location` must not be listed; entries are applied in alphabetical location order as required by Azure."
  type = list(object({
    location                  = string
    zone_redundancy_enabled   = optional(bool, false)
    regional_endpoint_enabled = optional(bool, false)
  }))
  default = []
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  IDENTITY, ENCRYPTION & ACCESS                                   ║
# ╚════════════════════════════════════════════════════════════════╝

variable "managed_identity_type" {
  description = "(OPTIONAL) Registry managed identity type. `None`, `SystemAssigned`, `UserAssigned` or `SystemAssigned, UserAssigned`."
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "SystemAssigned", "UserAssigned", "SystemAssigned, UserAssigned"], var.managed_identity_type)
    error_message = "managed_identity_type must be None, SystemAssigned, UserAssigned or \"SystemAssigned, UserAssigned\"."
  }
}

variable "user_assigned_identity_ids" {
  description = "(OPTIONAL) User-assigned managed identity resource IDs assigned to the registry. Required when managed_identity_type includes `UserAssigned`."
  type        = list(string)
  default     = []
}

variable "encryption" {
  description = <<-EOT
    (OPTIONAL) Customer-managed key encryption (Premium only).
    `key_vault_key_id`   - versionless Key Vault key ID.
    `identity_client_id` - client ID of a user-assigned identity that is ALSO present in `user_assigned_identity_ids` and has `get/wrapKey/unwrapKey` on the key.
  EOT
  type = object({
    key_vault_key_id   = string
    identity_client_id = string
  })
  default = null
}

variable "role_assignments" {
  description = <<-EOT
    (OPTIONAL) RBAC scoped to the registry. Typical production shape:
      aci-pull = { principal_id = <ACI identity object id>, role_definition_name = "AcrPull" }
    Provide exactly one of `role_definition_name` (built-in/custom role name) or `role_definition_id` (full role definition resource ID).
  EOT
  type = map(object({
    principal_id         = string
    role_definition_name = optional(string)
    role_definition_id   = optional(string)
    principal_type       = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      try(v.role_definition_name, null) != null ? try(v.role_definition_id, null) == null : try(v.role_definition_id, null) != null
    ])
    error_message = "each role_assignments entry must set exactly one of role_definition_name or role_definition_id."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      try(v.principal_type, null) == null || contains(["User", "Group", "ServicePrincipal", "ForeignGroup", "Device"], v.principal_type)
    ])
    error_message = "role_assignments principal_type must be one of: User, Group, ServicePrincipal, ForeignGroup, Device."
  }
}

variable "tokens" {
  description = <<-EOT
    (OPTIONAL) Scope-mapped registry tokens for CI/CD and runtime pull (Premium only).
    Each entry creates one scope map + one token, e.g.
      ci-push  = { actions = ["repositories/*/manifest/write/read", "*"] }
      app-pull = { actions = ["repositories/my-app/manifest/read", "catalog"] }
    Token passwords are never stored in state - rotate them out of band with `az acr token generate-password`.
  EOT
  type = map(object({
    token_name     = optional(string)
    scope_map_name = optional(string)
    actions        = list(string)
    description    = optional(string)
    enabled        = optional(bool, true)
  }))
  default = {}
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NETWORKING & OBSERVABILITY                                      ║
# ╚════════════════════════════════════════════════════════════════╝

variable "private_endpoints" {
  description = <<-EOT
    (OPTIONAL) Private endpoints for the registry (Premium only).
    subnet_id              - the delegated/standard subnet that hosts the NIC.
    private_dns_zone_ids   - usually the `privatelink.azurecr.io` zone resource ID; omit to manage DNS yourself.
  EOT
  type = map(object({
    subnet_id            = string
    private_dns_zone_ids = optional(list(string), [])
    subresource_names    = optional(list(string), ["registry"])
    name                 = optional(string)
    tags                 = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.private_endpoints : length(v.subresource_names) > 0])
    error_message = "each private_endpoints entry needs a non-empty subresource_names list (usually [\"registry\"])."
  }
}

variable "diagnostics" {
  description = <<-EOT
    (OPTIONAL) Diagnostic settings for the registry.
    `workspace_resource_id` is the only mandatory field; logs are shipped to Log Analytics.
    `log_categories` must match the categories Azure exposes for Microsoft.ContainerRegistry/registries.
  EOT
  type = object({
    enabled               = optional(bool, true)
    workspace_resource_id = optional(string, null)
    log_categories        = optional(list(string), ["ContainerRegistryRepositoryEvents", "ContainerRegistryLoginEvents"])
    metric_categories     = optional(list(string), ["AllMetrics"])
    retention_days        = optional(number, 0)
    name                  = optional(string, null)
  })
  default = {
    enabled = false
  }

  validation {
    condition     = var.diagnostics.retention_days >= 0 && var.diagnostics.retention_days <= 365
    error_message = "diagnostics.retention_days must be between 0 (indefinite) and 365."
  }
}

variable "lock" {
  description = "(OPTIONAL) Management lock on the registry. `CanNotDelete` is recommended for prod/uat/dr."
  type = object({
    kind = optional(string, "CanNotDelete")
    name = optional(string, null)
  })
  default = null

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock.kind, "CanNotDelete"))
    error_message = "lock.kind must be `CanNotDelete` or `ReadOnly`."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  TAGS                                                            ║
# ╚════════════════════════════════════════════════════════════════╝

variable "tags" {
  description = "(OPTIONAL) Extra tags merged onto the standard tag set."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.tags :
      length(k) <= 512 && length(v) <= 256
    ])
    error_message = "Azure tags are limited to 512 characters for keys and 256 for values."
  }
}
