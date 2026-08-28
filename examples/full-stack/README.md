# examples/full-stack — ACR + ACI + Notification Hubs together

The reference layout: a private registry feeding a container group that pulls
from it, both inside one network, with a notification hub the workload is told
about. This is the example to copy for a real service.

```text
                 ┌───────────────────────────┐
   CI pipeline ──▶│  ACR (Premium, private)   │◀── private endpoint ──┐
                 └────────────┬──────────────┘                       │
                              │ AcrPull via user-assigned identity   │
                              ▼                                      │
                 ┌───────────────────────────┐                       │
                 │  ACI group in a delegated │─── subnet ────────────┘
                 │  subnet (private IP only) │                       │
                 └────────────┬──────────────┘                       │
                              │ env: HUB_NAMESPACE / HUB_NAME        │
                              ▼                                      │
                 ┌───────────────────────────┐                       │
                 │  Notification Hub         │                       │
                 └───────────────────────────┘                       │
```

## Files

| File | Purpose |
| --- | --- |
| `main.tf` | resource group, user-assigned identity, role assignments, the three module calls |
| `network.tf` | VNet, subnet delegated to `Microsoft.ContainerInstance/containerGroups`, private endpoint subnet, NSG + rules, `privatelink.azurecr.io` zone and its VNet link |
| `locals.tf` | naming, `effective_registry_sku`, tag set, per-environment switches |
| `outputs.tf` | `image_reference`, `container_endpoints`, `container_ips`, hub names, identity IDs, `private_endpoint_ips`, `next_steps` |
| `environments/dev.tfvars` | cheap: Basic registry, public IP ACI, Basic hub, monitoring off |
| `environments/prod.tfvars` | Premium + private link, delegated subnet ACI, Standard hubs, Log Analytics with retention, locks |

## Run it

```bash
cd examples/full-stack
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

`dev.tfvars` plans with nothing pre-existing: the stack builds its own VNet,
registry, hubs and (optionally) Log Analytics workspace. Prod needs only the APNs
signing key, injected at plan time so it never touches git or state:

```bash
export TF_VAR_apns_private_key="$(cat ./AuthKey_2X9R4HXF34.p8)"   # never a -var flag
terraform plan -var-file=environments/prod.tfvars
```

Everything else is a switch: `enable_private_link`, `enable_monitoring`,
`log_retention_days`, `notification_sku`, `enforce_probes_for_production`,
`enforce_private_link_for_production`, `virtual_network_address_space`,
`aci_subnet_prefix`, `private_endpoint_subnet_prefix`.

## How the pieces are wired

1. **Image reference.** `local.image` is `${module.acr.login_server}/${var.image_repository}:${var.image_tag}`
   and is what the container group pulls. Change `image_tag` and only the ACI
   group is replaced — the registry is untouched.
2. **Passwordless pull.** A user-assigned identity is created for the workload,
   granted `AcrPull` on the registry, and referenced by the module's registry
   block. No Dockerfile secret, no rotation ticket.
3. **Network path.** `enable_private_link` forces `local.effective_registry_sku =
   "Premium"` (private endpoints need it), creates the registry private endpoint in
   `azurerm_subnet.private_endpoints`, links `privatelink.azurecr.io` to the VNet
   and sets `public_network_access_enabled = false`. The ACI subnet is delegated
   to `Microsoft.ContainerInstance/containerGroups` with a
   `Microsoft.ContainerRegistry` service endpoint, so `azurerm_subnet.aci` can
   resolve the registry.
4. **Push configuration.** The container receives `HUB_NAMESPACE` and
   `HUB_NAME` from `module.notifications`, so the image stays environment agnostic.
5. **Observability.** When `enable_monitoring = true` the stack creates
   `azurerm_log_analytics_workspace.this` with `retention_in_days =
   log_retention_days`, then passes its `id` and `primary_shared_key` straight into
   the ACR diagnostics and the ACI Log Analytics block. The key is a *sensitive*
   module input, so it appears in `terraform show` output but never in a file;
   wire `enable_monitoring = false` if your platform team owns the workspace
   instead.

## Verify

```bash
terraform output -json container_endpoints      # ACI endpoints (empty in private mode)
terraform output -json private_endpoint_ips     # the registry IPs inside your VNet
terraform output -json container_group_names
terraform output -json image_reference          # what CI must build and push
terraform output next_steps                     # the az CLI checks for this stack
```

In private mode, reach the workload from inside the VNet (a jump box or another
group), not from your laptop — that is the point of the example.

## CI: build and push the image the stack expects

```bash
IMAGE="$(terraform output -raw image_reference)"   # <login_server>/<repo>:<tag>
az acr login --name "$(terraform output -raw registry_name)"
docker build -t "$IMAGE" . && docker push "$IMAGE"
```

Or, without the admin user, use the CI token listed by
`terraform output -json registry_token_names` plus
`az acr token generate-password`.

## Destroying

```bash
terraform destroy -var-file=environments/dev.tfvars
```

`prod.tfvars` keeps `enable_lock = true`, so destroy is blocked until you remove
the lock on purpose.

<!-- BEGIN_TF_DOCS -->

## Variables you can set

| Name | Description | Default | Required |
|---|---|---|---|
| `aci_cpu_cores` | (OPTIONAL) ACI CPU per container (0.1 steps, min 0.5). | 0.5 | no |
| `aci_memory_gb` | (OPTIONAL) ACI memory per container in GB (0.5 steps, min 1.5). | 1.5 | no |
| `aci_subnet_prefix` | (OPTIONAL) Address prefix of the ACI delegated subnet. | 10.40.1.0/24 | no |
| `apns_key_id` | (OPTIONAL) APNs .p8 key id. When null, iOS hubs fall back to the FCM credential only. | - | no |
| `apns_private_key` | (OPTIONAL) APNs .p8 private key body. In real environments source it from Key Vault (see README); never commit it. | - | no |
| `apns_team_id` | (OPTIONAL) Apple developer team id. | - | no |
| `app_name` | (REQUIRED) Application short name used in the container group and hub names. | - | yes |
| `enable_monitoring` | (OPTIONAL) Create a Log Analytics workspace and wire registry diagnostics plus ACI container logs into it. | False | no |
| `enable_private_link` | (OPTIONAL) Build the hub network, delegate a subnet for ACI, put a private endpoint + private DNS zone on the registry and give ACI a private IP only… | False | no |
| `enforce_private_link_for_production` | (OPTIONAL) Refuse prod/uat/dr when enable_private_link = false. Keeps the example runnable in dev while making a public production registry a deliber… | True | no |
| `enforce_probes_for_production` | (OPTIONAL) Pass straight through to modules/aci: refuse prod/uat/dr containers without liveness and readiness probes. | True | no |
| `environment` | (REQUIRED) dev, staging, uat, prod or dr. | - | yes |
| `fcm_api_key` | (OPTIONAL) Google API server key for Android delivery. Placeholder is fine for plan, replace before shipping real pushes. | AA-placeholder-fcm-server-key-change-me | no |
| `image_repository` | (OPTIONAL) Repository inside the registry that holds the workload image. | web | no |
| `image_tag` | (OPTIONAL) Image tag to deploy. Pin a concrete tag (not `latest`) in prod so rollbacks are possible. | 1.0.0 | no |
| `ios_bundle_id` | (OPTIONAL) iOS/macOS bundle id for the APNs credential. | com.contoso.myapp | no |
| `location` | (REQUIRED) Azure region for every resource in this stack. | - | yes |
| `log_retention_days` | (OPTIONAL) Log Analytics retention in days (30-732, or 1 for dev). | 30 | no |
| `notification_sku` | (OPTIONAL) Notification hub namespace tier. Free is refused outside dev by the module. | Basic | no |
| `organization` | (REQUIRED) Organisation short code, lowercase alphanumeric, max 10 characters. | - | yes |
| `private_endpoint_subnet_prefix` | (OPTIONAL) Address prefix of the subnet hosting the registry private endpoint. | 10.40.9.0/28 | no |
| `registry_sku` | (OPTIONAL) ACR SKU. Premium is required by enable_private_link and by the token/retention settings used here. | Basic | no |
| `tags` | (OPTIONAL) Extra tags merged into every resource. | {} | no |
| `virtual_network_address_space` | (OPTIONAL) Address space of the VNet created when enable_private_link = true. | 10.40.0.0/16 | no |
| `web_port` | (OPTIONAL) Container port exposed by the web workload. | 8080 | no |
| `web_replicas_note` | (OPTIONAL) ACI has no replica set - this label is only used for tagging and is documented as such. | 1 (ACI is a single instance; use AKI/Container Apps for sca… | no |

## Outputs

| Name | Description |
|---|---|
| `aci_identity_id` | User-assigned identity used by ACI. Grant it more roles here instead of adding secrets. |
| `aci_identity_principal_id` | Object ID of the ACI identity (what az role assignment --assignee expects). |
| `container_endpoints` | Reachable endpoints for each container group. |
| `container_group_names` | Name of every ACI container group (az container show / kubectl-less debugging starts here). |
| `container_ips` | IP address of every container group (private when enable_private_link = true). |
| `image_reference` | Fully qualified image the stack deploys. |
| `log_analytics_workspace_id` | Workspace receiving registry diagnostics and ACI container logs (null when enable_monitoring = false). |
| `next_steps` | Commands to build, push and run the first image through this stack. |
| `notification_hub_names` | Hub names for the mobile clients and the backend sender. |
| `notification_hub_resource_ids` | Hub resource IDs, used when fetching Send/Listen keys with the Azure CLI. |
| `notification_namespace_name` | Notification hub namespace. |
| `private_endpoint_ips` | Private IPs allocated to the registry private endpoints. |
| `registry_id` | Registry resource ID - the scope for extra role assignments. |
| `registry_login_server` | Prefix your image tags with this value. |
| `registry_name` | Registry name (used by `az acr login` and the CI task). |
| `registry_token_names` | Scoped registry tokens created for CI; rotate the password outside of Terraform. |
| `resource_group_name` | Resource group holding the whole stack. |
| `virtual_network_id` | Hub VNet created for private link / ACI injection. |
<!-- END_TF_DOCS -->
