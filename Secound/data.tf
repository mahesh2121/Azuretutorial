data "azurerm_client_config" "current" {}

# Get subscription details to enforce one vault per subscription
data "azurerm_subscription" "current" {}