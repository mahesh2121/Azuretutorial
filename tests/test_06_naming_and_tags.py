"""Gate 6 - naming and tagging conventions.

The repository composes every resource name from
``<prefix>-{organization}-{environment}-{region}`` so that:

  * two environments can never collide,
  * `terraform plan` output is readable,
  * the Azure portal search box finds resources by owner and environment.

These tests keep new modules on that path and keep Azure's own hard limits
(lengths and character classes) encoded in the module, not in tribal knowledge.
"""

from __future__ import annotations

import re

from conftest import assert_clean

REQUIRED_TAG_KEYS = {"Environment", "Organization", "ManagedBy"}

AZURE_NAME_LIMITS = {
    # resource type: (max length, python regex for the generated name pattern)
    "azurerm_container_registry": (50, r"^acr[a-z0-9]{2,47}$"),
    "azurerm_notification_hub_namespace": (50, r"^[a-zA-Z0-9][a-zA-Z0-9-]{4,48}[a-zA-Z0-9]$"),
    "azurerm_resource_group": (90, r"^rg-"),
}


def _locals_text(module) -> str:
    path = module.path / "locals.tf"
    return path.read_text() if path.exists() else ""


def test_names_are_composed_from_organization_and_environment(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        text = _locals_text(directory) or "\n".join(path.read_text() for path in directory.path.glob("*.tf"))
        if "var.organization" not in text or "var.environment" not in text:
            failures.setdefault(label, []).append("no local composes names from var.organization and var.environment")
    assert_clean(failures, "Naming must be derived from organization + environment:")


NAME_LOCAL = re.compile(r"^(?P<indent>\s*)(?P<name>[a-z0-9_]*(_name|_name_prefix|_prefix|_names))\s*=\s*(?P<value>.*)$")
PAIRS = (("( ", ")"), ("[", "]"), ("{", "}"))


def _depth(text: str) -> int:
    return sum(text.count(open_) - text.count(close) for open_, close in (("(", ")"), ("[", "]"), ("{", "}")))


def _local_values(module) -> dict[str, str]:
    """Map every local in a module to the full text of its value (multi line safe)."""
    values: dict[str, str] = {}
    for path in sorted(module.path.glob("*.tf")):
        lines = path.read_text().splitlines()
        for index, line in enumerate(lines):
            match = NAME_LOCAL.match(line)
            if not match or match.group("name") not in module.locals or match.group("name") in values:
                continue
            chunk = [match.group("value")]
            depth = _depth(line.split("=", 1)[1])
            cursor = index + 1
            while depth > 0 and cursor < len(lines):
                chunk.append(lines[cursor])
                depth += _depth(lines[cursor])
                cursor += 1
            values[match.group("name")] = "\n".join(chunk)
    return values


def test_module_locals_expose_a_deterministic_name(owned_dirs):
    """Names must be produced by the module, not pasted in by every caller."""
    failures: dict[str, list[str]] = {}
    for label, module in {k: v for k, v in owned_dirs.items() if k.startswith("modules/")}.items():
        named = {name: value for name, value in _local_values(module).items() if name.endswith(("_name", "_name_prefix", "_prefix", "_names"))}
        if not named:
            failures.setdefault(label, []).append("no locals generate resource names (expected e.g. registry_name / name_prefix)")
            continue
        composed = [name for name, value in named.items() if "var.organization" in value or "var.environment" in value]
        if not composed:
            failures.setdefault(label, []).append(f"generated names are not derived from organization/environment: {sorted(named)}")
    assert_clean(failures, "Deterministic naming:")


def test_azure_hard_name_limits_are_enforced_in_modules(owned_dirs):
    """The name validation regexes must live in the module, not only in docs."""
    acr = owned_dirs.get("modules/acr")
    if acr:
        text = "\n".join(path.read_text() for path in acr.path.glob("*.tf"))
        assert r"^[a-z0-9]{5,50}$" in text, "modules/acr must validate the 5-50 lowercase alphanumeric ACR name rule"

    hub = owned_dirs.get("modules/notification-hub")
    if hub:
        text = "\n".join(path.read_text() for path in hub.path.glob("*.tf"))
        assert "[a-zA-Z0-9-]{4,48}" in text, "modules/notification-hub must validate the 6-50 namespace name rule"

    aci = owned_dirs.get("modules/aci")
    if aci:
        text = "\n".join(path.read_text() for path in aci.path.glob("*.tf"))
        assert "^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$" in text, "modules/aci must validate the 1-63 container group name rule"


def test_standard_tags_are_applied_everywhere(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        locals_text = _locals_text(directory) or "\n".join(path.read_text() for path in directory.path.glob("*.tf"))
        missing = sorted(key for key in REQUIRED_TAG_KEYS if key not in locals_text)
        if missing:
            failures.setdefault(label, []).append(f"standard tags missing: {', '.join(missing)}")
    assert_clean(failures, "Every stack must merge Environment/Organization/ManagedBy tags:")


UNTAGGABLE = {
    "azurerm_management_lock",
    "azurerm_role_assignment",
    "azurerm_monitor_diagnostic_setting",
    "azurerm_subnet_network_security_group_association",
    "azurerm_subnet",
    "azurerm_network_security_group",
    "azurerm_virtual_network",
    "azurerm_private_endpoint",
    "azurerm_private_dns_zone_virtual_network_link",
    "azurerm_container_registry_token",
    "azurerm_container_registry_scope_map",
}


def test_tags_flow_into_resources_and_modules(owned_dirs):
    """Everything Azure lets you tag must carry the standard tag set."""
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for (rtype, name), body in directory.resources.items():
            if rtype in UNTAGGABLE:
                continue
            if "tags" not in body.arguments:
                failures.setdefault(label, []).append(f"{rtype}.{name} has no tags argument")
        for module_name, body in directory.modules.items():
            if "tags" not in body.arguments:
                failures.setdefault(label, []).append(f"module {module_name!r} does not pass tags through")
    assert_clean(failures, "Tag everything that supports tags:")


def test_region_short_codes_are_shared(repo, owned_dirs):
    """The region -> short code table must stay identical across modules."""
    tables: dict[str, str] = {}
    for label, directory in {k: v for k, v in owned_dirs.items() if k.startswith("modules/")}.items():
        text = "\n".join(path.read_text() for path in directory.path.glob("*.tf"))
        match = re.search(r"region_short_codes\s*=\s*\{(.*?)\n\s*\}", text, flags=re.S)
        if match:
            tables[label] = re.sub(r"\s+", "", match.group(1))
    distinct = set(tables.values())
    assert tables, "no region_short_codes table found in any module"
    assert len(distinct) == 1, "region_short_codes tables have drifted apart:\n  " + "\n  ".join(
        f"{label}: {len(value)} chars" for label, value in sorted(tables.items())
    )
