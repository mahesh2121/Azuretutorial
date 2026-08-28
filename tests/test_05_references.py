"""Gate 5 - reference graph integrity.

Terraform resolves identifiers at plan time; these tests resolve them here so a
typo never reaches CI. Checks:

  * every ``var.x`` / ``local.x`` used in a directory is declared in it,
  * every ``module.x.attr`` exists as an output of the called module,
  * every resource reference points at a declared resource,
  * no module block passes an input the module does not accept.
"""

from __future__ import annotations

import re

from conftest import assert_clean  # noqa: F401

from harness.tf import parse, tf_files, merge_configs, Body

MODULE_ARG_ALLOWLIST = {"source", "version", "providers", "depends_on", "count", "for_each"}


def _module_config(directory, source: str):
    from harness.model import Module

    target = (directory.path / source).resolve()
    if not target.is_dir() or not list(target.glob("*.tf")):
        return None, target
    config = merge_configs(parse(path) for path in tf_files(target, "*.tf"))
    return Module(path=target, kind="module", config=config), target


def test_every_var_reference_is_declared(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name in directory.refs["var"]:
            if name not in directory.variables:
                failures.setdefault(label, []).append(f"var.{name} is used but never declared")
    assert_clean(failures, "Undeclared input variables:")


def test_every_local_reference_is_declared(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name in directory.refs["local"]:
            if name not in directory.locals:
                failures.setdefault(label, []).append(f"local.{name} is used but never declared")
    assert_clean(failures, "Undeclared locals:")


def test_resource_references_point_at_declared_resources(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        declared = {f"{rtype}.{name}" for rtype, name in directory.resources}
        for rtype, name, attribute in directory.refs["resource_attr"]:
            address = f"{rtype}.{name}"
            if address not in declared:
                failures.setdefault(label, []).append(f"{address}.{attribute} references a resource that is not declared here")
    assert_clean(failures, "Broken resource references:")


def test_module_calls_match_the_module_contract(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        for name, body in directory.modules.items():
            source = str(body.get("source", "")).strip('"')
            if not source:
                failures.setdefault(label, []).append(f"module {name!r} has no source")
                continue
            module, target = _module_config(directory, source)
            if module is None:
                failures.setdefault(label, []).append(f"module {name!r} source {source!r} does not resolve to a directory with .tf files ({target})")
                continue
            provided = {key for key in body.arguments if key not in MODULE_ARG_ALLOWLIST}
            unknown = sorted(provided - set(module.variables))
            if unknown:
                failures.setdefault(label, []).append(f"module {name!r} passes undeclared input(s): {', '.join(unknown)}")
            missing = sorted(module.required_variables - provided)
            if missing:
                failures.setdefault(label, []).append(f"module {name!r} is missing required input(s): {', '.join(missing)}")
    assert_clean(failures, "Module calls do not match the called module:")


def test_module_attribute_references_exist(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in owned_dirs.items():
        calls = {name: str(body.get("source", "")).strip('"') for name, body in directory.modules.items()}
        for module_name, attributes in _group_module_attributes(directory).items():
            if module_name not in calls:
                continue
            source = calls[module_name]
            module, _target = _module_config(directory, source)
            if module is None:
                continue
            for attribute in sorted(attributes):
                if attribute not in module.outputs:
                    failures.setdefault(label, []).append(f"module.{module_name}.{attribute} is not an output of {source}")
    assert_clean(failures, "Module output references:")


def _group_module_attributes(directory) -> dict[str, set[str]]:
    grouped: dict[str, set[str]] = {}
    for module_name, attribute in directory.refs["module_attr"]:
        grouped.setdefault(module_name, set()).add(attribute)
    return grouped


def test_no_reference_to_removed_helper(repo, owned_dirs):
    """Catch the classic copy-paste leftovers."""
    failures: dict[str, list[str]] = {}
    stale = re.compile(r"\b(data\.terraform_remote_state|local\.workspace)\b")
    for label, directory in owned_dirs.items():
        for expression in directory.expressions:
            if stale.search(expression):
                failures.setdefault(label, []).append(f"stale reference: {expression[:80]}")
    assert_clean(failures, "Remove references that do not exist in this repository:")
