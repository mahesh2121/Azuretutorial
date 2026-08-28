"""Gate 8 - the examples are the module documentation users actually run.

An example that does not plan is worse than no example, so these tests keep the
`examples/` trees wired to the current module contract: every variable they set
exists, every required variable is set, and each custom module is exercised.
"""

from __future__ import annotations

import re

from conftest import assert_clean  # noqa: F401

from harness.tf import parse

REQUIRED_EXAMPLE_FILES = ["versions.tf", "providers.tf", "main.tf", "variables.tf", "outputs.tf", "README.md"]

ALLOWED_ENVIRONMENTS = {"dev", "staging", "uat", "prod", "dr"}


def test_example_layout(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in {k: v for k, v in owned_dirs.items() if k.startswith("examples/")}.items():
        missing = [name for name in REQUIRED_EXAMPLE_FILES if not (directory.path / name).exists()]
        if missing:
            failures.setdefault(label, []).append(f"missing file(s): {', '.join(missing)}")
        if not directory.tfvars_files:
            failures.setdefault(label, []).append("no environments/*.tfvars - examples must ship runnable variable files")
    assert_clean(failures, "Example folders must be complete:")


def test_examples_use_the_local_modules(repo):
    failures: dict[str, list[str]] = {}
    for name, example in repo.examples.items():
        if not example.module_calls:
            failures.setdefault(f"examples/{name}", []).append("does not call any module from modules/")
            continue
        for module_name, (source, _body) in example.module_calls.items():
            if not source.startswith("../../modules/"):
                failures.setdefault(f"examples/{name}", []).append(f"module {module_name!r} should use a relative source under ../../modules/, got {source!r}")
    assert_clean(failures, "Examples must consume the custom modules:")


def test_every_module_is_covered_by_an_example(repo):
    covered = set()
    for example in repo.examples.values():
        for _name, (source, _body) in example.module_calls.items():
            covered.add(source.split("/")[-1])
    missing = sorted(set(repo.modules) - covered)
    assert not missing, f"these modules have no example: {', '.join(missing)}"


def test_tfvars_only_set_declared_variables(repo, owned_dirs):
    failures: dict[str, list[str]] = {}
    for name, example in repo.examples.items():
        declared = set(example.variables)
        for tfvars in example.tfvars_files:
            payload = parse(tfvars)
            keys = {key for key in payload if not key.startswith("__")}
            unknown = sorted(keys - declared)
            if unknown:
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"sets undeclared variable(s): {', '.join(unknown)}")
            required = sorted(key for key, body in example.variables.items() if not body.has("default") and key not in keys)
            if required:
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"missing required variable(s): {', '.join(required)}")
    assert_clean(failures, "tfvars files must match the example variables:")


def test_environment_files_are_self_consistent(repo):
    failures: dict[str, list[str]] = {}
    for name, example in repo.examples.items():
        for tfvars in example.tfvars_files:
            payload = parse(tfvars)
            environment = str(payload.get("environment", "")).strip('"')
            location = str(payload.get("location", "")).strip('"')
            if environment and environment not in ALLOWED_ENVIRONMENTS:
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"environment {environment!r} is not one of {sorted(ALLOWED_ENVIRONMENTS)}")
            if location and not re.fullmatch(r"[a-z0-9]+", location):
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"location {location!r} must be lowercase without spaces")
            file_hint = tfvars.stem
            if environment and file_hint not in ALLOWED_ENVIRONMENTS and file_hint != environment:
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"file name {file_hint!r} should match environment {environment!r}")
            if environment and file_hint in ALLOWED_ENVIRONMENTS and file_hint != environment:
                failures.setdefault(f"examples/{name}/{tfvars.name}", []).append(f"file name {file_hint!r} contradicts environment {environment!r}")
    assert_clean(failures, "Environment files:")


def test_examples_declare_providers_and_backend(owned_dirs):
    failures: dict[str, list[str]] = {}
    for label, directory in {k: v for k, v in owned_dirs.items() if k.startswith("examples/")}.items():
        if not directory.providers:
            failures.setdefault(label, []).append("root module must configure provider \"azurerm\"")
        backends = [block for body in directory.terraform_blocks for block in body.blocks.get("backend", [])]
        if not backends:
            failures.setdefault(label, []).append("example should declare a backend block (local or azurerm) so state handling is explicit")
    assert_clean(failures, "Example roots must own provider + backend configuration:")


def test_full_stack_example_wires_the_three_services_together(repo):
    stack = repo.examples.get("full-stack")
    assert stack is not None, "examples/full-stack must exist"
    assert {"acr", "aci", "notifications"} <= set(stack.module_calls), "the full-stack example must call all three modules"

    text = "\n".join(path.read_text() for path in stack.path.glob("*.tf"))
    assert "module.acr.login_server" in text, "ACI must pull the image from the registry created in the same stack"
    assert "AcrPull" in text, "the ACI identity must be granted AcrPull on the registry"
    assert "module.notifications" in text, "the workload must be told which hub to push to"
    assert "delegation" in text, "private ACI needs a delegated subnet"
