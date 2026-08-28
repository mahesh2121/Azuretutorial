# ╔══════════════════════════════════════════════════════════════════╗
# ║  REQUIRED INPUTS                                                 ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "environment" {
  description = "(REQUIRED) Environment name: dev, staging, uat, prod or dr. Used for naming, tagging and the production guardrails."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "dr"], lower(var.environment))
    error_message = "environment must be one of: dev, staging, uat, prod, dr."
  }
}

variable "organization" {
  description = "(REQUIRED) Organisation short code used in names and the `Organization` tag. Lowercase alphanumeric, max 10 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.organization))
    error_message = "organization must be 1-10 lowercase alphanumeric characters (a-z0-9)."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region for the namespace and hubs, e.g. `westeurope`."
  type        = string

  validation {
    condition     = length(var.location) > 0 && var.location == lower(replace(var.location, " ", ""))
    error_message = "location must be a lowercase Azure region without spaces, e.g. `eastus` or `westeurope`."
  }
}

variable "resource_group_name" {
  description = "(REQUIRED) Existing resource group that will hold the namespace and hubs."
  type        = string

  validation {
    condition     = can(regex("^[-a-zA-Z0-9._()]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid resource group name (1-90 characters)."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NAMING                                                          ║
# ╚════════════════════════════════════════════════════════════════╝

variable "namespace_name" {
  description = "(OPTIONAL) Namespace name. Defaults to `ns-<organization>-<environment>-<region_short>-<instance>`. Must be globally unique because it becomes <name>.servicebus.windows.net."
  type        = string
  default     = null

  validation {
    condition     = var.namespace_name == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$", var.namespace_name))
    error_message = "namespace_name must be 6-50 characters of [a-zA-Z0-9-] and may not start or end with a hyphen."
  }
}

variable "hub_name_prefix" {
  description = "(OPTIONAL) Prefix for generated hub names (`<prefix>-<key>`). Defaults to `nh-<organization>-<environment>`."
  type        = string
  default     = null

  validation {
    condition     = var.hub_name_prefix == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,60}[a-zA-Z0-9._:-]$", var.hub_name_prefix))
    error_message = "hub_name_prefix must be 2-62 characters of [a-zA-Z0-9._:-] starting and ending with an allowed character."
  }
}

variable "instance_number" {
  description = "(OPTIONAL) Numeric suffix (zero padded to 3) used only when `namespace_name` is generated."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_number >= 1 && var.instance_number <= 999
    error_message = "instance_number must be between 1 and 999."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NAMESPACE CONFIG                                                ║
# ╚════════════════════════════════════════════════════════════════╝

variable "sku_name" {
  description = <<-EOT
    (OPTIONAL) Namespace tier:
      Free     - 1 hub, 1M notifications/month, no SLA - dev only (rejected for prod/uat/dr).
      Basic    - 10M notifications/month, no auto-forwarding.
      Standard - unlimited notifications, 10 hubs, Service Bus backend, 99.9% SLA. Required for production.
  EOT
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Free", "Basic", "Standard"], var.sku_name)
    error_message = "sku_name must be Free, Basic or Standard."
  }
}

variable "enabled" {
  description = "(OPTIONAL) Whether the namespace accepts traffic. Setting false suspends every hub inside it - rejected for prod/uat/dr."
  type        = bool
  default     = true
}

variable "allow_sandbox_apns_in_production" {
  description = "(OPTIONAL) Set true to permit application_mode = \"Sandbox\" APNs credentials outside dev/staging (not recommended - Apple delivers only to TestFlight/Ad Hoc builds)."
  type        = bool
  default     = false
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  THE HUBS                                                        ║
# ║                                                                  ║
# ║  One map entry == one `azurerm_notification_hub`.                ║
# ║  Platform credentials are optional so a hub can be created       ║
# ║  before the Apple/Google artefacts exist (bring your own later). ║
# ╚════════════════════════════════════════════════════════════════╝

variable "hubs" {
  description = <<-EOT
    (REQUIRED) Notification hubs to create inside the namespace.

      name            - explicit hub name; defaults to `<hub_name_prefix>-<key>`.
      apns.bundle_id  - iOS/macOS app id, e.g. com.contoso.myapp.
      apns.key_id     - 10 character APNs key id from Apple Developer > Keys.
      apns.team_id    - 10 character Apple developer team id.
      apns.token      - contents of the .p8 private key WITHOUT the BEGIN/END lines.
                        Feed it from a secret store, e.g.
                          token = data.azurerm_key_vault_secret.apns.value
      apns.application_mode - "Sandbox" (dev) or "Production".
      fcm_api_key     - Google Cloud Project API key (legacy FCM server key accepted by Notification Hubs).
      registration_ttl - optional registration time to live in seconds (managed client side; kept as a tag for audit).

    Example:
      hubs = {
        ios = {
          apns = {
            bundle_id        = "com.contoso.myapp"
            key_id           = "2X9R4HXF34"
            team_id          = "APPNJTV5QQ"
            token            = data.azurerm_key_vault_secret.apns_p8.value
            application_mode = "Production"
          }
        }
        android = { fcm_api_key = data.azurerm_key_vault_secret.fcm.value }
      }
  EOT
  type = map(object({
    name = optional(string)
    apns = optional(object({
      bundle_id        = optional(string)
      key_id           = optional(string)
      team_id          = optional(string)
      token            = optional(string)
      application_mode = optional(string, "Sandbox")
    }))
    fcm_api_key = optional(string)
    registration_ttl_seconds = optional(number)
    tags                     = optional(map(string), {})
  }))

  validation {
    condition     = length(var.hubs) > 0
    error_message = "hubs must declare at least one hub."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.apns, null) == null || try(hub.apns.application_mode, null) == null || contains(["Sandbox", "Production"], hub.apns.application_mode)
    ])
    error_message = "hubs[...].apns.application_mode must be `Sandbox` or `Production`."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.apns, null) == null || (
        (try(hub.apns.key_id, null) == null ? true : can(regex("^[A-Z0-9]{10}$", hub.apns.key_id)))
        && (try(hub.apns.team_id, null) == null ? true : can(regex("^[A-Z0-9]{10}$", hub.apns.team_id)))
      )
    ])
    error_message = "APNs key_id and team_id are 10 character uppercase alphanumeric strings, e.g. `2X9R4HXF34`."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.apns.bundle_id, null) == null || can(regex("^[a-zA-Z0-9.-]{3,100}$", hub.apns.bundle_id))
    ])
    error_message = "APNs bundle_id must look like a reverse-DNS identifier, e.g. com.contoso.myapp."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.fcm_api_key, null) == null || length(trimspace(hub.fcm_api_key)) >= 20
    ])
    error_message = "fcm_api_key looks truncated; a Google API key is at least 20 characters (use `AA...` server keys from the GCP project)."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.registration_ttl_seconds, null) == null || (hub.registration_ttl_seconds >= 1 && hub.registration_ttl_seconds <= 2592000)
    ])
    error_message = "registration_ttl_seconds must be between 1 second and 30 days (2592000)."
  }

  validation {
    condition = alltrue([
      for key, hub in var.hubs :
      try(hub.name, null) == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._:-]{0,258}[a-zA-Z0-9._:-]$", hub.name))
    ])
    error_message = "hubs[...].name must be 1-260 characters of [a-zA-Z0-9._:-] and may not start with a hyphen."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPTIONAL EXTRAS                                                 ║
# ╚════════════════════════════════════════════════════════════════╝

variable "lock" {
  description = "(OPTIONAL) Management lock on the namespace. `CanNotDelete` stops a hub namespace (and therefore every app's push channel) from being deleted by accident."
  type = object({
    kind = optional(string, "CanNotDelete")
    name = optional(string)
  })
  default = null

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], coalesce(var.lock.kind, "CanNotDelete"))
    error_message = "lock.kind must be `CanNotDelete` or `ReadOnly`."
  }
}

variable "tags" {
  description = "(OPTIONAL) Extra tags merged onto the standard tag set."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.tags : length(k) <= 512 && length(v) <= 256])
    error_message = "Azure tags are limited to 512 characters for keys and 256 for values."
  }
}
