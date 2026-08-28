# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE INPUTS - Notification Hubs quickstart                   ║
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
  description = "(REQUIRED) Organisation short code, lowercase alphanumeric."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.organization))
    error_message = "organization must be 1-10 lowercase alphanumeric characters."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region for the namespace."
  type        = string
}

variable "sku_name" {
  description = "(OPTIONAL) Free (dev only), Basic or Standard. The module refuses Free for prod/uat/dr."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Free", "Basic", "Standard"], var.sku_name)
    error_message = "sku_name must be Free, Basic or Standard."
  }
}

variable "ios_bundle_id" {
  description = "(OPTIONAL) iOS/macOS bundle id registered with Apple, e.g. com.contoso.myapp."
  type        = string
  default     = "com.contoso.myapp"

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]{3,100}$", var.ios_bundle_id))
    error_message = "ios_bundle_id must be a reverse-DNS identifier such as com.contoso.myapp."
  }
}

variable "apns_key_id" {
  description = "(OPTIONAL) 10 character APNs .p8 key identifier from Apple Developer > Keys."
  type        = string
  default     = null
}

variable "apns_team_id" {
  description = "(OPTIONAL) 10 character Apple developer team identifier."
  type        = string
  default     = null
}

variable "apns_private_key" {
  description = "(OPTIONAL) Body of the .p8 push key (no BEGIN/END lines). Prefer wiring this from azurerm_key_vault_secret; it is marked sensitive so Terraform never prints it."
  type        = string
  default     = null
  sensitive   = true
}

variable "fcm_api_key" {
  description = "(OPTIONAL) Google API server key for Android delivery. Wire from a secret store in real environments."
  type        = string
  default     = "AA-placeholder-fcm-server-key-change-me"
  sensitive   = true
}

variable "enable_lock" {
  description = "(OPTIONAL) CanNotDelete lock on the namespace."
  type        = bool
  default     = false
}

variable "tags" {
  description = "(OPTIONAL) Extra tags merged onto the standard tag set."
  type        = map(string)
  default     = {}
}
