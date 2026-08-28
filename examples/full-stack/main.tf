# ╔══════════════════════════════════════════════════════════════════╗
# ║  FULL STACK EXAMPLE - ACR + ACI + NOTIFICATION HUBS              ║
# ║                                                                  ║
# ║  • private registry with private endpoint and no admin user      ║
# ║  • ACI running the image from that registry, private IP only,    ║
# ║  managed-identity pulls (no secret in state) and probes          ║
# ║  • Log Analytics for registry diagnostics and container logs     ║
# ║  • a notification hub namespace + hub per platform               ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = merge(local.standard_tags, { Service = "Platform" })
}

# The identity ACI runs as: it pulls images (AcrPull) and can be granted
# data-plane roles later without rotating anything.
resource "azurerm_user_assigned_identity" "aci" {
  name                = local.identity_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = merge(local.standard_tags, { Service = "ContainerInstances" })
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  1. IMAGE REGISTRY                                               ║
# ╚════════════════════════════════════════════════════════════════╝

module "acr" {
  source = "../../modules/acr"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  sku                           = local.effective_registry_sku
  admin_enabled                 = false
  public_network_access_enabled = !var.enable_private_link
  enforce_private_endpoints_for_production = var.enforce_private_link_for_production
  network_rule_bypass_option    = var.enable_private_link ? "None" : "AzureServices"

  # Lock the registry down to the VNet when private link is used, and stop
  # images from being exported out of the tenant.
  network_rule_set = var.enable_private_link ? { default_action = "Deny", ip_rules = [] } : null
  export_policy_enabled = var.enable_private_link ? false : true

  retention_policy = local.effective_registry_sku == "Premium" ? { enabled = true, days = 30 } : null

  # Least privilege credentials for the build pipeline; passwords are never
  # written to state (rotate with `az acr token generate-password`).
  tokens = local.effective_registry_sku == "Premium" ? {
    ci-push = {
      actions = [
        "repositories/${var.image_repository}/manifest/write",
        "repositories/${var.image_repository}/blob/read",
        "repositories/${var.image_repository}/tags/write",
        "repositories/${var.image_repository}/tags/read",
      ]
      description = "CI pipeline push scope for ${var.app_name}"
    }
  } : {}

  private_endpoints = local.private_endpoints

  role_assignments = {
    aci-pull = {
      principal_id         = azurerm_user_assigned_identity.aci.principal_id
      role_definition_name = "AcrPull"
      principal_type       = "ServicePrincipal"
    }
  }

  diagnostics = {
    enabled               = var.enable_monitoring
    workspace_resource_id = try(azurerm_log_analytics_workspace.this[0].id, null)
    retention_days        = 0
  }

  lock = local.production_like ? { kind = "CanNotDelete" } : null

  tags = local.standard_tags
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  2. RUNNING WORKLOADS                                            ║
# ╚════════════════════════════════════════════════════════════════╝

module "aci" {
  source = "../../modules/aci"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  enable_diagnostics                  = var.enable_monitoring
  diagnostics_workspace_resource_id   = try(azurerm_log_analytics_workspace.this[0].id, null)
  diagnostics_workspace_shared_key    = try(azurerm_log_analytics_workspace.this[0].primary_shared_key, null)
  default_registry_server            = local.registry_server
  default_user_assigned_identity_id  = azurerm_user_assigned_identity.aci.id
  enforce_no_public_ip_for_production = var.enforce_private_link_for_production
  enforce_probes_for_production       = var.enforce_probes_for_production
  lock                                = local.production_like ? { kind = "CanNotDelete" } : null

  container_groups = {
    # ─── HTTP FRONT END ────────────────────────────────────────
    web = {
      ip_address_type = var.enable_private_link ? "Private" : "Public"
      subnet_ids      = local.aci_subnet_ids
      zones           = local.production_like ? ["1", "2", "3"] : []

      # A public FQDN is only legal without VNet injection.
      dns_name_label              = var.enable_private_link ? null : "${var.organization}-${var.environment}-${var.app_name}"
      dns_name_label_reuse_policy = var.enable_private_link ? null : "Noreuse"

      restart_policy = "Always"

      registry = {
        server      = local.registry_server
        identity_id = azurerm_user_assigned_identity.aci.id
      }

      exposed_ports = [{ port = var.web_port, protocol = "TCP" }]

      containers = [
        {
          name   = "${var.app_name}-web"
          image  = local.image
          cpu    = var.aci_cpu_cores
          memory = var.aci_memory_gb

          ports = [{ port = var.web_port, protocol = "TCP" }]

          environment_variables = {
            APP_ENV        = var.environment
            PORT           = tostring(var.web_port)
            PUSH_NAMESPACE = module.notifications.service_endpoint
            PUSH_HUB_NAME  = module.notifications.hub_names.app
          }

          volume_mounts = ["tls-material"]

          liveness_probe = {
            http_get = {
              path = "/healthz"
              port = var.web_port
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe = {
            http_get = {
              path   = "/ready"
              port   = var.web_port
              scheme = "Http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      ]

      volumes = [
        # ACI has no "secret volume + emptyDir" hybrid: an empty_dir volume is
        # mounted read-write by Azure, so a projected cert bundle uses it.
        { name = "tls-material", mount_path = "/mnt/tls", empty_dir = true }
      ]
    }

    # ─── QUEUE WORKER (init container warms the cache) ─────────
    worker = {
      ip_address_type = var.enable_private_link ? "Private" : "Public"
      subnet_ids      = local.aci_subnet_ids
      restart_policy  = "Always"

      registry = {
        server      = local.registry_server
        identity_id = azurerm_user_assigned_identity.aci.id
      }

      volumes = [
        { name = "cache", mount_path = "/var/cache/app", empty_dir = true },
        {
          name       = "worker-config"
          mount_path = "/etc/worker"
          secret = {
            "worker.json" = jsonencode({
              environment = var.environment
              concurrency = local.production_like ? 8 : 1
              queue       = "jobs-${var.environment}"
            })
          }
        }
      ]

      init_containers = [
        {
          name      = "wait-for-queue"
          image     = local.image
          commands  = ["sh", "-c", "echo warming cache > /var/cache/app/warm.txt"]
          volume_mounts = ["cache"]
        }
      ]

      containers = [
        {
          name          = "${var.app_name}-worker"
          image         = local.image
          cpu           = var.aci_cpu_cores
          memory        = var.aci_memory_gb
          commands      = ["sh", "-c", "while true; do cat /etc/worker/worker.json; sleep 30; done"]
          volume_mounts = ["cache", "worker-config"]

          environment_variables = {
            APP_ENV       = var.environment
            PUSH_HUB_NAME = module.notifications.hub_names.app
          }

          liveness_probe = {
            exec                  = ["sh", "-c", "test -f /var/cache/app/warm.txt"]
            initial_delay_seconds = 10
            period_seconds        = 60
            failure_threshold     = 3
          }

          readiness_probe = {
            exec                  = ["sh", "-c", "test -s /etc/worker/worker.json"]
            initial_delay_seconds = 5
            period_seconds        = 30
            failure_threshold     = 3
          }
        }
      ]
    }
  }

  tags = local.standard_tags
}

# ╔════════════════════════════════════════════════════════════════╗
# ║  3. PUSH NOTIFICATIONS                                           ║
# ╚════════════════════════════════════════════════════════════════╝

module "notifications" {
  source = "../../modules/notification-hub"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  sku_name = var.notification_sku

  hubs = {
    app = {
      apns = local.apns_complete ? {
        bundle_id        = var.ios_bundle_id
        key_id           = var.apns_key_id
        team_id          = var.apns_team_id
        token            = var.apns_private_key
        application_mode = local.production_like ? "Production" : "Sandbox"
      } : null
      fcm_api_key              = var.fcm_api_key
      registration_ttl_seconds = 604800
    }
  }

  lock = local.production_like ? { kind = "CanNotDelete" } : null

  tags = local.standard_tags
}

resource "azurerm_log_analytics_workspace" "this" {
  count = var.enable_monitoring ? 1 : 0

  name                = local.workspace_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = merge(local.standard_tags, { Service = "LogAnalytics" })
}
