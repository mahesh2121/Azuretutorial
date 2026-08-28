"""Gate 4 - provider contract.

Every resource argument in this repository is checked against
``tests/schemas/azurerm_*.json``, a curated copy of the documented
``hashicorp/azurerm`` argument reference for the pinned provider version.
That catches:

  * renamed or removed arguments (a top cause of "worked last week" bugs),
  * deprecated arguments that Azure still accepts but the provider warns on,
  * missing required arguments,
  * typos in nested block arguments, which Terraform rejects at plan time.
"""

from __future__ import annotations

import re

from conftest import assert_clean

from harness.tf import normalize_body


def test_only_known_resource_types_are_used(owned_dirs, schema):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        unknown = schema.unknown_types(directory.resource_types)
        if unknown:
            failures.setdefault(label, []).append(f"resource type(s) missing from the provider contract: {', '.join(sorted(unknown))}")
    assert_clean(failures, "Add the resource to tests/schemas/ or stop using it:")


def test_resource_arguments_match_the_provider_schema(owned_dirs, schema):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for (rtype, rname), body in directory.resources.items():
            for finding in schema.validate_resource(rtype, body):
                failures.setdefault(f"{label}: {rtype}.{rname}", []).append(finding)
    assert_clean(failures, "Resource arguments diverge from the azurerm provider contract:")


def test_data_source_arguments_match_the_provider_schema(owned_dirs, schema):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for (dtype, dname), body in directory.data_sources.items():
            for finding in schema.validate_data_source(dtype, body):
                failures.setdefault(f"{label}: data.{dtype}.{dname}", []).append(finding)
    assert_clean(failures, "Data source arguments diverge from the provider contract:")


def test_attribute_references_are_readable_on_the_resource(owned_dirs, schema):
    """`azurerm_x.this.some_typo` fails at plan - catch it here instead."""
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        declared = {rtype for rtype, _ in directory.resources}
        for rtype, _name, attribute in directory.refs["resource_attr"]:
            if rtype not in declared:
                continue  # reference into another stack, not checkable here
            if not schema.validate_attribute_reference(rtype, attribute):
                failures.setdefault(label, []).append(f"{rtype}.<name>.{attribute} is not an exported attribute of {rtype}")
    assert_clean(failures, "Attribute references must exist on the resource:")


def test_deprecated_arguments_are_not_used(schema, owned_dirs):
    """Azure still accepts these, the provider warns or errors on them."""
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for (rtype, name), body in directory.resources.items():
            for finding in schema.validate_deprecated(rtype, body):
                failures.setdefault(f"{label}: {rtype}.{name}", []).append(finding)
    assert_clean(failures, "Deprecated provider arguments are in use:")


def test_required_arguments_are_present_in_the_contract(schema):
    broken = []
    for rtype, spec in schema.resources.items():
        for name in spec.get("required", []):
            if name not in spec.get("arguments", []) and name not in spec.get("blocks", {}):
                broken.append(f"{rtype}: required {name!r} is not declared as an argument or block")
    assert not broken, "Provider contract is internally inconsistent:\n  " + "\n  ".join(broken)


def test_body_normalisation_handles_dynamic_blocks(schema):
    """The harness folds `dynamic "x" {}` into the block it renders."""
    body = normalize_body(
        {
            "name": "${local.x}",
            "resource_group_name": "${var.resource_group_name}",
            "location": "${var.location}",
            "sku": "Premium",
            "dynamic": [
                {
                    "\"georeplications\"": {
                        "for_each": "${local.georeplications}",
                        "content": [{"location": "${georeplications.key}", "__is_block__": True}],
                        "__is_block__": True,
                    }
                }
            ],
            "__is_block__": True,
        }
    )
    assert body.arguments["name"] == "${local.x}"
    assert "dynamic" not in body.arguments
    assert body.blocks["georeplications"][0]["location"] == "${georeplications.key}"
    assert schema.validate_resource("azurerm_container_registry", body) == []
