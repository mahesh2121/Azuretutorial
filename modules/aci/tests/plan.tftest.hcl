# ╔══════════════════════════════════════════════════════════════════╗
# ║  UNIT TESTS FOR modules/aci - run with:                          ║
# ║  cd modules/aci && terraform init && terraform test              ║
# ╚══════════════════════════════════════════════════════════════════╝

run "smallest_group_gets_production_defaults" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      api = {
        containers = [
          {
            name   = "api"
            image  = "mcr.microsoft.com/dotnet/aspnet:8.0"
            cpu    = 0.5
            memory = 1.5
          }
        ]
      }
    }
  }

  assert {
    condition     = azurerm_container_group.this["api"].name == "aci-contoso-dev-api"
    error_message = "Container group names must be generated from the prefix and the map key."
  }

  assert {
    condition     = azurerm_container_group.this["api"].os_type == "Linux"
    error_message = "os_type must default to Linux."
  }

  assert {
    condition     = azurerm_container_group.this["api"].restart_policy == "Always"
    error_message = "restart_policy must default to Always."
  }

  assert {
    condition     = azurerm_container_group.this["api"].ip_address_type == "Public"
    error_message = "ip_address_type must default to Public."
  }

  assert {
    condition     = azurerm_container_group.this["api"].sku == "Standard"
    error_message = "sku must default to Standard (Dedicated/Confidential are opt-in)."
  }

  assert {
    condition     = azurerm_container_group.this["api"].tags["Service"] == "ContainerInstances" && azurerm_container_group.this["api"].tags["Environment"] == "dev"
    error_message = "Standard tags must be applied to every container group."
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 0
    error_message = "No lock may exist while var.lock is null."
  }
}

run "vnet_injection_with_identity_pull_and_probes" {
  command = plan

  variables {
    environment         = "prod"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-prod-aci-westeurope"

    container_groups = {
      web = {
        ip_address_type = "Private"
        subnet_ids      = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-prod/subnets/snet-aci"]
        zones           = ["1", "2", "3"]
        restart_policy  = "Always"

        registry = {
          server      = "acrcontosoprodeus001.azurecr.io"
          identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-contoso-prod-aci"
        }

        user_assigned_identity_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-contoso-prod-aci"]

        exposed_ports = [{ port = 8080, protocol = "TCP" }]

        containers = [
          {
            name   = "web"
            image  = "acrcontosoprodeus001.azurecr.io/web:1.4.2"
            cpu    = 1
            memory = 2
            ports  = [{ port = 8080, protocol = "TCP" }]
            environment_variables = {
              ASPNETCORE_URLS = "http://+:8080"
            }
            liveness_probe = {
              http_get          = { path = "/healthz", port = 8080, scheme = "Http" }
              period_seconds    = 30
              failure_threshold = 3
            }
            readiness_probe = {
              http_get          = { path = "/ready", port = 8080 }
              period_seconds    = 10
              failure_threshold = 3
            }
          }
        ]
      }
    }
  }

  assert {
    condition     = azurerm_container_group.this["web"].ip_address_type == "Private" && length(local.container_groups["web"].subnet_ids) == 1
    error_message = "Private groups must carry the delegated subnet IDs."
  }

  assert {
    condition     = local.container_groups["web"].zones == ["1", "2", "3"]
    error_message = "zones must be normalised in order for zone-redundant placement."
  }

  # Managed identity based pulls keep registry credentials out of state.
  assert {
    condition     = local.container_groups["web"].registry_uses_identity && !local.container_groups["web"].registry_uses_secrets && local.container_groups["web"].registry_enabled
    error_message = "A registry block with identity_id must select identity mode and not the username/password mode."
  }

  assert {
    condition     = local.container_groups["web"].identity_type == "UserAssigned"
    error_message = "user_assigned_identity_ids must resolve the identity type to UserAssigned."
  }

  assert {
    condition     = local.container_groups["web"].containers[0].liveness_probe.http_get.port == 8080 && local.container_groups["web"].containers[0].readiness_probe != null
    error_message = "Probes must survive normalisation into the flat structure used by the dynamic blocks."
  }
}

run "volumes_init_containers_and_secret_encoding" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      job = {
        restart_policy = "Never"
        ip_address_type = "None"
        priority        = "Spot"

        volumes = [
          { name = "scratch", mount_path = "/var/cache", empty_dir = true },
          { name = "config", mount_path = "/etc/job", secret = { "job.json" = "{\"retries\":3}" } },
        ]

        init_containers = [
          {
            name          = "preflight"
            image         = "alpine:3.20"
            commands      = ["sh", "-c", "echo ok > /var/cache/ready"]
            volume_mounts = ["scratch"]
          }
        ]

        containers = [
          {
            name          = "job"
            image         = "alpine:3.20"
            cpu           = 0.5
            memory        = 1.5
            commands      = ["sh", "-c", "cat /etc/job/job.json"]
            volume_mounts = ["scratch", "config"]
          }
        ]
      }
    }
  }

  assert {
    condition     = azurerm_container_group.this["job"].restart_policy == "Never" && azurerm_container_group.this["job"].priority == "Spot"
    error_message = "Batch semantics (Never + Spot) must be forwarded."
  }

  assert {
    condition     = length(local.container_groups["job"].volumes) == 2 && length(local.container_groups["job"].init_containers) == 1
    error_message = "Volumes and init containers must both be normalised."
  }

  # The ACI API only accepts base64 secret payloads; the module encodes them.
  assert {
    condition     = local.container_groups["job"].volumes[1].secret["job.json"] == base64encode("{\"retries\":3}")
    error_message = "Secret volume payloads must be base64 encoded by the module."
  }

  assert {
    condition     = local.container_groups["job"].volumes[0].mount_path == "/var/cache" && local.container_groups["job"].volumes[0].is_empty_dir
    error_message = "empty_dir volumes must keep their mount path."
  }
}

run "global_diagnostics_are_applied_to_every_group" {
  command = plan

  variables {
    environment                       = "dev"
    organization                      = "contoso"
    location                          = "eastus"
    resource_group_name               = "rg-contoso-dev-aci-eastus"
    enable_diagnostics                = true
    diagnostics_workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-dev"
    diagnostics_workspace_shared_key  = "d2VsY29tZS10by10ZXJyYWZvcm0tdGVzdC1rZXk="

    container_groups = {
      web = {
        containers = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
      worker = {
        containers = [{ name = "worker", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  assert {
    condition = alltrue([
      for key, group in local.container_groups :
      group.diagnostics_enabled
      && group.diagnostics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-dev"
    ])
    error_message = "Global diagnostics must reach every group that has no explicit override."
  }

  assert {
    condition     = length(azurerm_container_group.this) == 2
    error_message = "One container group per map entry."
  }
}

run "lock_is_created_for_every_group" {
  command = plan

  variables {
    environment         = "uat"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-uat-aci-eastus"
    lock                = { kind = "CanNotDelete" }

    container_groups = {
      web = {
        containers = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
      worker = {
        containers = [{ name = "worker", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 2
    error_message = "var.lock must create one lock per container group."
  }

  assert {
    condition     = azurerm_management_lock.this["web"].lock_level == "CanNotDelete"
    error_message = "The lock level must be propagated."
  }
}

# ─── NEGATIVE TESTS ────────────────────────────────────────────────

run "empty_container_groups_are_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"
    container_groups    = {}
  }

  expect_failures = [
    var.container_groups,
  ]
}

run "undersized_container_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        containers = [{ name = "web", image = "nginx:1.27", cpu = 0.25, memory = 0.5 }]
      }
    }
  }

  expect_failures = [
    var.container_groups,
  ]
}

run "private_ip_without_subnet_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        ip_address_type = "Private"
        containers      = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}

run "spot_with_public_ip_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      batch = {
        priority        = "Spot"
        ip_address_type = "Public"
        containers      = [{ name = "batch", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["batch"],
  ]
}

run "dns_label_on_private_ip_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        ip_address_type = "Private"
        subnet_ids      = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet"]
        dns_name_label  = "contoso-web"
        containers      = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}

run "system_identity_with_vnet_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        ip_address_type            = "Private"
        subnet_ids                 = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet"]
        system_assigned_identity   = true
        containers                 = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}

run "unknown_volume_mount_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        volumes = [{ name = "data", empty_dir = true }]
        containers = [
          {
            name          = "web"
            image         = "nginx:1.27"
            cpu           = 0.5
            memory        = 1.5
            volume_mounts = ["does-not-exist"]
          }
        ]
      }
    }
  }

  expect_failures = [
    var.container_groups,
  ]
}

run "exposed_port_without_container_port_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-aci-eastus"

    container_groups = {
      web = {
        exposed_ports = [{ port = 9999, protocol = "TCP" }]
        containers = [
          { name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5, ports = [{ port = 80, protocol = "TCP" }] }
        ]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}

run "public_ip_in_production_is_rejected" {
  command = plan

  variables {
    environment                       = "prod"
    organization                      = "contoso"
    location                          = "eastus"
    resource_group_name               = "rg-contoso-prod-aci-eastus"
    enforce_no_public_ip_for_production = true

    container_groups = {
      web = {
        containers = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}

run "missing_probes_in_production_are_rejected" {
  command = plan

  variables {
    environment                 = "prod"
    organization                = "contoso"
    location                    = "eastus"
    resource_group_name         = "rg-contoso-prod-aci-eastus"
    enforce_probes_for_production = true

    container_groups = {
      web = {
        ip_address_type = "None"
        containers      = [{ name = "web", image = "nginx:1.27", cpu = 0.5, memory = 1.5 }]
      }
    }
  }

  expect_failures = [
    azurerm_container_group.this["web"],
  ]
}
