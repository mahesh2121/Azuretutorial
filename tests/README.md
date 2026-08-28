# tests/ — how this repository is verified

Two lanes, because a Terraform repository fails in two different ways:

1. **Structure and wiring** fail before any API call (typos, renamed provider
   arguments, undeclared `var.x`, examples that no longer match the module).
   That is lane 1: pure Python, parses the HCL, no credentials, no network.
2. **Semantics** only fail inside Terraform (`terraform test` runs, provider
   validation, `fmt`). That is lane 2, which needs a `terraform` binary.

```bash
python3 -m venv .venv-tf && .venv-tf/bin/pip install -r tests/requirements.txt
.venv-tf/bin/python -m pytest tests -c tests/pytest.ini          # lane 1
.venv-tf/bin/python tests/run_all.sh                              # lane 1 + 2 + docs drift
make test / make test-terraform / make ci                          # same thing via make
```

## Lane 1: the contract suite

| File | Gate |
| --- | --- |
| `test_01_syntax.py` | every `.tf`, `.tfvars` and `.tftest.hcl` parses; only legal block types; no conflict markers |
| `test_02_style.py` | spaces not tabs, no trailing whitespace, 2-space indents, single trailing newline, line length, banner comments |
| `test_03_module_contract.py` | pinned providers, no `backend`/`provider` blocks in modules, typed + documented inputs, documented outputs, `sensitive` credentials, no dead inputs/locals, enum validation |
| `test_04_provider_schema.py` | every resource argument checked against `schemas/azurerm_3.116.json`, deprecated arguments, attribute references |
| `test_05_references.py` | `var.*` / `local.*` declared, `module.x.attr` exists in the called module, module inputs match its contract |
| `test_06_naming_and_tags.py` | names derived from organization + environment, Azure name limits enforced, standard tags everywhere, one shared region table |
| `test_07_security.py` | no committed secrets (incl. base64-obfuscated), sensitive credential outputs, admin user off, guardrails + locks present |
| `test_08_examples.py` | example layout, relative module sources, tfvars ↔ variables, dev/prod self-consistency, full-stack wiring |
| `test_09_terraform_tests.py` | the `terraform test` suites are structurally sound (positive and negative runs, valid variables, complete asserts) |
| `test_10_docs.py` | READMEs document every input/output, tooling exists (Makefile targets, CI steps, .gitignore) |

Failures print *all* findings at once (`assert_clean` in `conftest.py`) so one run
answers "what is wrong with this branch", not "what is the first problem".

## `harness/`

| Module | Responsibility |
| --- | --- |
| `tf.py` | parse HCL with `python-hcl2`, normalise blocks (folds `dynamic "x"` into the block it renders), collect identifiers |
| `model.py` | `TfDirectory` / `Module` / `Repo`: variables, outputs, resources, module calls, test files, tfvars |
| `schema.py` | `ProviderSchema`: validates a resource body against the JSON contract |
| `__init__.py` | `discover_repo()`, `load_provider_schema()` |

## `schemas/azurerm_3.116.json`

A curated snapshot of the documented `hashicorp/azurerm` 3.116 argument
reference for exactly the resources used here, with three lists per resource:
`arguments` (+ `blocks`), `required`, `deprecated` and `exported` (readable
attributes). It exists so a rename like 4.x's `image_registry_credential` →
`image_registry_login` fails a test instead of a deploy.

When you adopt a new resource type, add it to this file — a test fails until you
do, and that is deliberate.

## Lane 2: native `terraform test`

`modules/*/tests/plan.tftest.hcl` runs against the real provider schema:

```bash
cd modules/acr && terraform init -backend=false && terraform test
```

All runs use `command = plan`, so no Azure credentials are required — only the
provider binary. Negative runs use `expect_failures` on the variable or resource
whose custom condition must fire, which is how the guardrails themselves get
proven. Because these files need a provider download, CI runs them; the offline
lane only checks their structure.

## Notes for contributors

* `Secound/` is a pre-existing stack; the style gates deliberately skip it.
* `pytest` config lives in `pytest.ini` here so `pytest tests` from the repo root
  uses `rootdir = tests/` and does not try to import `harness/` as a test module.
* Nothing in this directory talks to Azure. If a test starts needing a
  subscription, it belongs in lane 2 instead.
