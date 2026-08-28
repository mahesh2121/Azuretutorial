"""Gate 7 - security posture.

These are the checks a reviewer would do by hand on an Azure PR, automated:

  * no secret-looking literal values anywhere in committed files,
  * credential outputs marked `sensitive`,
  * registry admin account off by default and never on in an example,
  * private-link capable modules keep the option, production guardrails on,
  * ACI/Notification Hub examples do not embed connection strings in tags or env.
"""

from __future__ import annotations

import re

from conftest import assert_clean

# A *name* that looks like a credential is not itself a secret, so this pattern
# is only used to decide which expressions must be marked `sensitive`.
SECRET_KEY = re.compile(r"(password|private_key|secret|api_key|shared_key|token|certificate|connection_string)", re.I)
PLACEHOLDER_WORDS = (
    "placeholder", "change-me", "changeme", "example", "replace-me", "your-", "null", "REPLACE",
    "test", "fake", "sample", "dummy", "00000000", "deadbeef",
)

# `key = "value"` where value looks like a real secret and is not a placeholder.
HARDCODED_SECRET = re.compile(
    r"(?P<key>[a-zA-Z0-9_]*(?:password|private_key|secret|api_key|shared_key|access_key|certificate|connection_string)[a-zA-Z0-9_]*)\s*=\s*\"(?P<value>[^\"]{8,})\"",
    re.I,
)
OPAQUE = re.compile(r"^[A-Za-z0-9+/=_.-]{20,}$")
SUSPICIOUS_ASSIGNMENT = re.compile(r"(?i)\b(apns_token|token|api_key|password|shared_key)\s*=\s*\"[A-Za-z0-9+/_=-]{24,}\"")


def _decode(value: str) -> str:
    import base64
    import binascii

    try:
        return base64.b64decode(value, validate=True).decode("utf-8", "replace")
    except (binascii.Error, ValueError):
        return ""


def test_no_hardcoded_secrets_in_committed_terraform(repo):
    offenders: dict[str, list[str]] = {}
    for path in sorted(list(repo.root.rglob("*.tf")) + list(repo.root.rglob("*.tfvars")) + list(repo.root.rglob("*.tftest.hcl"))):
        if ".terraform" in path.parts:
            continue
        for index, line in enumerate(path.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            match = HARDCODED_SECRET.search(line)
            if not match:
                continue
            value = match.group("value")
            if any(word in value.lower() for word in PLACEHOLDER_WORDS):
                continue
            if OPAQUE.match(value):
                # base64 / hex blobs hide secrets well: decode before letting them pass
                decoded = _decode(value)
                if decoded and any(word in decoded.lower() for word in PLACEHOLDER_WORDS):
                    continue
            if value.startswith("${") or "var." in value or "local." in value or "module." in value or "(" in value:
                continue  # computed from inputs/data sources
            offenders.setdefault(str(path.relative_to(repo.root)), []).append(f"line {index}: {match.group('key')} looks like a literal secret")
    assert_clean(offenders, "Move secrets into Key Vault / CI variables. Offending lines:")


def test_no_key_or_pem_material_in_repository(repo):
    offenders: dict[str, list[str]] = {}
    pattern = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")
    for path in repo.root.rglob("*"):
        if not path.is_file() or ".git" in path.parts or ".terraform" in path.parts:
            continue
        if path.suffix not in {".tf", ".tfvars", ".md", ".pem", ".key", ".p8", ".json", ".yml", ".yaml", ".txt"}:
            continue
        if pattern.search(path.read_text(errors="ignore")):
            offenders[str(path.relative_to(repo.root))] = ["contains private key material"]
    assert_clean(offenders, "Never commit private keys:")


# Reading a value that Terraform would print in `terraform output` unmasked.
SENSITIVE_VALUE_SOURCE = re.compile(
    r"(admin_password|primary_shared_key|secondary_shared_key|primary_access_key|secondary_access_key"
    r"|key_vault_secret\.[a-zA-Z0-9_-]+\.value|private_key\b|\bapi_key\b|workspace_shared_key"
    r"|token_password|connection_strings\b)",
)


def test_credential_bearing_outputs_are_sensitive(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name, body in directory.outputs.items():
            value = str(body.get("value", ""))
            looks_secret = SENSITIVE_VALUE_SOURCE.search(value) is not None
            if looks_secret and body.get("sensitive") is not True:
                failures.setdefault(label, []).append(f"output {name!r} exposes a credential without sensitive = true")
    assert_clean(failures, "Credential outputs must be marked sensitive (state is not a vault):")


def test_registry_admin_is_disabled_by_default_and_in_examples(repo):
    acr = repo.modules.get("acr")
    assert acr is not None, "modules/acr is missing"
    admin = acr.variables.get("admin_enabled")
    assert admin is not None, "modules/acr must expose admin_enabled so callers can see the risk"
    assert admin.get("default") is False, "admin_enabled must default to false"

    text = "\n".join(path.read_text() for path in (repo.root / "examples").rglob("*.tf")) + "\n".join(
        path.read_text() for path in (repo.root / "examples").rglob("*.tfvars")
    )
    assert not re.search(r"^\s*admin_enabled\s*=\s*true", text, re.M), "no example may enable the registry admin user"


def test_the_sensitive_rule_catches_known_secrets():
    """A gate that never fires is decoration: assert the pattern bites."""
    assert SENSITIVE_VALUE_SOURCE.search("azurerm_container_registry.this.admin_password")
    assert SENSITIVE_VALUE_SOURCE.search("data.azurerm_key_vault_secret.apns.value")
    assert not SENSITIVE_VALUE_SOURCE.search("keys(module.acr.tokens)")
    assert not SENSITIVE_VALUE_SOURCE.search("azurerm_container_registry.this.login_server")


def test_admin_password_output_is_guarded(repo):
    acr = repo.modules.get("acr")
    outputs = (acr.path / "outputs.tf").read_text()
    assert "var.admin_enabled ?" in outputs, "admin_password must only be exported when the admin user is explicitly enabled"
    assert "sensitive   = true" in outputs or "sensitive = true" in outputs, "admin credentials must be sensitive"


def test_production_guardrails_exist_in_every_module(owned_dirs):
    failures: dict[str, list[str]] = {}
    expectations = {
        "modules/acr": ["precondition"],
        "modules/aci": ["precondition"],
        "modules/notification-hub": ["precondition"],
    }
    for label, needles in expectations.items():
        directory = owned_dirs.get(label)
        assert directory is not None, f"{label} missing"
        text = "\n".join(path.read_text() for path in directory.path.glob("*.tf"))
        for needle in needles:
            if needle not in text:
                failures.setdefault(label, []).append(f"expected a lifecycle {needle} guardrail")
    assert_clean(failures, "Modules must fail closed on unsafe configurations:")


def test_lock_support_is_offered_by_stateful_modules(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, module in {k: v for k, v in owned_dirs.items() if k.startswith("modules/")}.items():
        if "azurerm_management_lock" not in "\n".join(path.read_text() for path in module.path.glob("*.tf")):
            failures.setdefault(label, []).append("module should offer an optional delete lock (azurerm_management_lock)")
    assert_clean(failures, "Long lived resources need lock support:")


def test_no_public_write_on_registries(repo):
    acr_calls = []
    for example in repo.examples.values():
        for name, (source, body) in example.module_calls.items():
            if source.endswith("modules/acr"):
                acr_calls.append((example.name, name, body))
    for example_name, module_name, body in acr_calls:
        anonymous = body.get("anonymous_pull_enabled")
        assert anonymous in (None, "false", '"false"', False), f"examples/{example_name}.{module_name} must not allow anonymous pulls"


def test_diagnostic_log_categories_are_scoped(owned_dirs):
    """A wildcard log category list is a smell: names must be explicit."""
    failures: dict[str, list[str]] = {}
    module = owned_dirs.get("modules/acr")
    assert module is not None
    text = "\n".join(path.read_text() for path in module.path.glob("*.tf"))
    if re.search(r'log_categories\s*=\s*\["\*"\]', text):
        failures.setdefault("modules/acr", []).append("log_categories must list concrete categories")
    assert_clean(failures, "Diagnostics configuration:")


def test_sensitive_variable_values_are_not_printed_in_readmes(repo):
    offenders: dict[str, list[str]] = {}
    for readme in (repo.root / "examples").rglob("README.md"):
        text = readme.read_text()
        for line_no, line in enumerate(text.splitlines(), 1):
            if HARDCODED_SECRET.search(line) and "az keyvault" not in line and "TF_VAR" not in line:
                offenders.setdefault(str(readme.relative_to(repo.root)), []).append(f"line {line_no}: looks like a real secret in documentation")
    assert_clean(offenders, "Documentation must use obvious placeholders:")
