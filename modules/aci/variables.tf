# ╔══════════════════════════════════════════════════════════════════╗
# ║  REQUIRED INPUTS                                                 ║
# ╚══════════════════════════════════════════════════════════════════╝

variable "environment" {
  description = "(REQUIRED) Environment name: dev, staging, uat, prod or dr. Drives naming and tagging."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "uat", "prod", "dr"], lower(var.environment))
    error_message = "environment must be one of: dev, staging, uat, prod, dr."
  }
}

variable "organization" {
  description = "(REQUIRED) Organisation short code used in container group names and the `Organization` tag. Lowercase alphanumeric, max 10 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.organization))
    error_message = "organization must be 1-10 lowercase alphanumeric characters (a-z0-9)."
  }
}

variable "location" {
  description = "(REQUIRED) Azure region for the container groups, e.g. `eastus`."
  type        = string

  validation {
    condition     = length(var.location) > 0 && var.location == lower(replace(var.location, " ", ""))
    error_message = "location must be a lowercase Azure region without spaces, e.g. `eastus` or `westeurope`."
  }
}

variable "resource_group_name" {
  description = "(REQUIRED) Existing resource group that will hold the container groups."
  type        = string

  validation {
    condition     = can(regex("^[-a-zA-Z0-9._()]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be a valid resource group name (1-90 characters)."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  NAMING                                                          ║
# ╚════════════════════════════════════════════════════════════════╝

variable "name_prefix" {
  description = "(OPTIONAL) Prefix for generated container group names (`<prefix>-<key>`). Defaults to `aci-<organization>-<environment>`."
  type        = string
  default     = null

  validation {
    condition     = var.name_prefix == null || can(regex("^[a-z0-9][a-z0-9-]{0,38}[a-z0-9]$", var.name_prefix))
    error_message = "name_prefix must be 2-40 lowercase alphanumeric/hyphen characters, starting and ending with a letter or digit."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  THE CONTAINER GROUPS                                            ║
# ║                                                                  ║
# ║  One map entry == one `azurerm_container_group` == one pod-like  ║
# ║  ACI instance. Everything except name/image/cpu/memory in a      ║
# ║  container is optional so small workloads stay one-liners.       ║
# ╚════════════════════════════════════════════════════════════════╝

variable "container_groups" {
  description = <<-EOT
    (REQUIRED) Map of container groups to create.

    Group level:
      name                      - override the generated `<prefix>-<key>` name.
      os_type                   - `Linux` (default) or `Windows`.
      restart_policy            - `Always` (default), `Never`, `OnFailure`.
      ip_address_type           - `Public` (default), `Private` (needs subnet_ids), `None` (needed for Spot).
      subnet_ids                - resource IDs of subnets delegated to Microsoft.ContainerInstance/containerGroups.
      dns_name_label            - public FQDN label; only valid with a Public IP.
      dns_name_label_reuse_policy - `Noreuse` (recommended) / `ResourceGroupReuse` / `SubscriptionReuse` / `TenantReuse` / `Unsecure`.
      priority                  - `Regular` (default) or `Spot` (Spot requires ip_address_type = "None").
      sku                       - `Standard` (default), `Dedicated`, `Confidential`.
      zones                     - availability zones, e.g. ["1","2","3"].
      system_assigned_identity  - adds a managed identity (not supported with VNet-injected groups).
      user_assigned_identity_ids - user-assigned identity resource IDs (used for ACR pulls and Key Vault).
      registry                  - private registry access. Prefer `identity_id` over username/password.
      diagnostics               - Log Analytics workspace id + key for container logs.
      dns_config / exposed_ports/ tags - as their names suggest.
      containers               - the workload containers (see below).
      init_containers          - run-to-completion containers executed before `containers`.
      volumes                  - group-level volume definitions referenced by containers by name.

    Container level:
      name, image, cpu, memory are required. cpu/memory follow Azure ACI rules
      (Linux: cpu >= 0.5 in 0.1 steps, memory >= 1.5 in 0.5 steps).
      Optional: cpu_limit, memory_limit, commands, ports, environment_variables,
      secure_environment_variables, liveness_probe, readiness_probe,
      volume_mounts (list of volume names defined on the group).
  EOT
  type = map(object({
    name                      = optional(string)
    os_type                   = optional(string, "Linux")
    restart_policy            = optional(string, "Always")
    ip_address_type           = optional(string, "Public")
    subnet_ids                = optional(list(string), [])
    dns_name_label            = optional(string)
    dns_name_label_reuse_policy = optional(string)
    priority                  = optional(string, "Regular")
    sku                       = optional(string, "Standard")
    zones                     = optional(list(string), [])
    system_assigned_identity   = optional(bool, false)
    user_assigned_identity_ids = optional(list(string), [])
    registry = optional(object({
      server      = optional(string)
      username    = optional(string)
      password    = optional(string, null)
      identity_id = optional(string, null)
    }))
    diagnostics = optional(object({
      workspace_id  = string
      workspace_key = string
      log_type      = optional(string, "ContainerInstanceLogs")
      metadata      = optional(map(string), {})
    }))
    dns_config = optional(object({
      nameservers    = list(string)
      search_domains = optional(list(string), [])
      options        = optional(list(string), [])
    }))
    exposed_ports = optional(list(object({
      port     = number
      protocol = optional(string, "TCP")
    })), [])
    containers = list(object({
      name                         = string
      image                        = string
      cpu                          = number
      memory                       = number
      cpu_limit                    = optional(number)
      memory_limit                 = optional(number)
      commands                     = optional(list(string), [])
      ports = optional(list(object({
        port     = number
        protocol = optional(string, "TCP")
      })), [])
      environment_variables        = optional(map(string), {})
      secure_environment_variables = optional(map(string), {})
      volume_mounts                = optional(list(string), [])
      liveness_probe = optional(object({
        exec                  = optional(list(string), [])
        http_get = optional(object({
          path         = optional(string)
          port         = optional(number)
          scheme       = optional(string)
          http_headers = optional(map(string), {})
        }))
        initial_delay_seconds = optional(number)
        period_seconds        = optional(number)
        failure_threshold     = optional(number)
        success_threshold     = optional(number)
        timeout_seconds       = optional(number)
      }))
      readiness_probe = optional(object({
        exec                  = optional(list(string), [])
        http_get = optional(object({
          path         = optional(string)
          port         = optional(number)
          scheme       = optional(string)
          http_headers = optional(map(string), {})
        }))
        initial_delay_seconds = optional(number)
        period_seconds        = optional(number)
        failure_threshold     = optional(number)
        success_threshold     = optional(number)
        timeout_seconds       = optional(number)
      }))
      security = optional(object({
        privilege_enabled = optional(bool, false)
      }))
    }))
    init_containers = optional(list(object({
      name                         = string
      image                        = string
      commands                     = optional(list(string), [])
      environment_variables        = optional(map(string), {})
      secure_environment_variables = optional(map(string), {})
      volume_mounts                = optional(list(string), [])
    })), [])
    volumes = optional(list(object({
      name               = string
      mount_path         = optional(string)
      read_only          = optional(bool, false)
      empty_dir          = optional(bool, false)
      secret             = optional(map(string), {})
      share_name         = optional(string)
      storage_account    = optional(string)
      storage_account_key = optional(string)
    })), [])
    key_vault_key_id                       = optional(string)
    key_vault_user_assigned_identity_id    = optional(string)
    tags                                   = optional(map(string), {})
  }))

  validation {
    condition     = length(var.container_groups) > 0
    error_message = "container_groups must declare at least one container group."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      length(group.containers) >= 1 && length(group.containers) <= 20
    ])
    error_message = "each container group needs between 1 and 20 containers."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      contains(["Linux", "Windows"], coalesce(group.os_type, "Linux"))
    ])
    error_message = "container_groups[...].os_type must be `Linux` or `Windows`."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      contains(["Always", "Never", "OnFailure"], coalesce(group.restart_policy, "Always"))
    ])
    error_message = "container_groups[...].restart_policy must be Always, Never or OnFailure."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      contains(["Public", "Private", "None"], coalesce(group.ip_address_type, "Public"))
    ])
    error_message = "container_groups[...].ip_address_type must be Public, Private or None."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      contains(["Regular", "Spot"], coalesce(group.priority, "Regular"))
    ])
    error_message = "container_groups[...].priority must be Regular or Spot."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      contains(["Standard", "Dedicated", "Confidential"], coalesce(group.sku, "Standard"))
    ])
    error_message = "container_groups[...].sku must be Standard, Dedicated or Confidential."
  }

  validation {
    condition = alltrue(flatten([
      for key, group in var.container_groups : [
        for c in group.containers : can(regex("^[a-z0-9]([-a-z0-9]{0,28}[a-z0-9])?$", c.name))
      ]
    ]))
    error_message = "container names must be 1-30 lowercase alphanumeric/hyphen characters that start and end with a letter or digit."
  }

  validation {
    condition = alltrue(flatten([
      for key, group in var.container_groups : [
        for c in group.containers : length(c.image) > 0 && !startswith(c.image, "http://")
      ]
    ]))
    error_message = "every container needs an image reference without an http:// scheme (use `registry/repo:tag`)."
  }

  validation {
    condition = alltrue(flatten([
      for key, group in var.container_groups : [
        for c in group.containers : c.cpu >= 0.5 && c.memory >= 1.5
      ]
    ]))
    error_message = "ACI requires cpu >= 0.5 cores and memory >= 1.5 GB per container."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      length(coalesce(group.volumes, [])) == length(distinct([for v in coalesce(group.volumes, []) : v.name]))
    ])
    error_message = "volume names must be unique within a container group."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      alltrue([
        for v in coalesce(group.volumes, []) :
        (
          (try(v.empty_dir, false) ? 1 : 0)
          + (length(try(v.secret, {})) > 0 ? 1 : 0)
          + (try(v.share_name, null) != null ? 1 : 0)
        ) == 1
      ])
    ])
    error_message = "each volume must declare exactly one source: empty_dir = true, a non-empty secret map, or an Azure Files share (share_name + storage_account + storage_account_key)."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      alltrue([
        for v in coalesce(group.volumes, []) :
        try(v.share_name, null) == null || (try(v.storage_account, null) != null && try(v.storage_account_key, null) != null)
      ])
    ])
    error_message = "an Azure Files volume needs all of share_name, storage_account and storage_account_key."
  }

  validation {
    condition = alltrue([
      for key, group in var.container_groups :
      alltrue([
        for v in coalesce(group.volumes, []) :
        try(v.mount_path, null) == null || can(regex("^/[a-zA-Z0-9._/-]*$", v.mount_path))
      ])
    ])
    error_message = "volume mount_path must be an absolute Linux path, e.g. /mnt/secrets."
  }

  validation {
    condition = alltrue(flatten([
      for key, group in var.container_groups : [
        for c in concat(group.containers, coalesce(group.init_containers, [])) :
        length(setsubtract(coalesce(c.volume_mounts, []), [for v in coalesce(group.volumes, []) : v.name])) == 0
      ]
    ]))
    error_message = "every entry in a container's volume_mounts must match a volume name declared on the same container group."
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  OPTIONAL GLOBALS                                                ║
# ╚════════════════════════════════════════════════════════════════╝

variable "diagnostics_workspace_resource_id" {
  description = "(OPTIONAL) Log Analytics workspace resource ID applied to every container group that does not set its own `diagnostics`. Ignored when `enable_diagnostics` is false."
  type        = string
  default     = null
}

variable "diagnostics_workspace_shared_key" {
  description = "(OPTIONAL) Primary shared key for `diagnostics_workspace_resource_id`. Supply it from a data source or variable file that is never committed; it is marked sensitive so Terraform will not echo it."
  type        = string
  default     = null
  sensitive   = true
}

variable "enable_diagnostics" {
  description = "(OPTIONAL) Master switch for the global diagnostics settings above."
  type        = bool
  default     = false
}

variable "default_registry_server" {
  description = "(OPTIONAL) Registry server (e.g. an ACR login server) injected into groups whose `registry.server` is null but which use managed-identity pulls."
  type        = string
  default     = null
}

variable "default_user_assigned_identity_id" {
  description = "(OPTIONAL) User-assigned identity added to every group that does not declare its own. Typical use: one identity with `AcrPull` on the registry."
  type        = string
  default     = null
}

variable "enforce_no_public_ip_for_production" {
  description = "(OPTIONAL) When true, prod/uat/dr groups must use ip_address_type = \"Private\" with a delegated subnet. Recommended for production workloads."
  type        = bool
  default     = false
}

variable "enforce_probes_for_production" {
  description = "(OPTIONAL) When true, every container in prod/uat/dr must declare both a liveness_probe and a readiness_probe."
  type        = bool
  default     = false
}

variable "lock" {
  description = "(OPTIONAL) Management lock applied to every container group. `CanNotDelete` prevents accidental teardown of a running workload."
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
  description = "(OPTIONAL) Extra tags merged onto the standard tag set for every resource."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.tags : length(k) <= 512 && length(v) <= 256])
    error_message = "Azure tags are limited to 512 characters for keys and 256 for values."
  }
}
