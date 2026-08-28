# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE INPUTS - the knobs a team usually flips                 ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "environment" {
  description = "(REQUIRED) dev, staging, uat, prod or dr."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "dr"], lower(var.environment))
    error_message = "environment must be one of: dev, staging, uat, prod, dr."
  }
}

variable "organization" {
  description = "(REQUIRED) Organisation short code, lowercase alphanumeric, max 10 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.organization))
    error_message = "organization must be 1-10 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region, e.g. eastus."
  type        = string
}

variable "registry_sku" {
  description = "(OPTIONAL) Basic / Standard / Premium. Private endpoints, tokens, geo-replication, retention and trust policies need Premium."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.registry_sku)
    error_message = "registry_sku must be Basic, Standard or Premium."
  }
}

variable "enable_ci_tokens" {
  description = "(OPTIONAL) Create scoped tokens for the CI pipeline (push) and for runtime pulls. Premium only."
  type        = bool
  default     = false
}

variable "enable_diagnostics" {
  description = "(OPTIONAL) Send registry login/manifest events and metrics to Log Analytics."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "(OPTIONAL) Existing Log Analytics workspace resource ID used when enable_diagnostics = true. Leave empty to skip diagnostics entirely."
  type        = string
  default     = ""
}

variable "private_endpoint_subnet_ids" {
  description = "(OPTIONAL) Subnet resource IDs that will host private endpoints for the registry. Requires registry_sku = Premium. See examples/full-stack for a complete private-link wiring."
  type        = list(string)
  default     = []
}

variable "private_dns_zone_id" {
  description = "(OPTIONAL) Resource ID of a `privatelink.azurecr.io` private DNS zone to link to the private endpoint's DNS zone group."
  type        = string
  default     = null
}

variable "enforce_private_endpoints_for_production" {
  description = "(OPTIONAL) The module refuses prod/uat/dr registries without a private endpoint while this is true. Flip it on once private_endpoint_subnet_ids is populated."
  type        = bool
  default     = false
}

variable "enable_lock" {
  description = "(OPTIONAL) Put a CanNotDelete lock on the registry so no one can tear down the image store."
  type        = bool
  default     = false
}

variable "retention_days" {
  description = "(OPTIONAL) Days an untagged manifest survives. Premium only; 0 disables the retention policy block."
  type        = number
  default     = 30
}

variable "tags" {
  description = "(OPTIONAL) Extra tags merged onto the standard tag set."
  type        = map(string)
  default     = {}
}
