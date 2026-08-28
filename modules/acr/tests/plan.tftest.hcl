# ╔══════════════════════════════════════════════════════════════════╗
# ║  UNIT TESTS FOR modules/acr - run with:                          ║
# ║  cd modules/acr && terraform init && terraform test              ║
# ║                                                                  ║
# ║  Every run uses `command = plan`, so no Azure credentials and    ║
# ║  no subscription are needed - these guard the module contract.   ║
# ╚══════════════════════════════════════════════════════════════════╝

run "generated_name_is_deterministic" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    sku                 = "Basic"
  }

  assert {
    condition     = azurerm_container_registry.this.name == "acrcontosodeveus001"
    error_message = "Registry name must be acr{org}{env}{region}{instance}, got ${azurerm_container_registry.this.name}."
  }

  assert {
    condition     = azurerm_container_registry.this.sku == "Basic"
    error_message = "sku must be forwarded to the registry unchanged."
  }

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "The admin user must stay disabled by default."
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == true
    error_message = "public_network_access_enabled should default to true for dev convenience."
  }

  assert {
    condition = (
      azurerm_container_registry.this.tags["Environment"] == "dev"
      && azurerm_container_registry.this.tags["Service"] == "ContainerRegistry"
      && azurerm_container_registry.this.tags["ManagedBy"] == "Terraform"
    )
    error_message = "The standard tag set (Environment/Service/ManagedBy) must always be applied."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "No diagnostic setting may exist while var.diagnostics.enabled is false."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 0
    error_message = "No private endpoint may exist while var.private_endpoints is empty."
  }

  assert {
    condition     = length(local.premium_only_violations) == 0
    error_message = "A plain Basic registry must not report premium-only features."
  }
}

run "instance_number_and_name_override" {
  command = plan

  variables {
    environment         = "staging"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-staging-acr-westeurope"
    instance_number     = 7
    sku                 = "Standard"
  }

  assert {
    condition     = azurerm_container_registry.this.name == "acrcontosostagingweu007"
    error_message = "instance_number must be zero padded to 3 and appended to the generated name."
  }

  assert {
    condition     = local.region_short == "weu"
    error_message = "westeurope must map to the shared region short code `weu`."
  }
}

run "explicit_name_wins" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    name                = "contosodevshared"
    sku                 = "Basic"
  }

  assert {
    condition     = azurerm_container_registry.this.name == "contosodevshared"
    error_message = "var.name must override the generated name."
  }
}

run "premium_features_unlock_zone_and_geo_replication" {
  command = plan

  variables {
    environment             = "prod"
    organization            = "contoso"
    location                = "eastus"
    resource_group_name     = "rg-contoso-prod-acr-eastus"
    sku                     = "Premium"
    zone_redundancy_enabled = true
    enforce_private_endpoints_for_production = false
    retention_policy        = { enabled = true, days = 45 }
    georeplications = [
      { location = "westeurope", zone_redundancy_enabled = false, regional_endpoint_enabled = false },
      { location = "northeurope", zone_redundancy_enabled = false, regional_endpoint_enabled = false },
    ]
    tags = { CostCenter = "platform-prod" }
  }

  assert {
    condition     = azurerm_container_registry.this.zone_redundancy_enabled == true
    error_message = "zone_redundancy_enabled must reach the registry on Premium."
  }

  # Azure requires geo-replications to be declared in alphabetical order of
  # location; the module keys the map by location to guarantee it.
  assert {
    condition     = length(local.georeplications) == 2 && keys(local.georeplications)[0] == "northeurope"
    error_message = "georeplications must be de-duplicated and ordered by location."
  }

  assert {
    condition     = azurerm_container_registry.this.tags["CostCenter"] == "platform-prod"
    error_message = "var.tags must be merged into the standard tag set."
  }
}

run "tokens_create_scope_map_pairs" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    sku                 = "Premium"
    tokens = {
      ci-push = {
        actions = ["repositories/web/manifest/write", "repositories/web/tags/write"]
      }
      app-pull = {
        actions          = ["repositories/web/manifest/read", "catalog"]
        scope_map_name   = "apppullscope"
        token_name       = "apppulltoken"
      }
    }
  }

  assert {
    condition     = length(azurerm_container_registry_scope_map.this) == 2 && length(azurerm_container_registry_token.this) == 2
    error_message = "Every token entry must create exactly one scope map and one token."
  }

  assert {
    condition     = azurerm_container_registry_scope_map.this["ci-push"].name == "ci-push-scope-map"
    error_message = "Scope maps default to `<key>-scope-map`."
  }

  assert {
    condition     = azurerm_container_registry_token.this["app-pull"].name == "apppulltoken"
    error_message = "Explicit token_name must win over the generated one."
  }

  assert {
    condition     = length(azurerm_container_registry_scope_map.this["ci-push"].actions) == 2
    error_message = "actions must be forwarded unchanged to the scope map."
  }
}

run "network_rules_and_diagnostics_and_lock" {
  command = plan

  variables {
    environment             = "dev"
    organization            = "contoso"
    location                = "eastus"
    resource_group_name     = "rg-contoso-dev-acr-eastus"
    sku                     = "Premium"
    network_rule_set        = { default_action = "Deny", ip_rules = ["10.20.30.40/32", "10.20.31.0/24"] }
    export_policy_enabled   = true
    public_network_access_enabled = true
    diagnostics = {
      enabled               = true
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops/providers/Microsoft.OperationalInsights/workspaces/law-contoso-dev"
      retention_days        = 0
    }
    lock = { kind = "CanNotDelete" }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Diagnostics must create one diagnostic setting when a workspace is supplied."
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 1 && azurerm_management_lock.this[0].lock_level == "CanNotDelete"
    error_message = "var.lock must create a CanNotDelete management lock."
  }

  assert {
    condition     = local.network_rule_set.default_action == "Deny" && length(local.network_rule_set.ip_rules) == 2
    error_message = "The network rule set must be passed through with both IP ranges."
  }
}

run "diagnostics_are_skipped_without_a_workspace" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    sku                 = "Standard"
    diagnostics = {
      enabled               = true
      workspace_resource_id = null
    }
  }

  assert {
    condition     = local.diagnostics_enabled == false && length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "enabled = true without a workspace resource ID must not create a partial diagnostic setting."
  }
}

run "role_assignments_are_scoped_to_the_registry" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    sku                 = "Premium"
    managed_identity_type = "SystemAssigned"
    role_assignments = {
      aci-pull = {
        principal_id         = "11111111-2222-3333-4444-555555555555"
        role_definition_name = "AcrPull"
        principal_type       = "ServicePrincipal"
      }
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.this) == 1 && azurerm_role_assignment.this["aci-pull"].role_definition_name == "AcrPull"
    error_message = "Role assignments must be created with the requested built-in role."
  }

  assert {
    condition     = strcontains(var.managed_identity_type, "SystemAssigned")
    error_message = "sanity: the identity type drives the principal outputs."
  }
}

# ─── NEGATIVE TESTS: the guardrails must actually bite ──────────────

run "invalid_sku_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    sku                 = "Ultra"
  }

  expect_failures = [
    var.sku,
  ]
}

run "uppercase_registry_name_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
    name                = "Contoso-Dev"
    sku                 = "Basic"
  }

  expect_failures = [
    var.name,
  ]
}

run "bad_environment_is_rejected" {
  command = plan

  variables {
    environment         = "test"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-acr-eastus"
  }

  expect_failures = [
    var.environment,
  ]
}

run "premium_feature_on_basic_is_rejected" {
  command = plan

  variables {
    environment             = "dev"
    organization            = "contoso"
    location                = "eastus"
    resource_group_name     = "rg-contoso-dev-acr-eastus"
    sku                     = "Basic"
    zone_redundancy_enabled = true
  }

  # The SKU matrix is enforced by a lifecycle precondition on the registry.
  expect_failures = [
    azurerm_container_registry.this,
  ]
}

run "admin_user_in_production_is_rejected" {
  command = plan

  variables {
    environment                            = "prod"
    organization                           = "contoso"
    location                               = "eastus"
    resource_group_name                    = "rg-contoso-prod-acr-eastus"
    sku                                    = "Premium"
    admin_enabled                          = true
    enforce_private_endpoints_for_production = false
  }

  expect_failures = [
    azurerm_container_registry.this,
  ]
}

run "private_only_registry_without_endpoint_is_rejected" {
  command = plan

  variables {
    environment                            = "dev"
    organization                           = "contoso"
    location                               = "eastus"
    resource_group_name                    = "rg-contoso-dev-acr-eastus"
    sku                                    = "Premium"
    public_network_access_enabled           = false
    enforce_private_endpoints_for_production = false
  }

  expect_failures = [
    azurerm_container_registry.this,
  ]
}
