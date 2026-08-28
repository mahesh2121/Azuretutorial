# modules/notification-hub — Notification Hubs namespace + hubs

Creates one `azurerm_notification_hub_namespace` and any number of
`azurerm_notification_hub` resources inside it, with APNs (token based) and FCM
credentials wired per hub, plus an optional delete lock.

Azure bills the *namespace* by tier and caps the hub count per tier, so the
module owns the namespace and lets one call manage all hubs of an app. That
keeps `Free` (1 hub), `Basic` (10) and `Standard` (10) choices explicit.

## What it creates

| Resource | Notes |
| --- | --- |
| `azurerm_notification_hub_namespace` | `namespace_type = "NotificationHub"`, SKU and `enabled` flag |
| `azurerm_notification_hub` | one per entry in `var.hubs`, with `apns_credential` and/or `gcm_credential` |
| `azurerm_management_lock` | optional; locks the namespace, which is what protects every hub inside it |

## Naming

```text
namespace        ns-{organization}-{environment}-{region_short}{instance_number}   e.g. ns-contoso-prod-weu001
hub              nh-{organization}-{environment}-{key}                            e.g. nh-contoso-prod-ios
hub name override   hubs[key].name (use it when an existing hub must be adopted)
lock             lock-{namespace}
```

Namespace names are limited by Azure to 6-50 alphanumeric characters and
hyphens; hub names to 1-260. Both are validated on the *resolved* value.

## Usage

```hcl
module "notifications" {
  source = "../../modules/notification-hub"

  environment         = "prod"
  organization        = "contoso"
  location            = "westeurope"
  resource_group_name = "rg-contoso-prod-push-westeurope"

  sku_name = "Standard"

  hubs = {
    ios = {
      apns = {
        application_mode = "Production"
        bundle_id        = "com.contoso.shopping"
        key_id           = "2X9R4HXF34" # APNs key id: 10 uppercase alphanumerics
        team_id          = "AB12CD34EF" # Apple developer team id, same shape
        token            = data.azurerm_key_vault_secret.apns_p8.value
      }
      tags = { platform = "ios" }
    }

    android = {
      fcm_api_key = data.azurerm_key_vault_secret.fcm.value
      tags        = { platform = "android" }
    }
  }

  lock = { kind = "CanNotDelete" }
}
```

* `data.azurerm_key_vault_secret.*` is deliberate: the `.p8` signing key and the
  FCM server key must not sit in `terraform.tfstate` if you can avoid it. The
  module also accepts them as plain inputs (`hubs[key].apns.token`,
  `hubs[key].fcm_api_key`) for pipelines that inject them via `TF_VAR_*`.
* Registration TTL is recorded as the `RegistrationTtl` tag (and returned by the
  `hubs` output) because `azurerm_notification_hub` in 3.x has no
  `registration_ttl` argument; manage the value client side and keep the tag for
  audit. See `var.hubs[].registration_ttl_seconds`.

## Guardrails (plan-time, not docs-time)

* A hub must have a complete APNs credential, an FCM key, or both - a hub with
  no platform credential can never deliver a push.
* An APNs credential must be complete: `application_mode`, `bundle_id`,
  `key_id`, `team_id` and `token` together. Half-configured APNs is the most
  common cause of silently undelivered iOS pushes.
* `key_id` and `team_id` must be exactly 10 uppercase alphanumeric characters,
  `bundle_id` must look like a reverse-DNS app id, and an FCM key shorter than 20
  characters is rejected as truncated (the classic copy-paste accident).
* `application_mode = "Sandbox"` is refused outside `dev`/`staging`, so a
  production build can never ship a development certificate profile. Flip
  `allow_sandbox_apns_in_production` only for a hub you genuinely use for
  release-candidate testing.
* `sku_name = "Free"` is refused in `prod`, `uat` and `dr` (Free has no SLA and
  a 1 hub cap), and `enabled = false` is refused in those environments too - a
  disabled namespace silently drops every push.
* Hub count is capped by the tier: Free 1, Basic 10, Standard 10.
* At least one hub must exist; an empty namespace is billed but useless.

## Outputs you actually need

`namespace_name`, `namespace_id`, `hub_names`, `hub_ids`, `service_endpoint` and
`hubs` go into the app configuration; `hierarchy`, `credential_status` and
`platform_gaps` are for review and drift checks. Connection strings are
deliberately **not** exported - `connection_string_guidance` explains the CLI
commands to fetch them at deploy time, which keeps shared access keys out of
state.

A runnable version of everything above lives in
[`examples/notification-hub`](../../examples/notification-hub/README.md).

## Testing

```bash
cd modules/notification-hub
terraform init
terraform test
```

The suite checks generated names, multi-hub expansion, the lock, and each
guardrail above as a negative case. Offline lane:
[`tests/README.md`](../../tests/README.md).

## azurerm 4.x note

`azurerm_notification_hub` in 3.x has no `registration_ttl`, no
`authorization_rule` blocks and no legacy `aps_certificate` (APNs certificate
auth was removed by Apple). This module therefore only uses `apns_credential`
with a `.p8` token, which is the supported path in 3.x and 4.x alike.

<!-- BEGIN_TF_DOCS -->

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `allow_sandbox_apns_in_production` | (OPTIONAL) Set true to permit application_mode = \"Sandbox\" APNs credentials outside dev/staging (not recommended - Apple delivers only to TestFligh… | bool | False | no |
| `enabled` | (OPTIONAL) Whether the namespace accepts traffic. Setting false suspends every hub inside it - rejected for prod/uat/dr. | bool | True | no |
| `environment` | (REQUIRED) Environment name: dev, staging, uat, prod or dr. Used for naming, tagging and the production guardrails. | string | - | yes |
| `hub_name_prefix` | (OPTIONAL) Prefix for generated hub names (`<prefix>-<key>`). Defaults to `nh-<organization>-<environment>`. | string | - | no |
| `hubs` | (REQUIRED) Notification hubs to create inside the namespace. name - explicit hub name; defaults to `<hub_name_prefix>-<key>`. apns.bundle_id - iOS/ma… | map(object({name = optional(string), apns = optional(object({bundle_id = optional(string), key_id = optional(string), team_id = optional(string), tok… | - | yes |
| `instance_number` | (OPTIONAL) Numeric suffix (zero padded to 3) used only when `namespace_name` is generated. | number | 1 | no |
| `location` | (REQUIRED) Azure region for the namespace and hubs, e.g. `westeurope`. | string | - | yes |
| `lock` | (OPTIONAL) Management lock on the namespace. `CanNotDelete` stops a hub namespace (and therefore every app's push channel) from being deleted by acci… | object({kind = optional(string, "CanNotDelete"), name = optional(string)}) | - | no |
| `namespace_name` | (OPTIONAL) Namespace name. Defaults to `ns-<organization>-<environment>-<region_short>-<instance>`. Must be globally unique because it becomes <name>… | string | - | no |
| `organization` | (REQUIRED) Organisation short code used in names and the `Organization` tag. Lowercase alphanumeric, max 10 characters. | string | - | yes |
| `resource_group_name` | (REQUIRED) Existing resource group that will hold the namespace and hubs. | string | - | yes |
| `sku_name` | (OPTIONAL) Namespace tier: Free - 1 hub, 1M notifications/month, no SLA - dev only (rejected for prod/uat/dr). Basic - 10M notifications/month, no au… | string | Basic | no |
| `tags` | (OPTIONAL) Extra tags merged onto the standard tag set. | map(string) | {} | no |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `connection_string_guidance` | How to obtain the Send/Listen connection strings without putting them in state. | no |
| `credential_status` | Audit report: which hubs still lack a platform credential and which still point at the Apple sandbox endpoint. | no |
| `hierarchy` | Resolved naming inputs - handy for `terraform output -json` in pipelines. | no |
| `hub_ids` | Resource ID of every hub, keyed by the var.hubs key. | no |
| `hub_names` | Resolved hub names - hand these to the mobile app / backend sender configuration. | no |
| `hubs` | Per hub summary. Deliberately excludes platform credentials: only the fact that a credential is configured is reported. | no |
| `lock_id` | Resource ID of the management lock, or null when var.lock is not set. | no |
| `namespace_id` | Resource ID of the notification hub namespace. | no |
| `namespace_name` | Name of the namespace (resolved, may be generated). | no |
| `namespace_sku` | Namespace pricing tier in use. | no |
| `service_endpoint` | Service Bus endpoint exposed by the namespace, e.g. `https://ns-contoso-prod-eus001.servicebus.windows.net:443/`. | no |
<!-- END_TF_DOCS -->
