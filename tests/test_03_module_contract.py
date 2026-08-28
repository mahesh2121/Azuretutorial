"""Gate 3 - module contract hygiene (the "is this reusable?" checks).

A module that cannot be consumed by another team is not production ready, so
this gate enforces: pinned providers, no backend, no provider configuration,
documented and typed inputs, sensitive handling for secrets, and no dead
inputs or locals.
"""

from __future__ import annotations

import re

from conftest import assert_clean

SENSITIVE_NAME = re.compile(r"(private_key|password|secret|api_key|shared_key|_token$|certificate)", re.I)
REQUIRED_DESCRIPTION_LENGTH = 25


def _terraform_settings(directory):
    blocks = directory.terraform_blocks
    return blocks[0] if blocks else None


def test_every_module_declares_versions(repo):
    failures: dict[str, list[str]] = {}
    for name, directory in list(repo.modules.items()) + list(repo.examples.items()):
        kind = "modules" if name in repo.modules else "examples"
        path = directory.path / "versions.tf"
        if not path.exists():
            failures.setdefault(f"{kind}/{directory.name}", []).append("missing versions.tf")
            continue
        block = _terraform_settings(directory)
        if block is None or not block.has("required_version"):
            failures.setdefault(f"{kind}/{directory.name}", []).append("versions.tf has no required_version")
    assert_clean(failures, "Each module and example must pin the Terraform version:")


def test_providers_are_pinned_to_a_major_version(repo):
    failures: dict[str, list[str]] = {}
    for label, directory in {f"modules/{k}": v for k, v in repo.modules.items()}.items():
        block = _terraform_settings(directory)
        if block is None:
            continue
        requirements = block.blocks.get("required_providers", [])
        payload = requirements[0] if requirements else {}
        for provider, spec in payload.items():
            if provider.startswith("__"):
                continue
            spec = spec if isinstance(spec, dict) else {}
            version = str(spec.get("version", "")).strip('"')
            source = str(spec.get("source", "")).strip('"')
            if not version:
                failures.setdefault(label, []).append(f"provider {provider!r} has no version constraint")
            elif not re.search(r"[<>~^]=?\s*\d+\.\d+", version):
                failures.setdefault(label, []).append(f"provider {provider!r} constraint {version!r} does not bound the major version")
            if provider == "azurerm" and source != "hashicorp/azurerm":
                failures.setdefault(label, []).append(f"azurerm must be sourced from hashicorp/azurerm, got {source!r}")
        # Modules must stay testable offline: a required_provider on a module is
        # fine, a `backend` block or a `provider` block is not.
        if block.blocks.get("backend"):
            failures.setdefault(label, []).append("modules must not declare a backend - state belongs to the caller")
    assert_clean(failures, "Provider contracts are incomplete:")


def test_modules_do_not_configure_providers(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        if module.providers:
            failures.setdefault(f"modules/{name}", []).append(f"provider block(s) present: {', '.join(module.providers)} - configure providers in the root module")
    assert_clean(failures, "Reusable modules must not configure providers:")


def test_test_framework_is_available_to_callers(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        block = _terraform_settings(module)
        if block is None:
            continue
        constraint = str(block.get("required_version", "")).strip('"')
        match = re.search(r">=\s*(\d+)\.(\d+)", constraint)
        if not match:
            failures.setdefault(f"modules/{name}", []).append(f"required_version {constraint!r} must use a >= bound")
            continue
        major, minor = int(match.group(1)), int(match.group(2))
        # `terraform test` needs 1.6; nested optional() defaults need 1.9.
        if (major, minor) < (1, 6):
            failures.setdefault(f"modules/{name}", []).append("required_version must be >= 1.6.0 so `terraform test` works")
        uses_nested_defaults = "optional(" in "\n".join(path.read_text() for path in module.path.glob("*.tf"))
        if uses_nested_defaults and (major, minor) < (1, 9):
            failures.setdefault(f"modules/{name}", []).append("nested optional() defaults require required_version >= 1.9.0")
    assert_clean(failures, "Terraform version bounds:")


def test_all_variables_are_typed_and_documented(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name, body in directory.variables.items():
            if not body.has("type"):
                failures.setdefault(label, []).append(f"variable {name!r} has no type constraint")
            description = str(body.get("description", ""))
            if len(description.strip('"')) < REQUIRED_DESCRIPTION_LENGTH:
                failures.setdefault(label, []).append(f"variable {name!r} needs a description of at least {REQUIRED_DESCRIPTION_LENGTH} characters")
    assert_clean(failures, "Module variables must be typed and documented:")


def test_all_outputs_are_documented(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name, body in directory.outputs.items():
            description = str(body.get("description", ""))
            if len(description.strip('"')) < 15:
                failures.setdefault(label, []).append(f"output {name!r} is missing a useful description")
            if not body.has("value"):
                failures.setdefault(label, []).append(f"output {name!r} has no value")
    assert_clean(failures, "Module outputs must be documented:")


def test_secret_looking_variables_are_sensitive(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name, body in directory.variables.items():
            if SENSITIVE_NAME.search(name) and body.get("sensitive") is not True:
                failures.setdefault(label, []).append(f"variable {name!r} looks like a credential and must set sensitive = true")
    assert_clean(failures, "Credential inputs must be marked sensitive:")


def test_no_unused_variables_or_locals(repo):
    """An input nobody reads is a lie; a local nobody uses is dead weight."""
    failures: dict[str, list[str]] = {}
    for label, directory in {f"modules/{k}": v for k, v in repo.modules.items()}.items():
        used_vars, used_locals = set(), set()
        for path in directory.path.glob("*.tf"):
            text = path.read_text()
            # drop the declaration headers so `variable "x"` does not count as a use
            text = re.sub(r'^\s*(variable|output|locals|terraform|required_providers)\b.*$', "", text, flags=re.M)
            used_vars.update(re.findall(r"\bvar\.([a-zA-Z0-9_-]+)", text))
            used_locals.update(re.findall(r"\blocal\.([a-zA-Z0-9_-]+)", text))
        for name in directory.variables:
            if name not in used_vars:
                failures.setdefault(label, []).append(f"variable {name!r} is never referenced")
        for name in directory.locals:
            if name not in used_locals:
                failures.setdefault(label, []).append(f"local {name!r} is never referenced")
    assert_clean(failures, "Remove unused inputs and locals:")


def test_required_inputs_are_enforced_by_validation(repo):
    """Enum-like string inputs must be validated, not documented and hoped for."""
    failures: dict[str, list[str]] = {}
    enumish = ("sku", "kind", "os_type", "restart_policy", "priority", "ip_address_type", "application_mode", "principal_type", "action", "bypass", "default_action")
    for label, module in {f"modules/{k}": v for k, v in repo.modules.items()}.items():
        for name, body in module.variables.items():
            if not any(token in name for token in enumish):
                continue
            if not body.block_bodies("validation"):
                failures.setdefault(label, []).append(f"variable {name!r} is an enum-like input with no validation block")
    assert_clean(failures, "Validate enum-like inputs:")


def test_modules_expose_a_resource_id_output(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        text = "\n".join(path.read_text() for path in module.path.glob("outputs.tf"))
        if "id" not in text:
            failures.setdefault(f"modules/{name}", []).append("outputs.tf must expose the primary resource ID")
    assert_clean(failures, "Modules must return IDs so callers can wire them together:")
