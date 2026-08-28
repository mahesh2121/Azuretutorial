# modules/aci — Azure Container Instances

Creates one or more `azurerm_container_group` resources from a single map,
covering the shapes teams ask for in practice: long-running web services with
readiness/liveness probes, scheduled batch jobs (`restart_policy = "Never"`,
init containers), VNet-injected private workloads, and sidecar-free Windows
containers.

One module call = one group per map entry, so `for_each` semantics give you
isolate-able changes: destroying the cron job does not touch the web service.

## What it creates

| Resource | Notes |
| --- | --- |
| `azurerm_container_group` | `for_each` over `var.container_groups`; containers, init containers, volumes, ports, probes, registry pull, custom DNS, identity, Log Analytics |
| `azurerm_management_lock` | optional, one per group, so a stray `terraform destroy` cannot remove a running workload |

## Naming

```text
container group   {name_prefix}-{key}          e.g. aci-contoso-prod-web
name_prefix       aci-{organization}-{environment}
lock              lock-{group name}
```

Azure limits group names to 1-63 lowercase alphanumerics and hyphens; the module
validates the resolved name, not just the prefix.

## Usage

`container_groups` is a map, so the map key names the group and every field is
optional except the container list. The shape below is the one used by
[`examples/aci`](../../examples/aci/README.md), which is what the contract tests
verify:

```hcl
module "aci" {
  source = "../../modules/aci"

  environment         = "prod"
  organization        = "contoso"
  location            = "westeurope"
  resource_group_name = "rg-contoso-prod-aci-westeurope"

  # passwordless pull from a private registry, shared by every group
  default_registry_server        = "acrcontosoprodwe001.azurecr.io"
  default_user_assigned_identity_id = module.aci_identity.id

  diagnostics_workspace_resource_id = module.logging.id
  diagnostics_workspace_shared_key  = module.logging.workspace_key
  enable_diagnostics                = true

  container_groups = {
    # a long running web service
    web = {
      ip_address_type     = "Public"
      dns_name_label      = "contoso-web"
      restart_policy      = "Always"
      zones               = ["1", "2", "3"]
      exposed_ports       = [{ port = 80, protocol = "TCP" }]

      containers = [{
        name   = "web"
        image  = "acrcontosoprodwe001.azurecr.io/web:1.4.2"
        cpu    = 1
        memory = 2
        ports  = [{ port = 80, protocol = "TCP" }]

        environment_variables = { NODE_ENV = "prod" }

        liveness_probe = {
          http_get              = { path = "/", port = 80, scheme = "Http" }
          initial_delay_seconds = 10
          period_seconds        = 30
          failure_threshold     = 3
        }
        readiness_probe = {
          http_get              = { path = "/healthz", port = 80, scheme = "Http" }
          initial_delay_seconds = 5
          period_seconds        = 10
        }
      }]
    }

    # a scheduled batch job with an init container and mounted files
    cron = {
      ip_address_type = "Public"
      restart_policy  = "Never"

      volumes = [
        { name = "scratch", mount_path = "/var/cache/job", empty_dir = true },
        {
          name       = "job-config"
          mount_path = "/etc/job"
          secret     = { "settings.json" = jsonencode({ retries = 3 }) }
        },
      ]

      init_containers = [{
        name          = "wait-for-dependency"
        image         = "mcr.microsoft.com/azure-cli:latest"
        commands      = ["bash", "-c", "az --version > /var/cache/job/precheck.log"]
        volume_mounts = ["scratch"]
      }]

      containers = [{
        name          = "job"
        image         = "acrcontosoprodwe001.azurecr.io/reports:1.4.2"
        cpu           = 0.5
        memory        = 1
        commands      = ["bash", "-c", "cat /etc/job/settings.json && python /app/report.py"]
        volume_mounts = ["scratch", "job-config"]
      }]
    }
  }

  lock = { kind = "CanNotDelete" }
}
```

Private workloads: set `ip_address_type = "Private"` plus `subnet_ids` pointing
at a subnet delegated to `Microsoft.ContainerInstance/containerGroups` (see
`examples/full-stack/network.tf` for the delegation). Secure images from a
private registry without a password by setting `registry.identity_id` to a
user-assigned identity that holds `AcrPull`.

## Guardrails (plan-time, not docs-time)

* Windows groups: at most one container, no init containers, no VNet injection
  (all three are platform limits).
* `ip_address_type = "Private"` requires `subnet_ids`; a public group with
  `priority = "Spot"` must use `ip_address_type = "None"`.
* VNet injection is incompatible with `system_assigned_identity = true` (the ACI
  RP rejects it) - pass a user-assigned identity via `user_assigned_identity_ids`
  instead.
* `dns_name_label` is only allowed on public IPs.
* Every `exposed_ports` entry must also be declared on one of the group's
  containers (an `exposed_port` with no matching container port is rejected by
  the ACI RP).
* Volume mounts must reference a volume declared on the same group; volumes
  (`empty_dir`, a non-empty `secret` map, or a complete Azure Files `share`) -
  mixing sources is rejected.
* `cpu` must be a multiple of 0.1 in 0.1-64, `memory_gb` a multiple of 0.5 GB in
  0.5-512, and `cpu_limit`/`memory_limit` may not be lower than the request.
* A `registry` block needs either `identity_id` (passwordless) or both
  `username` and `password`, and `server` must be a bare host name.
* `key_vault_key_id` (customer-managed encryption for the group) requires
  `key_vault_user_assigned_identity_id`.
* `security.privilege_enabled` is emitted only for `sku = "Confidential"`
  groups, because the ACI RP rejects the block on every other SKU.
* Diagnostics need both `workspace_id` and `workspace_key`, `log_type` must be
  `ContainerInsights` or `ContainerInstanceLogs`, and metadata is capped at 20
  key/value pairs (all three are service limits).
* `enforce_no_public_ip_for_production` and `enforce_probes_for_production`
  apply the usual production rules in `prod`/`uat`/`dr`.
* Secret volumes are base64-encoded for you, so callers never double-encode.

## Testing

```bash
cd modules/aci
terraform init
terraform test
```

`tests/plan.tftest.hcl` covers defaults, VNet + identity + probes, volumes, init
containers, secret base64 handling, global vs. per-group diagnostics, locks and
ten negative cases. Offline checks: [`tests/README.md`](../../tests/README.md).

## azurerm 4.x note

In 4.x `image_registry_credential` was renamed to `image_registry_login`. The
module keeps the 3.x name in one place (`main.tf`), so migrating means changing
that block plus the provider pin.

<!-- BEGIN_TF_DOCS -->

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `container_groups` | (REQUIRED) Map of container groups to create. Group level: name - override the generated `<prefix>-<key>` name. os_type - `Linux` (default) or `Windo… | map(object({name = optional(string), os_type = optional(string, "Linux"), restart_policy = optional(string, "Always"), ip_address_type = optional(str… | - | yes |
| `default_registry_server` | (OPTIONAL) Registry server (e.g. an ACR login server) injected into groups whose `registry.server` is null but which use managed-identity pulls. | string | - | no |
| `default_user_assigned_identity_id` | (OPTIONAL) User-assigned identity added to every group that does not declare its own. Typical use: one identity with `AcrPull` on the registry. | string | - | no |
| `diagnostics_workspace_resource_id` | (OPTIONAL) Log Analytics workspace resource ID applied to every container group that does not set its own `diagnostics`. Ignored when `enable_diagnos… | string | - | no |
| `diagnostics_workspace_shared_key` | (OPTIONAL) Primary shared key for `diagnostics_workspace_resource_id`. Supply it from a data source or variable file that is never committed; it is m… | string | - | no |
| `enable_diagnostics` | (OPTIONAL) Master switch for the global diagnostics settings above. | bool | False | no |
| `enforce_no_public_ip_for_production` | (OPTIONAL) When true, prod/uat/dr groups must use ip_address_type = \"Private\" with a delegated subnet. Recommended for production workloads. | bool | False | no |
| `enforce_probes_for_production` | (OPTIONAL) When true, every container in prod/uat/dr must declare both a liveness_probe and a readiness_probe. | bool | False | no |
| `environment` | (REQUIRED) Environment name: dev, staging, uat, prod or dr. Drives naming and tagging. | string | - | yes |
| `location` | (REQUIRED) Azure region for the container groups, e.g. `eastus`. | string | - | yes |
| `lock` | (OPTIONAL) Management lock applied to every container group. `CanNotDelete` prevents accidental teardown of a running workload. | object({kind = optional(string, "CanNotDelete"), name = optional(string)}) | - | no |
| `name_prefix` | (OPTIONAL) Prefix for generated container group names (`<prefix>-<key>`). Defaults to `aci-<organization>-<environment>`. | string | - | no |
| `organization` | (REQUIRED) Organisation short code used in container group names and the `Organization` tag. Lowercase alphanumeric, max 10 characters. | string | - | yes |
| `resource_group_name` | (REQUIRED) Existing resource group that will hold the container groups. | string | - | yes |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set for every resource. | map(string) | {} | no |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `application_endpoints` | https:// endpoints for every group that exposes a public IP and ports. Handy for smoke tests in CI. | no |
| `container_group_ids` | Resource ID of every container group, keyed by the var.container_groups key. | no |
| `container_group_names` | Name of every container group (the resolved name, which may be generated). | no |
| `diagnostics_enabled_for` | Keys of the groups that ship container logs to Log Analytics, with the workspace used. | no |
| `fqdns` | FQDN of each container group derived from dns_name_label (null when no label is set). | no |
| `hierarchy` | Resolved naming inputs - handy for `terraform output -json` in pipelines. | no |
| `ip_addresses` | IP address assigned to each container group (public IP when ip_address_type = Public). | no |
| `lock_ids` | Management lock IDs, when var.lock is set. | no |
| `resource` | Curated per-group summary for callers that need more than IDs. | no |
| `system_assigned_principal_ids` | Object (principal) IDs of system-assigned identities, for granting RBAC such as AcrPull or Key Vault secrets user. | no |
| `user_assigned_identity_ids` | User-assigned identity resource IDs actually attached to each group (after defaults are applied). The owning identity's principal_id is what needs th… | no |
<!-- END_TF_DOCS -->
