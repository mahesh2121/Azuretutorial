# ╔══════════════════════════════════════════════════════════════════╗
# ║  LOCALS - NORMALISE INPUTS INTO FLAT, CHECKABLE SHAPES           ║
# ║                                                                  ║
# ║  Optional object attributes arrive as null, so every derived     ║
# ║  value is resolved exactly once here. main.tf only assembles     ║
# ║  HCL blocks and never repeats a `try()` chain.                   ║
# ╚══════════════════════════════════════════════════════════════════╝

locals {
  # ─── REGION SHORT CODES (shared convention across this repo) ────
  region_short_codes = {
    "eastus"             = "eus"
    "eastus2"            = "eus2"
    "centralus"          = "cus"
    "northcentralus"     = "ncus"
    "southcentralus"     = "scus"
    "westus2"            = "wus2"
    "westus3"            = "wus3"
    "canadacentral"      = "caca"
    "northeurope"        = "neu"
    "westeurope"         = "weu"
    "uksouth"            = "uks"
    "ukwest"             = "ukw"
    "francecentral"      = "frc"
    "germanywestcentral" = "gwc"
    "switzerlandnorth"   = "swn"
    "swedencentral"      = "sec"
    "uaenorth"           = "uane"
    "southafricanorth"   = "safa"
    "eastasia"           = "eas"
    "southeastasia"      = "sea"
    "japaneast"          = "jae"
    "japanwest"          = "jaw"
    "koreacentral"       = "koc"
    "australiaeast"      = "aus"
    "centralindia"       = "cen"
  }

  location_normalized = replace(var.location, " ", "")
  region_short = try(
    lookup(local.region_short_codes, local.location_normalized, substr(local.location_normalized, 0, 4)),
    local.location_normalized
  )

  name_prefix     = coalesce(try(var.name_prefix, null), "aci-${var.organization}-${var.environment}")
  production_like = contains(["prod", "uat", "dr"], lower(var.environment))

  standard_tags = merge(
    {
      Environment        = var.environment
      Organization       = var.organization
      Service            = "ContainerInstances"
      ManagedBy          = "Terraform"
      Module             = "azure-aci"
      DataClassification = "Confidential"
    },
    var.tags
  )

  # ─── GLOBAL DEFAULTS APPLIED TO EVERY GROUP ───────────────────────
  default_user_assigned_identity_ids = compact([coalesce(try(var.default_user_assigned_identity_id, null), "")])

  global_diagnostics_enabled = var.enable_diagnostics && try(var.diagnostics_workspace_resource_id, null) != null && try(var.diagnostics_workspace_shared_key, null) != null

  global_diagnostics_workspace_id  = local.global_diagnostics_enabled ? var.diagnostics_workspace_resource_id : null
  global_diagnostics_workspace_key = local.global_diagnostics_enabled ? var.diagnostics_workspace_shared_key : null

  # ─── ONE ENTRY PER CONTAINER GROUP ────────────────────────────────
  container_groups = {
    for key, group in var.container_groups : key => {
      key                           = key
      name                          = coalesce(try(group.name, null), "${local.name_prefix}-${key}")
      os_type                       = coalesce(try(group.os_type, null), "Linux")
      restart_policy                = coalesce(try(group.restart_policy, null), "Always")
      ip_address_type               = coalesce(try(group.ip_address_type, null), "Public")
      priority                      = coalesce(try(group.priority, null), "Regular")
      sku                           = coalesce(try(group.sku, null), "Standard")
      zones                         = [for zone in coalesce(try(group.zones, null), []) : zone]
      subnet_ids                    = [for subnet in coalesce(try(group.subnet_ids, null), []) : subnet]
      dns_name_label                = try(group.dns_name_label, null)
      dns_name_label_reuse_policy   = try(group.dns_name_label_reuse_policy, null)
      key_vault_key_id              = try(group.key_vault_key_id, null)
      key_vault_user_assigned_identity_id = try(group.key_vault_user_assigned_identity_id, null)
      tags                          = merge(local.standard_tags, coalesce(try(group.tags, null), {}))

      # ─── MANAGED IDENTITY ─────────────────────────────────────
      identity_ids = length(coalesce(try(group.user_assigned_identity_ids, null), [])) > 0 ? group.user_assigned_identity_ids : local.default_user_assigned_identity_ids
      system_assigned_identity = coalesce(try(group.system_assigned_identity, null), false)
      identity_type =(
        (length(coalesce(try(group.user_assigned_identity_ids, null), [])) > 0 || length(local.default_user_assigned_identity_ids) > 0)
        ? (coalesce(try(group.system_assigned_identity, null), false) ? "SystemAssigned, UserAssigned" : "UserAssigned")
        : (coalesce(try(group.system_assigned_identity, null), false) ? "SystemAssigned" : "None")
      )

      # ─── PRIVATE REGISTRY IMAGE PULL ──────────────────────────
      registry_server     = coalesce(try(group.registry.server, null), try(var.default_registry_server, null))
      registry_username   = try(group.registry.username, null)
      registry_password   = try(group.registry.password, null)
      registry_identity_id = try(group.registry.identity_id, null)
      registry_declared   = try(group.registry, null) != null
      registry_uses_identity = try(group.registry.identity_id, null) != null
      registry_uses_secrets  = try(group.registry.username, null) != null && try(group.registry.password, null) != null
      registry_enabled = (
        try(group.registry, null) != null
        && (try(group.registry.identity_id, null) != null || (try(group.registry.username, null) != null && try(group.registry.password, null) != null))
      )

      # ─── LOG ANALYTICS (container instance logs) ──────────────
      diagnostics_enabled     = try(group.diagnostics, null) != null || local.global_diagnostics_enabled
      diagnostics_workspace_id = try(coalesce(try(group.diagnostics.workspace_id, null), try(local.global_diagnostics_workspace_id, null)), null)
      diagnostics_workspace_key = try(coalesce(try(group.diagnostics.workspace_key, null), try(local.global_diagnostics_workspace_key, null)), null)
      diagnostics_log_type = coalesce(try(group.diagnostics.log_type, null), "ContainerInstanceLogs")
      diagnostics_metadata = coalesce(try(group.diagnostics.metadata, null), {})

      # ─── DNS / PORTS ──────────────────────────────────────────
      dns_config = try(group.dns_config, null) == null ? null : {
        nameservers    = group.dns_config.nameservers
        search_domains = coalesce(try(group.dns_config.search_domains, null), [])
        options       = coalesce(try(group.dns_config.options, null), [])
      }
      exposed_ports = [
        for port in coalesce(try(group.exposed_ports, null), []) : {
          port     = port.port
          protocol = coalesce(try(port.protocol, null), "TCP")
        }
      ]

      # ─── VOLUMES: declared once per group, mounted by name ────
      # Secret payloads are base64 encoded here because the ACI API only
      # accepts encoded values and rejects plain text.
      volumes = [
        for volume in coalesce(try(group.volumes, null), []) : {
          name                = volume.name
          mount_path          = coalesce(try(volume.mount_path, null), "/mnt/${volume.name}")
          read_only           = coalesce(try(volume.read_only, null), false)
          is_empty_dir        = coalesce(try(volume.empty_dir, null), false)
          secret              = { for secret_name, secret_value in coalesce(try(volume.secret, null), {}) : secret_name => base64encode(secret_value) }
          storage_account     = try(volume.storage_account, null)
          storage_account_key = try(volume.storage_account_key, null)
          share_name          = try(volume.share_name, null)
        }
      ]

      # ─── APP CONTAINERS ───────────────────────────────────────
      containers = [
        for container in group.containers : {
          name                         = container.name
          image                        = container.image
          cpu                          = container.cpu
          memory                       = container.memory
          cpu_limit                    = try(container.cpu_limit, null)
          memory_limit                 = try(container.memory_limit, null)
          commands                     = [for command in coalesce(try(container.commands, null), []) : command]
          ports = [
            for port in coalesce(try(container.ports, null), []) : {
              port     = port.port
              protocol = coalesce(try(port.protocol, null), "TCP")
            }
          ]
          environment_variables        = coalesce(try(container.environment_variables, null), {})
          secure_environment_variables = coalesce(try(container.secure_environment_variables, null), {})
          volume_mounts                = [for mount in coalesce(try(container.volume_mounts, null), []) : mount]
          privilege_enabled            = try(container.security.privilege_enabled, null)
          liveness_probe = try(container.liveness_probe, null) == null ? null : {
            exec                  = [for command in coalesce(try(container.liveness_probe.exec, null), []) : command]
            initial_delay_seconds = try(container.liveness_probe.initial_delay_seconds, null)
            period_seconds        = try(container.liveness_probe.period_seconds, null)
            failure_threshold     = try(container.liveness_probe.failure_threshold, null)
            success_threshold     = try(container.liveness_probe.success_threshold, null)
            timeout_seconds       = try(container.liveness_probe.timeout_seconds, null)
            http_get = try(container.liveness_probe.http_get, null) == null ? null : {
              path         = try(container.liveness_probe.http_get.path, null)
              port         = try(container.liveness_probe.http_get.port, null)
              scheme       = try(container.liveness_probe.http_get.scheme, null)
              http_headers = coalesce(try(container.liveness_probe.http_get.http_headers, null), {})
            }
          }
          readiness_probe = try(container.readiness_probe, null) == null ? null : {
            exec                  = [for command in coalesce(try(container.readiness_probe.exec, null), []) : command]
            initial_delay_seconds = try(container.readiness_probe.initial_delay_seconds, null)
            period_seconds        = try(container.readiness_probe.period_seconds, null)
            failure_threshold     = try(container.readiness_probe.failure_threshold, null)
            success_threshold     = try(container.readiness_probe.success_threshold, null)
            timeout_seconds       = try(container.readiness_probe.timeout_seconds, null)
            http_get = try(container.readiness_probe.http_get, null) == null ? null : {
              path         = try(container.readiness_probe.http_get.path, null)
              port         = try(container.readiness_probe.http_get.port, null)
              scheme       = try(container.readiness_probe.http_get.scheme, null)
              http_headers = coalesce(try(container.readiness_probe.http_get.http_headers, null), {})
            }
          }
        }
      ]

      # ─── INIT CONTAINERS (run to completion before `containers`) ─
      init_containers = [
        for container in coalesce(try(group.init_containers, null), []) : {
          name                         = container.name
          image                        = container.image
          commands                     = [for command in coalesce(try(container.commands, null), []) : command]
          environment_variables        = coalesce(try(container.environment_variables, null), {})
          secure_environment_variables = coalesce(try(container.secure_environment_variables, null), {})
          volume_mounts                = [for mount in coalesce(try(container.volume_mounts, null), []) : mount]
        }
      ]
    }
  }

  # ─── DERIVED LOOKUPS USED BY PRECONDITIONS AND OUTPUTS ────────────
  group_keys            = keys(local.container_groups)
  groups_using_vnet     = [for key, group in local.container_groups : key if length(group.subnet_ids) > 0]
  groups_with_identity  = [for key, group in local.container_groups : key if group.identity_type != "None"]
  groups_with_public_ip = [for key, group in local.container_groups : key if group.ip_address_type == "Public"]
  groups_with_dns_label = [for key, group in local.container_groups : key if group.dns_name_label != null]

  container_ports_by_group = {
    for key, group in local.container_groups : key => distinct(flatten([
      for container in group.containers : [for port in container.ports : port.port]
    ]))
  }

  volume_names_by_group = {
    for key, group in local.container_groups : key => [for volume in group.volumes : volume.name]
  }

  lock_enabled = var.lock != null
  lock_kind    = try(var.lock.kind, "CanNotDelete")
}
