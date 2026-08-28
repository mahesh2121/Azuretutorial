"""Gate 9 - the native `terraform test` suites must stay meaningful.

``terraform test`` is the tool that actually evaluates HCL, so this repository
ships ``modules/*/**.tftest.hcl`` run blocks for it. Those files cannot be
executed in the offline contract lane, so this gate statically verifies:

  * every module ships a test suite with positive *and* negative runs,
  * runs only set variables the module declares and set all required ones,
  * every assert has a condition and an error message,
  * expect_failures references real objects.

Run them for real with ``make test-terraform`` (needs Terraform >= 1.6).
"""

from __future__ import annotations

import re

from conftest import assert_clean  # noqa: F401

from harness.tf import parse

RESOURCE_ADDRESS = re.compile(r"^[a-z][a-z0-9_]*(\.[a-zA-Z0-9_-]+)(\[[^\]]+\])?$")


def _runs(test_file):
    config = parse(test_file)
    runs = []
    for entry in config.get("run", []) or []:
        for name, body in entry.items():
            runs.append((name.strip('"'), body if isinstance(body, dict) else {}))
    return config, runs


def test_every_module_ships_terraform_tests(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        files = sorted(module.path.glob("tests/*.tftest.hcl"))
        if not files:
            failures.setdefault(f"modules/{name}", []).append("no tests/*.tftest.hcl suite")
    assert_clean(failures, "Every module needs native Terraform tests:")


def test_suites_mix_positive_and_negative_runs(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        for test_file in sorted(module.path.glob("tests/*.tftest.hcl")):
            _config, runs = _runs(test_file)
            if len(runs) < 4:
                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"only {len(runs)} run block(s); ship at least 4")
            with_asserts = [label for label, body in runs if body.get("assert")]
            negative = [label for label, body in runs if "expect_failures" in body]
            if len(with_asserts) < 3:
                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append("need at least 3 runs with assert blocks")
            if not negative:
                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append("no negative run: guardrails must be proven to bite")
    assert_clean(failures, "Weak test suites:")


def test_runs_only_use_declared_module_variables(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        declared = set(module.variables)
        required = module.required_variables
        for test_file in sorted(module.path.glob("tests/*.tftest.hcl")):
            _config, runs = _runs(test_file)
            for label, body in runs:
                variables = body.get("variables") or {}
                provided = {}
                for entry in variables if isinstance(variables, list) else [variables]:
                    if isinstance(entry, dict):
                        provided.update(entry)
                provided = {key: value for key, value in provided.items() if not key.startswith("__")}
                unknown = sorted(set(provided) - declared)
                if unknown:
                    failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} sets undeclared variable(s): {', '.join(unknown)}")
                missing = sorted(required - set(provided))
                if missing:
                    failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} misses required variable(s): {', '.join(missing)}")
    assert_clean(failures, "Test runs must match the module contract:")


def test_assert_blocks_are_complete(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        for test_file in sorted(module.path.glob("tests/*.tftest.hcl")):
            _config, runs = _runs(test_file)
            for label, body in runs:
                for index, assertion in enumerate(body.get("assert") or [], 1):
                    if not isinstance(assertion, dict):
                        continue
                    if "condition" not in assertion:
                        failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} assert #{index} has no condition")
                    message = str(assertion.get("error_message", "")).strip('"')
                    if len(message) < 20:
                        failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} assert #{index} needs a helpful error_message")
    assert_clean(failures, "Assertion hygiene:")


def test_expect_failures_reference_real_objects(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        declared_vars = set(module.variables)
        declared_resources = {rtype for rtype, _ in module.resources}
        for test_file in sorted(module.path.glob("tests/*.tftest.hcl")):
            raw = test_file.read_text()
            _config, runs = _runs(test_file)
            for label, body in runs:
                if "expect_failures" not in body:
                    continue
                for entry in body.get("expect_failures") or []:
                    for reference in re.findall(r"[a-zA-Z0-9_.\[\]\"]+", str(entry)):
                        if reference.startswith("var."):
                            variable = reference.split(".", 1)[1]
                            if variable not in declared_vars:
                                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} expects a failure on unknown var.{variable}")
                        elif reference.startswith("azurerm_"):
                            base = re.sub(r"\[[^\]]*\]", "", reference)
                            if not RESOURCE_ADDRESS.match(base):
                                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r}: {reference!r} is not a resource address")
                            elif base.split(".")[0] not in declared_resources:
                                failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} expects a failure on unknown resource {base}")
    # the raw text check keeps the parsing honest: every expect_failures block must
    # actually list at least one object
    for path in sorted(repo.root.glob("modules/*/tests/*.tftest.hcl")):
        for match in re.finditer(r"expect_failures\s*=\s*\[([^\]]*)\]", path.read_text()):
            if not match.group(1).strip():
                failures.setdefault(str(path.relative_to(repo.root)), []).append("expect_failures is empty")
    assert_clean(failures, "expect_failures targets:")


def test_negative_runs_do_not_also_assert(repo):
    """Terraform halts on the expected error, so asserts there are dead weight."""
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        for test_file in sorted(module.path.glob("tests/*.tftest.hcl")):
            _config, runs = _runs(test_file)
            for label, body in runs:
                if "expect_failures" in body and body.get("assert"):
                    failures.setdefault(f"modules/{name}/tests/{test_file.name}", []).append(f"run {label!r} mixes expect_failures with assert blocks")
    assert_clean(failures, "Negative runs should not assert:")


def test_plan_only_runs_are_declared(repo):
    """Offline unit tests must never plan an apply: they would need credentials."""
    failures: dict[str, list[str]] = {}
    for path in sorted(repo.root.glob("modules/*/tests/*.tftest.hcl")):
        text = path.read_text()
        for block in re.finditer(r"run\s+\"([^\"]+)\"\s*\{(.*?)\n\}", text, flags=re.S):
            label, body = block.group(1), block.group(2)
            if "command" in body and "plan" not in body:
                failures.setdefault(str(path.relative_to(repo.root)), []).append(f"run {label!r} is not command = plan")
    assert_clean(failures, "Module unit tests must stay plan-only:")
