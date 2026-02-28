# ╔══════════════════════════════════════════════════════════════════╗
# ║                    REQUIRED INPUTS                               ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "environment" {
  description = "(REQUIRED) Environment: dev, staging, uat, prod, dr."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "dr"], var.environment)
    error_message = "Must be: dev, staging, uat, prod, dr."
  }
}

variable "organization" {
  description = "(REQUIRED) Org short name (max 10 chars, lowercase)."
  type        = string
  validation {
    condition     = length(var.organization) <= 10 && can(regex("^[a-z0-9]+$", var.organization))
    error_message = "Lowercase alphanumeric, max 10 chars."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region."
  type        = string
}

# ╔══════════════════════════════════════════════════════════════════╗
# ║                    OPTIONAL INPUTS                               ║
# ║              (Defaults safe for FREE account)                    ║
# ╚══════════════════════════════════════════════════════════════════╝

# NOTE: NO instance_number variable!
# Fixed to "001" to enforce ONE vault per subscription.

variable "sku_name" {
  description = "(OPTIONAL) standard (free) or premium (paid/HSM)."
  type        = string
  default     = "standard"
}

variable "enable_rbac_authorization" {
  description = "(OPTIONAL) Use RBAC."
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "(OPTIONAL) 7-90 days."
  type        = number
  default     = 7
}

variable "purge_protection_enabled" {
  description = "(OPTIONAL) Purge protection."
  type        = bool
  default     = false
}

variable "enabled_for_deployment" {
  type    = bool
  default = false
}

variable "enabled_for_disk_encryption" {
  type    = bool
  default = false
}

variable "enabled_for_template_deployment" {
  type    = bool
  default = false
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "network_acls" {
  description = "(OPTIONAL) Network ACL config."
  type = object({
    bypass                     = optional(string, "AzureServices")
    default_action             = optional(string, "Allow")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  default = {
    bypass         = "AzureServices"
    default_action = "Allow"
  }
}

variable "keys_input" {
  description = <<-EOT
    (OPTIONAL) Keys to create in this subscription's vault.
    Add as many as needed. All go into ONE vault.
    key_type: RSA, EC (free) | RSA-HSM, EC-HSM (premium)
  EOT
  type = map(object({
    key_type        = string
    key_size        = optional(number, 2048)
    key_opts        = list(string)
    expiration_date = optional(string, null)
    rotation_policy = optional(object({
      automatic = optional(object({
        time_before_expiry  = optional(string, null)
        time_after_creation = optional(string, null)
      }), null)
      expire_after         = optional(string, null)
      notify_before_expiry = optional(string, null)
    }), null)
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "secrets_input" {
  description = <<-EOT
    (OPTIONAL) Secrets to create in this subscription's vault.
    Add as many as needed. All go into ONE vault.
    Use value = "AUTO_GENERATE" for random 32-char password.
  EOT
  type = map(object({
    value           = string
    content_type    = optional(string, "text/plain")
    expiration_date = optional(string, null)
    tags            = optional(map(string), {})
  }))
  default = {}
}

variable "role_assignments" {
  description = "(OPTIONAL) RBAC role assignments."
  type = map(object({
    principal_id = string
    role_name    = string
  }))
  default = {}
}

variable "private_endpoints" {
  description = "(OPTIONAL) Private endpoints. Skip for free."
  type = map(object({
    subnet_id            = string
    private_dns_zone_ids = optional(list(string), [])
  }))
  default = {}
}

variable "enable_diagnostics" {
  type    = bool
  default = false
}

variable "log_analytics_workspace_id" {
  type    = string
  default = ""
}

variable "enable_lock" {
  type    = bool
  default = false
}

variable "contact_emails" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}