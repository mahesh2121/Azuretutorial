# ╔══════════════════════════════════════════════════════════════════╗
# ║  UNIT TESTS FOR modules/notification-hub - run with:             ║
# ║  cd modules/notification-hub && terraform init && terraform test ║
# ╚══════════════════════════════════════════════════════════════════╝

run "generated_names_defaults_and_tags" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    sku_name            = "Basic"

    hubs = {
      app = {
        fcm_api_key              = "AAexample-fcm-server-key-for-tests"
        registration_ttl_seconds = 86400
      }
    }
  }

  assert {
    condition     = azurerm_notification_hub_namespace.this.name == "ns-contoso-dev-eus001"
    error_message = "Namespace names must be ns-{organization}-{environment}-{region_short}{instance}, got ${azurerm_notification_hub_namespace.this.name}."
  }

  # The only value the API accepts for notification hubs; pinned on purpose.
  assert {
    condition     = azurerm_notification_hub_namespace.this.namespace_type == "NotificationHub"
    error_message = "namespace_type must always be NotificationHub."
  }

  assert {
    condition     = azurerm_notification_hub_namespace.this.sku_name == "Basic" && azurerm_notification_hub_namespace.this.enabled == true
    error_message = "sku_name and enabled must be forwarded to the namespace."
  }

  assert {
    condition     = azurerm_notification_hub.this["app"].name == "nh-contoso-dev-app"
    error_message = "Hub names must be generated from hub_name_prefix and the map key."
  }

  assert {
    condition     = azurerm_notification_hub.this["app"].tags["PushPlatform"] == "FCM" && azurerm_notification_hub.this["app"].tags["Service"] == "NotificationHubs"
    error_message = "Hub tags must record the configured platform and the standard tag set."
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 0
    error_message = "No lock may exist while var.lock is null."
  }
}

run "explicit_names_and_apns_token_credential" {
  command = plan

  variables {
    environment         = "staging"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-staging-notifications-westeurope"
    namespace_name      = "contoso-push-staging"
    hub_name_prefix     = "pushhub"
    sku_name            = "Standard"

    hubs = {
      ios = {
        name = "shopping-ios"
        apns = {
          bundle_id        = "com.contoso.shopping"
          key_id           = "2X9R4HXF34"
          team_id          = "APPNJTV5QQ"
          token            = "MIGTAgEAMBMGByqGSM49AgEGCCqBHM9VAYItBHkwdwIBAQQgplaceholder"
          application_mode = "Sandbox"
        }
      }
    }
  }

  assert {
    condition     = azurerm_notification_hub_namespace.this.name == "contoso-push-staging"
    error_message = "var.namespace_name must win over the generated name."
  }

  assert {
    condition     = azurerm_notification_hub.this["ios"].name == "shopping-ios"
    error_message = "hubs[...].name must win over the generated hub name."
  }

  assert {
    condition     = local.hubs["ios"].apns_ready && local.hubs["ios"].apns_mode == "Sandbox"
    error_message = "A complete apns block must be detected as ready with the requested mode."
  }

  assert {
    condition     = local.hubs["ios"].tags["ApnsMode"] == "Sandbox" && local.hubs["ios"].tags["PushPlatform"] == "APNs"
    error_message = "Audit tags must reflect the platform and APNs mode."
  }

  assert {
    condition     = output.hierarchy.namespace_dns == "contoso-push-staging.servicebus.windows.net"
    error_message = "The namespace DNS suffix must be derived from the namespace name (it is globally unique)."
  }
}

run "one_hub_per_app_under_a_shared_namespace" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    sku_name            = "Standard"

    hubs = {
      ios = {
        apns = {
          bundle_id        = "com.contoso.ios"
          key_id           = "AAAAAAAAAA"
          team_id          = "BBBBBBBBBB"
          token            = "MIGTAgEAMBMGByqGSM49AgEGCCqBHM9VAYItBHkwdwIBAQQgplaceholder"
          application_mode = "Sandbox"
        }
      }
      android = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
      web     = { fcm_api_key = "AAexample-fcm-web-push-key-tests" }
    }
  }

  assert {
    condition     = length(azurerm_notification_hub.this) == 3
    error_message = "Every hub entry must create exactly one hub inside the shared namespace."
  }

  assert {
    condition     = alltrue([for key, hub in azurerm_notification_hub.this : hub.namespace_name == azurerm_notification_hub_namespace.this.name])
    error_message = "All hubs must live inside the single namespace created by the module."
  }

  assert {
    condition     = length(local.hubs_without_credentials) == 0
    error_message = "Every hub must end up with a usable platform credential."
  }
}

run "lock_protects_the_namespace" {
  command = plan

  variables {
    environment         = "prod"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-prod-notifications-westeurope"
    sku_name            = "Standard"
    lock                = { kind = "CanNotDelete" }

    hubs = {
      app = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
    }
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 1 && azurerm_management_lock.this[0].lock_level == "CanNotDelete"
    error_message = "var.lock must create a CanNotDelete lock on the namespace."
  }

  assert {
    condition     = azurerm_notification_hub.this["app"].tags["RegistrationTtl"] == "default"
    error_message = "Absent registration_ttl must be recorded as `default` for audit."
  }
}

# ─── NEGATIVE TESTS ────────────────────────────────────────────────

run "free_tier_is_refused_in_production" {
  command = plan

  variables {
    environment         = "prod"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-prod-notifications-westeurope"
    sku_name            = "Free"

    hubs = {
      app = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
    }
  }

  expect_failures = [
    azurerm_notification_hub_namespace.this,
  ]
}

run "disabled_namespace_is_refused_in_production" {
  command = plan

  variables {
    environment         = "prod"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-prod-notifications-westeurope"
    sku_name            = "Standard"
    enabled             = false

    hubs = {
      app = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
    }
  }

  expect_failures = [
    azurerm_notification_hub_namespace.this,
  ]
}

run "free_tier_hub_count_is_capped" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    sku_name            = "Free"

    hubs = {
      ios     = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
      android = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
    }
  }

  expect_failures = [
    azurerm_notification_hub_namespace.this,
  ]
}

run "hub_without_any_credential_is_refused" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    sku_name            = "Basic"

    hubs = {
      lonely = {}
    }
  }

  expect_failures = [
    azurerm_notification_hub.this["lonely"],
  ]
}

run "incomplete_apns_block_is_refused" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    sku_name            = "Basic"

    hubs = {
      ios = {
        apns = {
          bundle_id = "com.contoso.ios"
          team_id   = "BBBBBBBBBB"
        }
      }
    }
  }

  expect_failures = [
    azurerm_notification_hub.this["ios"],
  ]
}

run "sandbox_apns_is_refused_in_production" {
  command = plan

  variables {
    environment         = "prod"
    organization        = "contoso"
    location            = "westeurope"
    resource_group_name = "rg-contoso-prod-notifications-westeurope"
    sku_name            = "Standard"

    hubs = {
      ios = {
        apns = {
          bundle_id        = "com.contoso.ios"
          key_id           = "AAAAAAAAAA"
          team_id          = "BBBBBBBBBB"
          token            = "MIGTAgEAMBMGByqGSM49AgEGCCqBHM9VAYItBHkwdwIBAQQgplaceholder"
          application_mode = "Sandbox"
        }
      }
    }
  }

  expect_failures = [
    azurerm_notification_hub.this["ios"],
  ]
}

run "too_short_namespace_name_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"
    namespace_name      = "abc"

    hubs = {
      app = { fcm_api_key = "AAexample-fcm-server-key-for-tests" }
    }
  }

  expect_failures = [
    var.namespace_name,
  ]
}

run "truncated_fcm_key_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"

    hubs = {
      app = { fcm_api_key = "short" }
    }
  }

  expect_failures = [
    var.hubs,
  ]
}

run "invalid_apns_key_id_is_rejected" {
  command = plan

  variables {
    environment         = "dev"
    organization        = "contoso"
    location            = "eastus"
    resource_group_name = "rg-contoso-dev-notifications-eastus"

    hubs = {
      ios = {
        apns = {
          bundle_id = "com.contoso.ios"
          key_id    = "lowercase-id"
          team_id   = "BBBBBBBBBB"
          token     = "MIGTAgEAMBMGByqGSM49AgEGCCqBHM9VAYItBHkwdwIBAQQgplaceholder"
        }
        fcm_api_key = "AAexample-fcm-server-key-for-tests"
      }
    }
  }

  expect_failures = [
    var.hubs,
  ]
}
