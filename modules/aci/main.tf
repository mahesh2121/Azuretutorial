# ╔══════════════════════════════════════════════════════════════════╗
# ║  CONTAINER GROUPS (ACI)                                          ║
# ║                                                                  ║
# ║  Guardrails enforced at plan time by preconditions:              ║
# ║  • Windows => exactly one container, no VNet injection           ║
# ║  • Private IPs require delegated subnets, FQDN labels do not     ║
# ║  • Spot priority implies ip_address_type = "None"                ║
# ║  • system-assigned identity cannot combine with VNet injection   ║
# ║  • registry access needs either an identity or user + password   ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_container_group" "this" {
  for_each = local.container_groups

  name                = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type         = each.value.os_type
  restart_policy  = each.value.restart_policy
  ip_address_type = each.value.ip_address_type
  priority        = each.value.priority
  sku             = each.value.sku

  zones        = length(each.value.zones) > 0 ? each.value.zones : null
  subnet_ids   = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : null
  dns_name_label                = each.value.dns_name_label
  dns_name_label_reuse_policy   = each.value.dns_name_label_reuse_policy
  key_vault_key_id              = each.value.key_vault_key_id
  key_vault_user_assigned_identity_id = each.value.key_vault_user_assigned_identity_id

  # ─── APP CONTAINERS ───────────────────────────────────────────────
  dynamic "container" {
    for_each = each.value.containers
    content {
      name         = container.value.name
      image        = container.value.image
      cpu          = container.value.cpu
      memory       = container.value.memory
      cpu_limit    = container.value.cpu_limit
      memory_limit = container.value.memory_limit

      commands = length(container.value.commands) > 0 ? container.value.commands : null

      environment_variables        = length(container.value.environment_variables) > 0 ? container.value.environment_variables : null
      secure_environment_variables = length(container.value.secure_environment_variables) > 0 ? container.value.secure_environment_variables : null

      dynamic "ports" {
        for_each = container.value.ports
        content {
          port     = ports.value.port
          protocol = ports.value.protocol
        }
      }

      # Volumes are declared once on the group and mounted by name, so every
      # container that lists a name in `volume_mounts` gets the same block.
      dynamic "volume" {
        for_each = [for spec in each.value.volumes : spec if contains(container.value.volume_mounts, spec.name)]
        content {
          name                 = volume.value.name
          mount_path           = volume.value.mount_path
          read_only            = volume.value.read_only ? true : null
          empty_dir            = volume.value.is_empty_dir ? true : null
          secret               = length(volume.value.secret) > 0 ? volume.value.secret : null
          storage_account_name = volume.value.storage_account
          storage_account_key  = volume.value.storage_account_key
          share_name           = volume.value.share_name
        }
      }

      dynamic "liveness_probe" {
        for_each = container.value.liveness_probe == null ? [] : [container.value.liveness_probe]
        content {
          exec                  = length(liveness_probe.value.exec) > 0 ? liveness_probe.value.exec : null
          initial_delay_seconds = liveness_probe.value.initial_delay_seconds
          period_seconds        = liveness_probe.value.period_seconds
          failure_threshold     = liveness_probe.value.failure_threshold
          success_threshold     = liveness_probe.value.success_threshold
          timeout_seconds       = liveness_probe.value.timeout_seconds

          dynamic "http_get" {
            for_each = liveness_probe.value.http_get == null ? [] : [liveness_probe.value.http_get]
            content {
              path         = http_get.value.path
              port         = http_get.value.port
              scheme       = http_get.value.scheme
              http_headers = length(http_get.value.http_headers) > 0 ? http_get.value.http_headers : null
            }
          }
        }
      }

      dynamic "readiness_probe" {
        for_each = container.value.readiness_probe == null ? [] : [container.value.readiness_probe]
        content {
          exec                  = length(readiness_probe.value.exec) > 0 ? readiness_probe.value.exec : null
          initial_delay_seconds = readiness_probe.value.initial_delay_seconds
          period_seconds        = readiness_probe.value.period_seconds
          failure_threshold     = readiness_probe.value.failure_threshold
          success_threshold     = readiness_probe.value.success_threshold
          timeout_seconds       = readiness_probe.value.timeout_seconds

          dynamic "http_get" {
            for_each = readiness_probe.value.http_get == null ? [] : [readiness_probe.value.http_get]
            content {
              path         = http_get.value.path
              port         = http_get.value.port
              scheme       = http_get.value.scheme
              http_headers = length(http_get.value.http_headers) > 0 ? http_get.value.http_headers : null
            }
          }
        }
      }

      # `security` only applies to Confidential SKUs - ACI rejects it elsewhere.
      dynamic "security" {
        for_each = container.value.privilege_enabled == null ? [] : [1]
        content {
          privilege_enabled = container.value.privilege_enabled
        }
      }
    }
  }

  # ─── INIT CONTAINERS ──────────────────────────────────────────────
  dynamic "init_container" {
    for_each = each.value.init_containers
    content {
      name  = init_container.value.name
      image = init_container.value.image

      commands                     = length(init_container.value.commands) > 0 ? init_container.value.commands : null
      environment_variables        = length(init_container.value.environment_variables) > 0 ? init_container.value.environment_variables : null
      secure_environment_variables = length(init_container.value.secure_environment_variables) > 0 ? init_container.value.secure_environment_variables : null

      dynamic "volume" {
        for_each = [for spec in each.value.volumes : spec if contains(init_container.value.volume_mounts, spec.name)]
        content {
          name       = volume.value.name
          mount_path = volume.value.mount_path
          read_only  = volume.value.read_only ? true : null
          empty_dir  = volume.value.is_empty_dir ? true : null
          secret     = length(volume.value.secret) > 0 ? volume.value.secret : null
        }
      }
    }
  }

  # ─── EXPOSED PORTS (public/private IP front door) ─────────────────
  dynamic "exposed_port" {
    for_each = each.value.exposed_ports
    content {
      port     = exposed_port.value.port
      protocol = exposed_port.value.protocol
    }
  }

  # ─── PRIVATE REGISTRY PULL ────────────────────────────────────────
  # `identity_id` is the recommended mode: ACI authenticates with a managed
  # identity that holds AcrPull, so no registry secret ever lands in state.
  dynamic "image_registry_credential" {
    for_each = each.value.registry_enabled ? [1] : []
    content {
      server                    = each.value.registry_server
      username                    = each.value.registry_uses_secrets ? each.value.registry_username : null
      password                    = each.value.registry_uses_secrets ? each.value.registry_password : null
      user_assigned_identity_id   = each.value.registry_uses_identity ? each.value.registry_identity_id : null
    }
  }

  # ─── LOG ANALYTICS ────────────────────────────────────────────────
  dynamic "diagnostics" {
    for_each = each.value.diagnostics_enabled ? [1] : []
    content {
      log_analytics {
        log_type      = each.value.diagnostics_log_type
        workspace_id  = each.value.diagnostics_workspace_id
        workspace_key = each.value.diagnostics_workspace_key
        metadata      = length(each.value.diagnostics_metadata) > 0 ? each.value.diagnostics_metadata : null
      }
    }
  }

  # ─── CUSTOM DNS ───────────────────────────────────────────────────
  dynamic "dns_config" {
    for_each = each.value.dns_config == null ? [] : [each.value.dns_config]
    content {
      nameservers    = dns_config.value.nameservers
      search_domains = length(dns_config.value.search_domains) > 0 ? dns_config.value.search_domains : null
      options        = length(dns_config.value.options) > 0 ? dns_config.value.options : null
    }
  }

  # ─── IDENTITY ─────────────────────────────────────────────────────
  dynamic "identity" {
    for_each = each.value.identity_type != "None" ? [1] : []
    content {
      type         = each.value.identity_type
      identity_ids = length(each.value.identity_ids) > 0 ? each.value.identity_ids : null
    }
  }

  tags = each.value.tags

  # ─── GUARDRAILS (evaluated during plan) ───────────────────────────
  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", each.value.name))
      error_message = "Container group name \"${each.value.name}\" must be 1-63 lowercase alphanumeric/hyphen characters, starting and ending with a letter or digit. Set container_groups[\"${each.key}\"].name or var.name_prefix."
    }

    # Azure: Windows groups support a single container and no VNet injection.
    precondition {
      condition = !(
        each.value.os_type == "Windows"
        && (length(each.value.containers) > 1 || length(each.value.subnet_ids) > 0 || length(each.value.init_containers) > 0)
      )
      error_message = "container_groups[\"${each.key}\"]: os_type = \"Windows\" supports exactly one container, no init containers and no virtual network (subnet_ids)."
    }

    precondition {
      condition     = each.value.ip_address_type != "Private" || length(each.value.subnet_ids) > 0
      error_message = "container_groups[\"${each.key}\"]: ip_address_type = \"Private\" requires subnet_ids pointing at a subnet delegated to Microsoft.ContainerInstance/containerGroups."
    }

    precondition {
      condition     = each.value.ip_address_type != "Public" || length(each.value.subnet_ids) == 0
      error_message = "container_groups[\"${each.key}\"]: subnet_ids (VNet injection) require ip_address_type = \"Private\", not \"Public\"."
    }

    precondition {
      condition     = each.value.dns_name_label == null || each.value.ip_address_type == "Public"
      error_message = "container_groups[\"${each.key}\"]: dns_name_label is only supported with ip_address_type = \"Public\"."
    }

    precondition {
      condition     = each.value.priority != "Spot" || each.value.ip_address_type == "None"
      error_message = "container_groups[\"${each.key}\"]: priority = \"Spot\" requires ip_address_type = \"None\" (Azure never assigns an IP to spot groups)."
    }

    # Azure still refuses a *system-assigned* identity on VNet-injected groups
    # (user-assigned identities, which is what image pulls need, do work).
    precondition {
      condition     = !(each.value.system_assigned_identity && length(each.value.subnet_ids) > 0)
      error_message = "container_groups[\"${each.key}\"]: system-assigned identities cannot be used with subnet_ids. Use a user-assigned identity (user_assigned_identity_ids) for image pulls instead."
    }

    precondition {
      condition     = !each.value.registry_declared || each.value.registry_enabled
      error_message = "container_groups[\"${each.key}\"].registry needs either identity_id (preferred) or both username and password to pull from a private registry."
    }

    precondition {
      condition     = !each.value.registry_enabled || each.value.registry_server != null
      error_message = "container_groups[\"${each.key}\"]: a registry block needs `server` (or set var.default_registry_server) - the value must be a host name without https://, e.g. myregistry.azurecr.io."
    }

    precondition {
      condition = alltrue([
        for id in concat(each.value.identity_ids, compact([coalesce(each.value.registry_identity_id, "")])) :
        can(regex("/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[^/]+$", id))
      ])
      error_message = "container_groups[\"${each.key}\"]: identity ids (identity_ids / registry.identity_id / key_vault_user_assigned_identity_id) must be full user-assigned managed identity resource IDs."
    }

    # Customer managed keys need an identity that can read the key; without it
    # the group fails to start with an unhelpful VMExtension error.
    precondition {
      condition     = each.value.key_vault_key_id == null || each.value.key_vault_user_assigned_identity_id != null
      error_message = "container_groups[\"${each.key}\"]: key_vault_key_id requires key_vault_user_assigned_identity_id so ACI can unwrap the key."
    }

    precondition {
      condition     = !each.value.diagnostics_enabled || (each.value.diagnostics_workspace_id != null && each.value.diagnostics_workspace_key != null)
      error_message = "container_groups[\"${each.key}\"]: diagnostics need both workspace_id and workspace_key. Read the key from a data source (e.g. azurerm_log_analytics_workspace) or set var.diagnostics_workspace_shared_key."
    }

    precondition {
      condition = (
        !each.value.diagnostics_enabled
        || contains(["ContainerInsights", "ContainerInstanceLogs"], each.value.diagnostics_log_type)
      )
      error_message = "container_groups[\"${each.key}\"]: diagnostics.log_type must be ContainerInsights or ContainerInstanceLogs."
    }

    # ACI writes to Log Analytics need the workspace to exist first; metadata
    # keys are free-form so only the count is bounded by the service.
    precondition {
      condition     = each.value.diagnostics_metadata == null || length(each.value.diagnostics_metadata) <= 20
      error_message = "container_groups[\"${each.key}\"]: diagnostics.metadata supports at most 20 key/value pairs."
    }

    precondition {
      condition = alltrue([
        for port in [for exposed in each.value.exposed_ports : exposed.port] :
        contains(local.container_ports_by_group[each.key], port)
      ])
      error_message = "container_groups[\"${each.key}\"]: every exposed_ports entry must also be declared on a container's ports (Azure requirement)."
    }

    precondition {
      condition = alltrue(flatten([
        for container in each.value.containers : [
          for mount in container.volume_mounts :
          contains(local.volume_names_by_group[each.key], mount)
        ]
      ]))
      error_message = "container_groups[\"${each.key}\"]: container volume_mounts must reference a volume declared in the group's volumes list."
    }

    # Azure sizing rules: cpu in 0.1 steps between 0.1 and 64, memory in 0.5 GB
    # steps between 0.5 and 512 GiB. Getting this wrong is a 400 from RP, not a
    # plan error, so the module enforces it up front.
    precondition {
      condition = alltrue([
        for container in each.value.containers : (
          abs(floor(container.cpu * 10) - container.cpu * 10) < 0.0001
          && abs(floor(container.memory * 2) - container.memory * 2) < 0.0001
          && container.cpu >= 0.1
          && container.cpu <= 64
          && container.memory >= 0.5
          && container.memory <= 512
        )
      ])
      error_message = "container_groups[\"${each.key}\"]: container cpu must be a multiple of 0.1 between 0.1 and 64 and memory a multiple of 0.5 GB between 0.5 and 512 - see the ACI resource size limits."
    }

    precondition {
      condition = alltrue(flatten([
        for container in each.value.containers : [
          try(container.cpu_limit, null) == null ? true : container.cpu_limit >= container.cpu,
          try(container.memory_limit, null) == null ? true : container.memory_limit >= container.memory
        ]
      ]))
      error_message = "container_groups[\"${each.key}\"]: cpu_limit/memory_limit must be greater than or equal to the requested cpu/memory."
    }

    precondition {
      condition     = !var.enforce_no_public_ip_for_production || !local.production_like || length(local.groups_with_public_ip) == 0
      error_message = "enforce_no_public_ip_for_production is on and this is a prod/uat/dr deployment: every container group must use ip_address_type = \"Private\" with a delegated subnet. Offending groups: ${join(", ", local.groups_with_public_ip)}."
    }

    precondition {
      condition = !var.enforce_probes_for_production || !local.production_like || alltrue(flatten([
        for key, group in local.container_groups : [
          for container in group.containers : container.liveness_probe != null && container.readiness_probe != null
        ]
      ]))
      error_message = "enforce_probes_for_production is on and this is a prod/uat/dr deployment: every container must declare a liveness_probe and a readiness_probe."
    }
  }
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  DELETION PROTECTION  (optional, per group)                      ║
# ╚════════════════════════════════════════════════════════════════╝

resource "azurerm_management_lock" "this" {
  for_each = local.lock_enabled ? local.container_groups : {}

  name       = coalesce(try(var.lock.name, null), "lock-${each.value.name}")
  lock_level = local.lock_kind
  notes      = "Managed by Terraform (modules/aci). Remove the lock variable before deleting ${each.value.name}."

  resource_name       = azurerm_container_group.this[each.key].name
  resource_group_name = var.resource_group_name
  type                = "Microsoft.ContainerInstance/containerGroups"
}
