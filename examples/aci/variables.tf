# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE INPUTS - ACI quickstart                                 ║
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
  description = "(REQUIRED) Azure region for the container groups."
  type        = string
}

variable "container_image" {
  description = "(OPTIONAL) Image the web container runs. Point it at your ACR login server for private images."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/aci-helloworld:latest"
}

variable "cron_image" {
  description = "(OPTIONAL) Image for the batch/scheduled container group."
  type        = string
  default     = "mcr.microsoft.com/azure-cli:latest"
}

variable "cpu_cores" {
  description = "(OPTIONAL) Requested CPU per container, in 0.1 steps starting at 0.5."
  type        = number
  default     = 0.5
}

variable "memory_gb" {
  description = "(OPTIONAL) Requested memory per container in GB, in 0.5 steps starting at 1.5."
  type        = number
  default     = 1.5
}

variable "use_private_ip" {
  description = "(OPTIONAL) Attach the groups to delegated subnets and give them private IPs only."
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "(OPTIONAL) Subnet resource IDs delegated to Microsoft.ContainerInstance/containerGroups. Required when use_private_ip = true."
  type        = list(string)
  default     = []
}

variable "dns_name_label" {
  description = "(OPTIONAL) Public DNS label for the web group (global, so keep it unique). Ignored with a private IP."
  type        = string
  default     = null

  validation {
    condition     = var.dns_name_label == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.dns_name_label))
    error_message = "dns_name_label must be 3-63 lowercase alphanumeric/hyphen characters."
  }
}

variable "user_assigned_identity_id" {
  description = "(OPTIONAL) User-assigned identity resource ID used to pull images from a private registry. Grant it `AcrPull` on the registry."
  type        = string
  default     = null
}

variable "registry_server" {
  description = "(OPTIONAL) Private registry host (no scheme) the identity pulls from, e.g. `acrcontosodeveus001.azurecr.io`."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "(OPTIONAL) Log Analytics workspace resource ID for container logs."
  type        = string
  default     = ""
}

variable "log_analytics_workspace_key" {
  description = "(OPTIONAL) Primary shared key of the workspace above. Read it from a data source or pass it from CI - never commit it."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_lock" {
  description = "(OPTIONAL) CanNotDelete lock on every container group."
  type        = bool
  default     = false
}

variable "tags" {
  description = "(OPTIONAL) Extra tags merged onto the standard tag set."
  type        = map(string)
  default     = {}
}
