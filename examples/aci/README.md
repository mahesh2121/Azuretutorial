# examples/aci — Container Instances on their own

Deploys two container groups through [`modules/aci`](../../modules/aci/README.md):
a long-running web service (probes, public IP, FQDN, availability zones) and a
batch job (init container, `empty_dir` + secret volumes, `restart_policy = "Never"`).

## What you get

* `azurerm_resource_group` named `rg-{organization}-{environment}-aci-{location}`
* two `azurerm_container_group` resources from one module call
* optional VNet injection, managed identity for passwordless pulls, Log
  Analytics, per-group delete locks

## Run it

```bash
cd examples/aci
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Then reach the workload:

```bash
terraform output -json application_endpoints
curl -fsS "http://<ip>/healthz"
```

## Optional wiring

| Input | Effect |
| --- | --- |
| `registry_server` | pulls from a private registry using the identity in `user_assigned_identity_id` |
| `user_assigned_identity_id` | grants the group an identity (needed for Key Vault and passwordless ACR pulls) |
| `use_private_ip = true` + `subnet_ids` | injects the groups into a subnet delegated to `Microsoft.ContainerInstance/containerGroups`; `enforce_no_public_ip_for_production` then keeps them private |
| `log_analytics_workspace_id` / `_key` | ships container logs to Log Analytics |
| `dns_name_label` | allocates `<label>.<region>.azurecontainer.io` (public IP only) |

`environments/prod.tfvars` turns on `enforce_no_public_ip_for_production` and
`enforce_probes_for_production`, so a production apply without a delegated subnet
or without probes fails during `terraform plan` rather than at 3am.

`log_analytics_workspace_key` is marked `sensitive` and is *not* set in either
tfvars file: pass it at plan time so nothing lands in git:

```bash
export TF_VAR_log_analytics_workspace_key="$(az loganalytics workspace-shared-keys \
  -g <rg> --workspace-name <law> --query primarySharedKey -o tsv)"
```

Leaving it unset keeps `enable_diagnostics` off (see `local.diagnostics_enabled`),
which is why `terraform plan` works with no extra inputs.

## Notes on cost and lifetime

ACI bills per second of CPU/memory while the group exists. A `restart_policy =
"Never"` group that completed still counts until it is deleted: for real
scheduled workloads prefer a Container Apps job or an AKI/CronJob, and keep ACI
for burst and batch spillover. The example therefore only runs two groups.

## Cleaning up

```bash
terraform destroy -var-file=environments/dev.tfvars
```

<!-- BEGIN_TF_DOCS -->

## Variables you can set

| Name | Description | Default | Required |
|---|---|---|---|
| `container_image` | (OPTIONAL) Image the web container runs. Point it at your ACR login server for private images. | mcr.microsoft.com/azuredocs/aci-helloworld:latest | no |
| `cpu_cores` | (OPTIONAL) Requested CPU per container, in 0.1 steps starting at 0.5. | 0.5 | no |
| `cron_image` | (OPTIONAL) Image for the batch/scheduled container group. | mcr.microsoft.com/azure-cli:latest | no |
| `dns_name_label` | (OPTIONAL) Public DNS label for the web group (global, so keep it unique). Ignored with a private IP. | - | no |
| `enable_lock` | (OPTIONAL) CanNotDelete lock on every container group. | False | no |
| `environment` | (REQUIRED) dev, staging, uat, prod or dr. | - | yes |
| `location` | (REQUIRED) Azure region for the container groups. | - | yes |
| `log_analytics_workspace_id` | (OPTIONAL) Log Analytics workspace resource ID for container logs. | - | no |
| `log_analytics_workspace_key` | (OPTIONAL) Primary shared key of the workspace above. Read it from a data source or pass it from CI - never commit it. | - | no |
| `memory_gb` | (OPTIONAL) Requested memory per container in GB, in 0.5 steps starting at 1.5. | 1.5 | no |
| `organization` | (REQUIRED) Organisation short code, lowercase alphanumeric. | - | yes |
| `registry_server` | (OPTIONAL) Private registry host (no scheme) the identity pulls from, e.g. `acrcontosodeveus001.azurecr.io`. | - | no |
| `subnet_ids` | (OPTIONAL) Subnet resource IDs delegated to Microsoft.ContainerInstance/containerGroups. Required when use_private_ip = true. | [] | no |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set. | {} | no |
| `use_private_ip` | (OPTIONAL) Attach the groups to delegated subnets and give them private IPs only. | False | no |
| `user_assigned_identity_id` | (OPTIONAL) User-assigned identity resource ID used to pull images from a private registry. Grant it `AcrPull` on the registry. | - | no |

## Outputs

| Name | Description |
|---|---|
| `application_endpoints` | Ready to click http(s) endpoints for every exposed port of every group. |
| `container_group_ids` | Azure resource IDs of the container groups. |
| `container_group_names` | Names of the container groups created by the module. |
| `diagnostics_enabled_for` | Container groups that ship logs to Log Analytics. |
| `fqdns` | FQDN per container group, present only where dns_name_label is set. |
| `hierarchy` | Audit summary of what the module resolved (names, groups, VNet usage). |
| `image_reference` | Image the workload runs; the CI pipeline pushes this tag. |
| `ip_addresses` | IP address per container group (empty for VNet-injected groups). |
| `next_steps` | Commands to run after apply to verify and use the deployment. |
| `resource_group_name` | Resource group that hosts the container groups. |
| `user_assigned_identity_ids` | User-assigned identity IDs granted to the groups (Key Vault / ACR access). |
<!-- END_TF_DOCS -->
