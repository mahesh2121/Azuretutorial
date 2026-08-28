# examples/acr — Container Registry on its own

Deploys the ACR module into a single resource group: a registry, optional private
endpoints, CI tokens and role assignments, diagnostics and a delete lock. Use it
to review the module in isolation before wiring it into a bigger stack, or as the
starting point for a shared "platform registry" subscription.

## What you get

* `azurerm_resource_group` named `rg-{organization}-{environment}-acr-{location}`
* `module.acr` → [`modules/acr`](../../modules/acr/README.md)
* Outputs: `registry_name`, `login_server`, `registry_id`, `resource_group_name`,
  `token_names` and `docker_login_commands`

## Run it

```bash
cd examples/acr
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Production shape (Premium, private endpoints, CI tokens, diagnostics, lock):

```bash
terraform plan -var-file=environments/prod.tfvars
```

`prod.tfvars` needs the subnet the private endpoint NICs live in, because
`public_network_access_enabled = false` without an endpoint would make the
registry unreachable (the module refuses that combination):

```bash
terraform plan -var-file=environments/prod.tfvars \
  -var 'private_endpoint_subnet_ids=["/subscriptions/.../subnetNames/container-registry"]' \
  -var 'private_dns_zone_id=/subscriptions/.../privateDNSZones/privatelink.azurecr.io'
```

## dev versus prod

| | dev | prod |
| --- | --- | --- |
| SKU | `Basic` | `Premium` (private link + tokens need it) |
| Public network access | enabled | disabled, via private endpoints |
| Admin user | disabled | disabled (enforced by the module) |
| `enable_ci_tokens` | `false` (Basic has no tokens) | `true`, `repositories/<repo>` scopes |
| `enable_diagnostics` | `false` | `true`, `retention_days = 30` |
| `enable_lock` | `false` | `true` (`CanNotDelete`) |

## Verifying after apply

```bash
terraform output -json
docker build -t "$(terraform output -raw login_server)/demo:local" .
az acr login --name "$(terraform output -raw registry_name)" && docker push "$(terraform output -raw login_server)/demo:local"
```

Token passwords are never written to state. Mint one when you need it:

```bash
az acr token generate-password --registry-name "$(terraform output -raw registry_name)" \
  --token-name ci-push --name password1
```

## Cleaning up

```bash
terraform destroy -var-file=environments/dev.tfvars
```

`prod.tfvars` sets `enable_lock = true`, so `destroy` is blocked until you pass
`-var 'enable_lock=false'` on purpose.

<!-- BEGIN_TF_DOCS -->

## Variables you can set

| Name | Description | Default | Required |
|---|---|---|---|
| `enable_ci_tokens` | (OPTIONAL) Create scoped tokens for the CI pipeline (push) and for runtime pulls. Premium only. | False | no |
| `enable_diagnostics` | (OPTIONAL) Send registry login/manifest events and metrics to Log Analytics. | False | no |
| `enable_lock` | (OPTIONAL) Put a CanNotDelete lock on the registry so no one can tear down the image store. | False | no |
| `enforce_private_endpoints_for_production` | (OPTIONAL) The module refuses prod/uat/dr registries without a private endpoint while this is true. Flip it on once private_endpoint_subnet_ids is po… | False | no |
| `environment` | (REQUIRED) dev, staging, uat, prod or dr. | - | yes |
| `location` | (REQUIRED) Azure region, e.g. eastus. | - | yes |
| `log_analytics_workspace_id` | (OPTIONAL) Existing Log Analytics workspace resource ID used when enable_diagnostics = true. Leave empty to skip diagnostics entirely. | - | no |
| `organization` | (REQUIRED) Organisation short code, lowercase alphanumeric, max 10 characters. | - | yes |
| `private_dns_zone_id` | (OPTIONAL) Resource ID of a `privatelink.azurecr.io` private DNS zone to link to the private endpoint's DNS zone group. | - | no |
| `private_endpoint_subnet_ids` | (OPTIONAL) Subnet resource IDs that will host private endpoints for the registry. Requires registry_sku = Premium. See examples/full-stack for a comp… | [] | no |
| `registry_sku` | (OPTIONAL) Basic / Standard / Premium. Private endpoints, tokens, geo-replication, retention and trust policies need Premium. | Basic | no |
| `retention_days` | (OPTIONAL) Days an untagged manifest survives. Premium only; 0 disables the retention policy block. | 30 | no |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set. | {} | no |

## Outputs

| Name | Description |
|---|---|
| `docker_login_commands` | Copy/paste commands to authenticate the Docker CLI against this registry. |
| `login_server` | Use this as the image prefix, e.g. `<login_server>/web:1.0.0`. |
| `registry_id` | Registry resource ID (scope for ACRPull/ACRPush role assignments). |
| `registry_name` | Registry name chosen by the module. |
| `resource_group_name` | Resource group created for the registry. |
| `token_names` | Registry token names created by enable_ci_tokens, ready for `az acr credential show`. |
<!-- END_TF_DOCS -->
