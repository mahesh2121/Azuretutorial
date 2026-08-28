# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE INPUTS                                                  ║
# ║  Everything a team needs to flip between dev and prod.           ║
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
  description = "(REQUIRED) Azure region for every resource in this stack."
  type        = string
}

variable "app_name" {
  description = "(REQUIRED) Application short name used in the container group and hub names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,20}$", var.app_name))
    error_message = "app_name must be 2-21 lowercase alphanumeric/hyphen characters."
  }
}

variable "image_repository" {
  description = "(OPTIONAL) Repository inside the registry that holds the workload image."
  type        = string
  default     = "web"
}

variable "image_tag" {
  description = "(OPTIONAL) Image tag to deploy. Pin a concrete tag (not `latest`) in prod so rollbacks are possible."
  type        = string
  default     = "1.0.0"
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NETWORKING                                                      ║
# ╚════════════════════════════════════════════════════════════════╝

variable "enable_private_link" {
  description = "(OPTIONAL) Build the hub network, delegate a subnet for ACI, put a private endpoint + private DNS zone on the registry and give ACI a private IP only. Forces registry SKU Premium."
  type        = bool
  default     = false
}

variable "virtual_network_address_space" {
  description = "(OPTIONAL) Address space of the VNet created when enable_private_link = true."
  type        = string
  default     = "10.40.0.0/16"
}

variable "aci_subnet_prefix" {
  description = "(OPTIONAL) Address prefix of the ACI delegated subnet."
  type        = string
  default     = "10.40.1.0/24"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$", var.aci_subnet_prefix))
    error_message = "aci_subnet_prefix must be CIDR notation, e.g. 10.40.1.0/24."
  }
}

variable "private_endpoint_subnet_prefix" {
  description = "(OPTIONAL) Address prefix of the subnet hosting the registry private endpoint."
  type        = string
  default     = "10.40.9.0/28"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$", var.private_endpoint_subnet_prefix))
    error_message = "private_endpoint_subnet_prefix must be CIDR notation, e.g. 10.40.9.0/28."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  REGISTRY / ACI                                                  ║
# ╚════════════════════════════════════════════════════════════════╝

variable "registry_sku" {
  description = "(OPTIONAL) ACR SKU. Premium is required by enable_private_link and by the token/retention settings used here."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.registry_sku)
    error_message = "registry_sku must be Basic, Standard or Premium."
  }
}

variable "aci_cpu_cores" {
  description = "(OPTIONAL) ACI CPU per container (0.1 steps, min 0.5)."
  type        = number
  default     = 0.5
}

variable "aci_memory_gb" {
  description = "(OPTIONAL) ACI memory per container in GB (0.5 steps, min 1.5)."
  type        = number
  default     = 1.5
}

variable "web_port" {
  description = "(OPTIONAL) Container port exposed by the web workload."
  type        = number
  default     = 8080

  validation {
    condition     = var.web_port >= 1 && var.web_port <= 65535
    error_message = "web_port must be a valid TCP port (1-65535)."
  }
}

variable "web_replicas_note" {
  description = "(OPTIONAL) ACI has no replica set - this label is only used for tagging and is documented as such."
  type        = string
  default     = "1 (ACI is a single instance; use AKI/Container Apps for scaling)"
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OBSERVABILITY                                                   ║
# ╚════════════════════════════════════════════════════════════════╝

variable "enable_monitoring" {
  description = "(OPTIONAL) Create a Log Analytics workspace and wire registry diagnostics plus ACI container logs into it."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "(OPTIONAL) Log Analytics retention in days (30-732, or 1 for dev)."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 27900
    error_message = "log_retention_days must be between 1 and 27900 (732 days for most tiers, 1 day for the free tier)."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  PUSH NOTIFICATIONS                                              ║
# ╚════════════════════════════════════════════════════════════════╝

variable "notification_sku" {
  description = "(OPTIONAL) Notification hub namespace tier. Free is refused outside dev by the module."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Free", "Basic", "Standard"], var.notification_sku)
    error_message = "notification_sku must be Free, Basic or Standard."
  }
}

variable "ios_bundle_id" {
  description = "(OPTIONAL) iOS/macOS bundle id for the APNs credential."
  type        = string
  default     = "com.contoso.myapp"
}

variable "apns_key_id" {
  description = "(OPTIONAL) APNs .p8 key id. When null, iOS hubs fall back to the FCM credential only."
  type        = string
  default     = null
}

variable "apns_team_id" {
  description = "(OPTIONAL) Apple developer team id."
  type        = string
  default     = null
}

variable "apns_private_key" {
  description = "(OPTIONAL) APNs .p8 private key body. In real environments source it from Key Vault (see README); never commit it."
  type        = string
  default     = null
  sensitive   = true
}

variable "fcm_api_key" {
  description = "(OPTIONAL) Google API server key for Android delivery. Placeholder is fine for plan, replace before shipping real pushes."
  type        = string
  default     = "AA-placeholder-fcm-server-key-change-me"
  sensitive   = true
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  GUARDRAILS                                                      ║
# ╚════════════════════════════════════════════════════════════════╝

variable "enforce_probes_for_production" {
  description = "(OPTIONAL) Pass straight through to modules/aci: refuse prod/uat/dr containers without liveness and readiness probes."
  type        = bool
  default     = true
}

variable "enforce_private_link_for_production" {
  description = "(OPTIONAL) Refuse prod/uat/dr when enable_private_link = false. Keeps the example runnable in dev while making a public production registry a deliberate act."
  type        = bool
  default     = true
}

variable "tags" {
  description = "(OPTIONAL) Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
