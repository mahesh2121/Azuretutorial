# examples/notification-hub — Notification Hubs on their own

Deploys one namespace and two hubs (iOS, Android) through
[`modules/notification-hub`](../../modules/notification-hub/README.md). The iOS
hub keeps an FCM credential as a fallback so the example plans before Apple
Developer artefacts exist.

## What you get

* `azurerm_resource_group` named `rg-{organization}-{environment}-notifications-{location}`
* a namespace `ns-{organization}-{environment}-{region_short}001` (SKU from `sku_name`)
* hubs `nh-{organization}-{environment}-ios` and `nh-{organization}-{environment}-android`
* outputs: `namespace_name`, `namespace_sku`, `hub_names`, `hub_ids`,
  `credential_status`, `next_steps`

## Run it

```bash
cd examples/notification-hub
terraform init
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

`dev.tfvars` uses `Basic`, Apple `Sandbox` (derived from `environment`) and
`apns_* = null`, so it plans with no external prerequisites at all.

`prod.tfvars` uses `Standard`, sets `apns_key_id` / `apns_team_id`, and expects the
`.p8` signing key at plan time. Never put the key in a file:

```bash
export TF_VAR_apns_private_key="$(az keyvault secret show \
  --vault-name kv-contoso-prod-weu-001 -n apns-p8 --query value -o tsv)"
terraform plan -var-file=environments/prod.tfvars
```

`enable_lock = true` in prod puts a `CanNotDelete` lock on the namespace.

## Supplying the platform credentials

| Input | Where it should come from |
| --- | --- |
| `apns_private_key` | `TF_VAR_apns_private_key` from Key Vault, or the `data.azurerm_key_vault_secret` pattern shown in `var.hubs` docs |
| `fcm_api_key` | same; the committed value in the tfvars files is a placeholder |
| `apns_key_id`, `apns_team_id` | safe to commit: they are identifiers, not secrets |

The module rejects a truncated key (`fcm_api_key` must be ≥ 20 characters) and a
half-configured `apns` block, which is why the example only builds the `apns`
object when all three pieces are present (`local.apns_complete`).

## Sanity checks

```bash
az notification-hub namespace show -g "$(terraform output -raw resource_group_name)" \
  -n "$(terraform output -raw namespace_name)"
az notification-hub list -g "$(terraform output -raw resource_group_name)" \
  --namespace-name "$(terraform output -raw namespace_name)" -o table
terraform output -json credential_status      # which hub has APNs / FCM, and the mode
```

Sending a test push needs a namespace connection string, which this module
deliberately does not export. Fetch it in the shell, not in state:

```bash
az notification-hub namespace list-keys \
  -g "$(terraform output -raw resource_group_name)" \
  -n "$(terraform output -raw namespace_name)" -o table
```

## Cleaning up

```bash
terraform destroy -var-file=environments/dev.tfvars
```

<!-- BEGIN_TF_DOCS -->

## Variables you can set

| Name | Description | Default | Required |
|---|---|---|---|
| `apns_key_id` | (OPTIONAL) 10 character APNs .p8 key identifier from Apple Developer > Keys. | - | no |
| `apns_private_key` | (OPTIONAL) Body of the .p8 push key (no BEGIN/END lines). Prefer wiring this from azurerm_key_vault_secret; it is marked sensitive so Terraform never… | - | no |
| `apns_team_id` | (OPTIONAL) 10 character Apple developer team identifier. | - | no |
| `enable_lock` | (OPTIONAL) CanNotDelete lock on the namespace. | False | no |
| `environment` | (REQUIRED) dev, staging, uat, prod or dr. | - | yes |
| `fcm_api_key` | (OPTIONAL) Google API server key for Android delivery. Wire from a secret store in real environments. | AA-placeholder-fcm-server-key-change-me | no |
| `ios_bundle_id` | (OPTIONAL) iOS/macOS bundle id registered with Apple, e.g. com.contoso.myapp. | com.contoso.myapp | no |
| `location` | (REQUIRED) Azure region for the namespace. | - | yes |
| `organization` | (REQUIRED) Organisation short code, lowercase alphanumeric. | - | yes |
| `sku_name` | (OPTIONAL) Free (dev only), Basic or Standard. The module refuses Free for prod/uat/dr. | Basic | no |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set. | {} | no |

## Outputs

| Name | Description |
|---|---|
| `credential_status` | Which hubs still lack a platform credential / still use the Apple sandbox. |
| `hub_ids` | Hub resource IDs, useful for `az notification-hub keys list`. |
| `hub_names` | Hub names to give to the mobile apps and to the backend sender. |
| `namespace_name` | Namespace name (globally unique, also the DNS prefix). |
| `namespace_sku` | Namespace pricing tier. |
| `next_steps` | How to retrieve the Send/Listen keys without writing them into state. |
| `resource_group_name` | Resource group holding the namespace and hubs. |
<!-- END_TF_DOCS -->
