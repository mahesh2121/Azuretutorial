# modules/acr — Azure Container Registry

Production-oriented wrapper around `azurerm_container_registry`. It creates one
registry plus the things every team re-implements by hand: private endpoints,
scope maps and tokens for CI, `AcrPull`/`AcrPush` role assignments, a diagnostic
setting, and an optional delete lock.

Use this module when a workload needs a *private, role-based, monitored*
registry. It is intentionally not a thin passthrough: the module refuses to
plan configurations that Azure accepts but that fail in production.

## What it creates

| Resource | Notes |
| --- | --- |
| `azurerm_container_registry` | SKU-gated features (`retention_policy`, `trust_policy`, `georeplications`, tokens, network rules) are only emitted for SKUs that support them |
| `azurerm_private_endpoint` + NIC | One per entry in `private_endpoints`; registry and data-plane sub-resources |
| `azurerm_container_registry_scope_map` / `_token` | Premium only; token passwords are never read into state |
| `azurerm_role_assignment` | Built-in (`AcrPull`, `AcrPush`, `AcrDelete`) or a custom role ID |
| `azurerm_monitor_diagnostic_setting` | Log categories and metrics, optional eventhub + storage export |
| `azurerm_management_lock` | `CanNotDelete` by default when `lock` is set |

## Naming

```text
registry            acr{organization}{environment}{region_short}{instance_number}   e.g. acmecontosoduse001
private endpoint     pe-{registry}-{key}
scope map / token    from var.scope_maps / var.tokens (lowercase, no hyphens)
role assignment      ra-{registry}-{key}
diagnostic setting   diag-{registry}
lock                 lock-{registry}
```

Azure requires registry names to be 5-50 lowercase alphanumeric characters, so
the generated name contains no separators. Override it with `var.name` if the
generated value does not fit your naming policy.

## Usage

```hcl
module "acr" {
  source = "../../modules/acr"

  environment         = "prod"
  organization        = "contoso"
  location            = "westeurope"
  resource_group_name = "rg-contoso-prod-acr-westeurope"
  sku                 = "Premium"

  public_network_access_enabled      = false
  enforce_private_endpoints_for_production = true
  data_endpoint_enabled              = true

  private_endpoints = {
    registry = {
      subnet_id = azurerm_subnet.private_endpoints.id
      group_ids = ["registry"]
    }
  }

  tokens = {
    ci-push = {
      actions = ["repositories/web/manifest/write", "repositories/web/tags/write", "repositories/web/blob/read"]
    }
  }

  role_assignments = {
    aks-pull = {
      role_definition_name = "AcrPull"
      principal_id         = module.aks.kubelet_identity_object_id
    }
  }

  diagnostics = {
    log_analytics_workspace_id = module.logging.workspace_id
  }

  lock = {}
}
```

A copy-pasteable version lives in [`examples/acr`](../../examples/acr/README.md).

## Guardrails (plan-time, not docs-time)

* Premium-only features (`retention_policy`, trust policy, quarantine, network
  rules, tokens, georeplication, anonymous pull) require `sku = "Premium"`.
* `sku = "Basic"` with `enforce_private_endpoints_for_production` in a
  production-like environment is refused, because Basic cannot have private
  endpoints.
* `admin_enabled = true` is refused for `prod`, `uat` and `dr`.
* `export_policy_enabled = false` is only allowed together with
  `public_network_access_enabled = false` (Azure's own rule).
* `anonymous_pull_enabled` requires Standard or Premium.
* `public_network_access_enabled = false` without any private endpoint is
  refused - that combination is an unreachable registry.
* Production-like environments must declare at least one private endpoint when
  `enforce_private_endpoints_for_production = true`.
* `encryption` requires a user-assigned identity (Azure cannot wrap a key with a
  system-assigned identity), and `key_vault_id` must be a real Key Vault ID.
* `georeplications` must not contain the primary location.
* Names are validated against Azure's limits: registry 5-50 lowercase
  alphanumerics, private endpoint 1-80 `[a-zA-Z0-9-.]`, scope map and token
  names `[a-zA-Z0-9-]`.

## Testing

```bash
cd modules/acr
terraform init            # downloads azurerm 3.x, no Azure credentials needed
terraform test              # plan-only runs in tests/plan.tftest.hcl
```

The suite proves both directions: that good input produces the expected plan and
that every guardrail above actually blocks (`expect_failures`). The repository
also runs an offline contract lane over this module - see
[`tests/README.md`](../../tests/README.md).

## azurerm 4.x note

The pin is `>= 3.80.0, < 4.0.0`. Nothing in this module uses an argument that
4.x removes, so bumping the constraint is a version bump, not a rewrite.

<!-- BEGIN_TF_DOCS -->

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `admin_enabled` | (OPTIONAL) Enable the registry admin user. Deprecated by Azure and hard-blocked for prod/staging/uat/dr by a lifecycle precondition - use tokens or A… | bool | False | no |
| `anonymous_pull_enabled` | (OPTIONAL) Allow unauthenticated image pulls. Standard/Premium only. Off by default - only enable for publicly distributable images. | bool | False | no |
| `data_endpoint_enabled` | (OPTIONAL) Enable dedicated data endpoints for tiered login. Premium only. | bool | False | no |
| `diagnostics` | (OPTIONAL) Diagnostic settings for the registry. `workspace_resource_id` is the only mandatory field; logs are shipped to Log Analytics. `log_categor… | object({enabled = optional(bool, true), workspace_resource_id = optional(string, null), log_categories = optional(list(string), ["ContainerRegistryRe… | {'enabled': False} | no |
| `encryption` | (OPTIONAL) Customer-managed key encryption (Premium only). `key_vault_key_id` - versionless Key Vault key ID. `identity_client_id` - client ID of a u… | object({key_vault_key_id = string, identity_client_id = string}) | - | no |
| `enforce_private_endpoints_for_production` | (OPTIONAL) When true, non-dev environments must declare at least one private endpoint. A recommended guardrail, enabled by default. | bool | True | no |
| `environment` | (REQUIRED) Environment name: dev, staging, uat, prod or dr. Drives naming, tagging and the production guardrails. | string | - | yes |
| `export_policy_enabled` | (OPTIONAL) Allow images to be exported from the registry. Set to false (with public_network_access_enabled = false) for hardened registries. | bool | True | no |
| `georeplications` | (OPTIONAL) Geo-replicated registry locations. Premium only. The primary `location` must not be listed; entries are applied in alphabetical location o… | list(object({location = string, zone_redundancy_enabled = optional(bool, false), regional_endpoint_enabled = optional(bool, false)})) | [] | no |
| `instance_number` | (OPTIONAL) Numeric suffix (zero padded to 3) appended to the generated registry name. Used to keep names unique when several registries live in the s… | number | 1 | no |
| `location` | (REQUIRED) Azure region for the registry, e.g. `eastus`. Changing this forces a new resource. | string | - | yes |
| `lock` | (OPTIONAL) Management lock on the registry. `CanNotDelete` is recommended for prod/uat/dr. | object({kind = optional(string, "CanNotDelete"), name = optional(string, null)}) | - | no |
| `managed_identity_type` | (OPTIONAL) Registry managed identity type. `None`, `SystemAssigned`, `UserAssigned` or `SystemAssigned, UserAssigned`. | string | None | no |
| `name` | (OPTIONAL) Explicit registry name. When null, a deterministic name is generated: `acr{organization}{environment}{region_short}{instance_number}`. | string | - | no |
| `network_rule_bypass_option` | (OPTIONAL) Which trusted Azure services may bypass network rules. Possible values: `None`, `AzureServices`. | string | AzureServices | no |
| `network_rule_set` | (OPTIONAL) Firewall rules for the registry. Premium only. Set `default_action = "Deny"` to lock the registry down to the listed IP ranges. | object({default_action = optional(string, "Allow"), ip_rules = optional(list(string), [])}) | - | no |
| `organization` | (REQUIRED) Organisation short code, used in the registry name and the `Organization` tag. Lowercase alphanumeric, max 10 characters. | string | - | yes |
| `private_endpoints` | (OPTIONAL) Private endpoints for the registry (Premium only). subnet_id - the delegated/standard subnet that hosts the NIC. private_dns_zone_ids - us… | map(object({subnet_id = string, private_dns_zone_ids = optional(list(string), []), subresource_names = optional(list(string), ["registry"]), name = o… | {} | no |
| `public_network_access_enabled` | (OPTIONAL) Allow access to the registry over the public endpoint. Set to false for private-link-only registries. | bool | True | no |
| `quarantine_policy_enabled` | (OPTIONAL) Quarantine newly pushed images until they are scanned. Premium only. | bool | False | no |
| `resource_group_name` | (REQUIRED) Existing resource group in which the registry will be created. Changing this forces a new resource. | string | - | yes |
| `retention_policy` | (OPTIONAL) Retention of untagged manifests. Configurable on Premium only - Azure fixes untagged manifest retention at 7 days for Basic/Standard regis… | object({enabled = optional(bool, true), days = optional(number, 7)}) | - | no |
| `role_assignments` | (OPTIONAL) RBAC scoped to the registry. Typical production shape: aci-pull = { principal_id = <ACI identity object id>, role_definition_name = "AcrPu… | map(object({principal_id = string, role_definition_name = optional(string), role_definition_id = optional(string), principal_type = optional(string)}… | {} | no |
| `sku` | (OPTIONAL) Registry SKU. `Premium` is required for private endpoints, network rules, geo-replication, zone redundancy, retention/trust/quarantine pol… | string | Basic | no |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set. | map(string) | {} | no |
| `tokens` | (OPTIONAL) Scope-mapped registry tokens for CI/CD and runtime pull (Premium only). Each entry creates one scope map + one token, e.g. ci-push = { act… | map(object({token_name = optional(string), scope_map_name = optional(string), actions = list(string), description = optional(string), enabled = optio… | {} | no |
| `trust_policy_enabled` | (OPTIONAL) Enable Content Trust (Notary v2) so only signed images can be pulled. Premium only. | bool | False | no |
| `user_assigned_identity_ids` | (OPTIONAL) User-assigned managed identity resource IDs assigned to the registry. Required when managed_identity_type includes `UserAssigned`. | list(string) | [] | no |
| `zone_redundancy_enabled` | (OPTIONAL) Zone-redundant storage/metadata for the registry. Premium only. Changing this forces a new resource. | bool | False | no |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `admin_password` | Admin password. Only populated when admin_enabled = true; discouraged in production. | yes |
| `admin_username` | Admin username. Only populated when admin_enabled = true; discouraged in production. | yes |
| `diagnostic_setting_id` | Resource ID of the diagnostic setting, or null when diagnostics are disabled. | no |
| `hierarchy` | Naming inputs and the resolved registry name - useful for `terraform output -json` in CI. | no |
| `identity_principal_id` | System-assigned managed identity principal (object) ID, or null when no system-assigned identity exists. | no |
| `identity_tenant_id` | Tenant ID of the system-assigned managed identity, or null when no system-assigned identity exists. | no |
| `lock_id` | Resource ID of the management lock, or null when no lock is requested. | no |
| `login_server` | Registry login server, e.g. `myregistry.azurecr.io`. Use it as the image prefix. | no |
| `name` | Name of the container registry (the value actually used by Azure). | no |
| `private_endpoints` | Private endpoint IDs and the private IPs allocated to them. | no |
| `resource` | Curated registry attributes for callers that need more than the individual outputs (never contains credentials). | no |
| `resource_id` | Full resource ID of the container registry. | no |
| `role_assignments` | Created role assignment IDs keyed by the input map key. | no |
| `sku` | SKU the registry was created with. | no |
| `tokens` | Map of token key to the created token/scope map IDs. Rotate the password out of band (never in state): az acr credential show -g <rg> -n <registry> -… | no |
<!-- END_TF_DOCS -->
