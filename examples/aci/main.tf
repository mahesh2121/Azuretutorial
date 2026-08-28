# ╔══════════════════════════════════════════════════════════════════╗
# ║  EXAMPLE: ACI ONLY - custom modules/aci in action                ║
# ║                                                                  ║
# ║  Two workloads:                                                  ║
# ║  • web  - long running HTTP service with probes                  ║
# ║  • cron - init container + secret/emptyDir volumes, Never        ║
# ║  restart policy so the group completes and stops                 ║
# ╚══════════════════════════════════════════════════════════════════╝

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.organization}-${var.environment}-aci-${var.location}"
  location = var.location

  tags = merge(
    {
      Environment  = var.environment
      Organization = var.organization
      ManagedBy    = "Terraform"
      Service      = "ContainerInstances"
    },
    var.tags
  )
}

locals {
  diagnostics_enabled = var.log_analytics_workspace_id != "" && var.log_analytics_workspace_key != null

  # A real deployment reads the key from a data source instead of a variable:
  #   data "azurerm_log_analytics_workspace" "this" { ... }
  #   workspace_key = data.azurerm_log_analytics_workspace.this.primary_shared_key

  registry_block = var.registry_server == null ? null : {
    server      = var.registry_server
    username    = null
    password    = null
    identity_id = var.user_assigned_identity_id
  }
}

module "aci" {
  source = "../../modules/aci"

  environment         = var.environment
  organization        = var.organization
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  enable_diagnostics                     = local.diagnostics_enabled
  diagnostics_workspace_resource_id      = var.log_analytics_workspace_id != "" ? var.log_analytics_workspace_id : null
  diagnostics_workspace_shared_key       = var.log_analytics_workspace_key
  default_registry_server                = var.registry_server
  default_user_assigned_identity_id      = var.user_assigned_identity_id
  # Flip these two to true for production-grade checks; the quickstart keeps
  # them off so `terraform plan` works with a public IP and no probes.
  enforce_no_public_ip_for_production    = false
  enforce_probes_for_production          = false
  lock                                   = var.enable_lock ? { kind = "CanNotDelete" } : null

  container_groups = {
    # ─── PUBLIC WEB SERVICE ────────────────────────────────────
    web = {
      ip_address_type               = var.use_private_ip ? "Private" : "Public"
      subnet_ids                    = var.use_private_ip ? var.subnet_ids : []
      dns_name_label                = var.dns_name_label
      dns_name_label_reuse_policy   = var.dns_name_label == null ? null : "Noreuse"
      restart_policy                = "Always"
      user_assigned_identity_ids    = var.user_assigned_identity_id == null ? [] : [var.user_assigned_identity_id]
      registry                      = local.registry_block
      exposed_ports = [
        { port = 80, protocol = "TCP" }
      ]
      containers = [
        {
          name   = "web"
          image  = var.container_image
          cpu    = var.cpu_cores
          memory = var.memory_gb
          ports = [
            { port = 80, protocol = "TCP" }
          ]
          environment_variables = {
            NODE_ENV   = var.environment
            LOG_LEVEL = var.environment == "prod" ? "warn" : "info"
          }
          liveness_probe = {
            http_get              = { path = "/", port = 80, scheme = "Http" }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          readiness_probe = {
            http_get              = { path = "/healthz", port = 80, scheme = "Http" }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }
        }
      ]
    }

    # ─── BATCH JOB: INIT CONTAINER + VOLUMES ──────────────────
    cron = {
      ip_address_type              = var.use_private_ip ? "Private" : "Public"
      subnet_ids                   = var.use_private_ip ? var.subnet_ids : []
      restart_policy               = "Never"
      user_assigned_identity_ids = var.user_assigned_identity_id == null ? [] : [var.user_assigned_identity_id]
      registry                   = local.registry_block

      volumes = [
        # scratch space, never persisted
        { name = "scratch", mount_path = "/var/cache/job", empty_dir = true },
        # files rendered into the container; the module base64 encodes them
        { name = "job-config", mount_path = "/etc/job", secret = { "settings.json" = jsonencode({ environment = var.environment, retries = 3 }) } }
      ]

      init_containers = [
        {
          name      = "wait-for-dependency"
          image     = "mcr.microsoft.com/azure-cli:latest"
          commands  = ["bash", "-c", "az --version > /var/cache/job/precheck.log"]
          volume_mounts = ["scratch"]
        }
      ]

      containers = [
        {
          name   = "job"
          image  = var.cron_image
          cpu    = var.cpu_cores
          memory = var.memory_gb
          commands = [
            "bash", "-c", "cat /etc/job/settings.json && sleep 5 && echo done"
          ]
          volume_mounts = ["scratch", "job-config"]
          environment_variables = {
            ENVIRONMENT = var.environment
          }
        }
      ]
    }
  }

  tags = var.tags
}
