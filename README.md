# Azuretutorial — production-ready Terraform modules for ACR, ACI and Notification Hubs

Custom, dependency-free Terraform modules for three Azure services that the
well-known modules do not cover together:

| Module | Wraps | Highlights |
| --- | --- | --- |
| [`modules/acr`](modules/acr/README.md) | `azurerm_container_registry` | SKU-aware premium features, private endpoints, scope maps + tokens, role assignments, diagnostics, delete lock, 15 plan-time guardrails |
| [`modules/aci`](modules/aci/README.md) | `azurerm_container_group` | many groups per call, probes, init containers, volumes, VNet injection, passwordless registry pulls, Log Analytics, per-group locks, 20 guardrails |
| [`modules/notification-hub`](modules/notification-hub/README.md) | `azurerm_notification_hub_namespace` + `azurerm_notification_hub` | tier-aware hub caps, APNs (token based) and FCM credentials, production/sandbox enforcement, locks, 9 guardrails |

Examples are runnable stacks, not snippets:

| Example | Shows |
| --- | --- |
| [`examples/acr`](examples/acr/README.md) | registry alone, dev vs prod shapes, CI tokens |
| [`examples/aci`](examples/aci/README.md) | public web service + batch job with init container and volumes |
| [`examples/notification-hub`](examples/notification-hub/README.md) | namespace + iOS/Android hubs with credentials kept out of state |
| [`examples/full-stack`](examples/full-stack/README.md) | ACR + ACI + Notification Hubs in one VNet: private link, delegated subnet, `AcrPull` identity, shared Log Analytics |

`Secound/` is an existing Key Vault stack in this repository and is not managed by
the module conventions below.

## Quick start

```bash
cd examples/full-stack
terraform init
terraform plan -var-file=environments/dev.tfvars
```

No Azure credentials are needed for the plan of `dev.tfvars`; the resource group,
VNet, registry, container group and hubs are all created by the stack itself.

## Conventions every module follows

* **Naming.** `rg-{organization}-{environment}-{service}-{location}` for resource
  groups and `<prefix>{organization}{environment}{region_short}{instance}` for
  services with restrictive name rules (ACR, namespaces). Every module exposes
  `organization`, `environment`, `location` and `resource_group_name`.
* **Tags.** `Environment`, `Organization`, `ManagedBy` and `Service` are applied by
  the module; `var.tags` merges on top. Everything Azure lets you tag is tagged.
* **Guardrails over docs.** Anything Azure rejects at runtime (Windows ACI with
  two containers, `Free` registry with private endpoints, half-configured APNs
  credentials, disabled namespace in prod) is a `precondition` or `validation`, so
  `terraform plan` fails with a sentence that says what to change.
* **No secrets in state where avoidable.** Registry token passwords, namespace
  shared access keys and APNs `.p8` bodies are never exported; credential inputs
  are marked `sensitive`, and examples read them from Key Vault or `TF_VAR_*`.
* **Locks are opt-in.** `var.lock = { kind = "CanNotDelete" }` creates an
  `azurerm_management_lock`; leaving it `null` creates nothing, so dev stays
  disposable.
* **Provider pin.** `azurerm >= 3.80.0, < 4.0.0`, Terraform `>= 1.9.0, < 2.0.0`
  (nested `optional()` defaults and the `terraform test` framework).

## Testing

Two complementary lanes — details in [`tests/README.md`](tests/README.md):

```bash
make test             # offline contract suite (python-hcl2 + pytest), no cloud, no terraform
make test-terraform   # native `terraform test` runs for every module (needs terraform >= 1.6)
make lint             # terraform fmt -check, tflint and docs drift, when the tools exist
```

CI (`.github/workflows/terraform.yml`) runs both lanes on every pull request.

## Repository layout

```text
modules/                  reusable modules, one directory per service
  acr/                    versions, variables, locals, main, outputs, README, tests/
  aci/
  notification-hub/
examples/                 runnable stacks that consume modules/
  acr/  aci/  notification-hub/  full-stack/
    environments/*.tfvars per-environment inputs
tests/                    offline contract suite (pytest) + provider schema snapshots
tools/gen-docs.py         regenerates the Inputs/Outputs tables in every README
Makefile                  fmt / validate / test / test-terraform / docs / plan-<example>
.github/workflows/        CI
```
