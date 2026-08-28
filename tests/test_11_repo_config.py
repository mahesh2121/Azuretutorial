"""Gate 11 - repository configuration (the files that make CI trustworthy).

A green pipeline that never runs the tests, a `.gitignore` that hides the
runnable tfvars, or a CI job that can `terraform apply` from a pull request are
all real incidents. These checks keep the plumbing honest.
"""

from __future__ import annotations

import subprocess  # noqa: S404 - deliberate: `git check-ignore` is the oracle
import sys
from pathlib import Path

import pytest

from conftest import assert_clean  # noqa: F401
from harness.tf import parse

sys.path.insert(0, str(Path(__file__).resolve().parent))


def test_gitignore_covers_terraform_artifacts(repo):
    text = (repo.root / ".gitignore").read_text()
    for needle in (".terraform/", "*.tfstate", "crash.log", "__pycache__/"):
        assert needle in text, f".gitignore should ignore {needle!r}"


def test_runnable_tfvars_are_not_ignored(repo):
    """`git check-ignore` is the truth: examples must stay cloneable and runnable."""
    tracked = sorted(repo.root.glob("examples/*/environments/*.tfvars"))
    assert tracked, "no example tfvars found"
    ignored = []
    for path in tracked:
        relative = path.relative_to(repo.root)
        result = subprocess.run(  # noqa: S603
            ["git", "check-ignore", "-q", str(relative)],
            cwd=repo.root,
            check=False,
            capture_output=True,
        )
        if result.returncode == 0:
            ignored.append(str(relative))
    assert not ignored, "these runnable tfvars files are git-ignored:\n  " + "\n  ".join(ignored)


def test_no_real_credentials_in_ignored_patterns(repo):
    """The ignore list must not hide a *secret* file that someone will commit anyway."""
    text = (repo.root / ".gitignore").read_text()
    for pattern in ("*.pem", "*.p8", "*.key", ".env"):
        assert pattern in text, f".gitignore should exclude {pattern!r} (key material)"


@pytest.mark.parametrize("name", [".tflint.hcl"])
def test_tflint_config_parses_and_enables_the_right_rules(repo, name):
    path = repo.root / name
    assert path.exists(), f"{name} is missing"
    config = parse(path)
    plugins = {}
    for entry in config.get("plugin", []) or []:
        for plugin_name, body in entry.items():
            plugins[plugin_name.strip('"')] = body
    for plugin in ("terraform", "azurerm"):
        assert plugin in plugins, f"{name} must configure the {plugin!r} ruleset"
        assert plugins[plugin].get("enabled") is True, f"{plugin} plugin must be enabled"
        assert "version" in plugins[plugin], f"{plugin} plugin must be version pinned"
    rules = {}
    for entry in config.get("rule", []) or []:
        for rule_name, body in entry.items():
            rules[rule_name.strip('"')] = body
    for rule in ("terraform_documented_variables", "terraform_typed_variables", "terraform_unused_declarations"):
        assert rules.get(rule, {}).get("enabled") is True, f"enable the {rule} rule"


def test_ci_workflow_is_valid_and_never_deploys(repo):
    yaml = pytest.importorskip("yaml", reason="PyYAML is in tests/requirements.txt")
    workflows = sorted((repo.root / ".github" / "workflows").glob("*.yml"))
    assert workflows, "no GitHub workflow found"
    failures: dict[str, list[str]] = {}
    for path in workflows:
        text = path.read_text()
        try:
            document = yaml.safe_load(text)
        except yaml.YAMLError as exc:  # pragma: no cover - exercised by broken CI files
            failures[str(path.relative_to(repo.root))] = [f"invalid YAML: {exc}"]
            continue
        jobs = (document or {}).get("jobs", {})
        if not jobs:
            failures.setdefault(str(path.relative_to(repo.root)), []).append("no jobs")
        runs = "\n".join(
            str(step.get("run", "")) for job in jobs.values() for step in job.get("steps", []) if isinstance(step, dict)
        )
        for forbidden in ("terraform apply", "terraform destroy"):
            if forbidden in runs:
                failures.setdefault(str(path.relative_to(repo.root)), []).append(
                    f"CI must not run `{forbidden}` - that is a deployment, not a check"
                )
        for required in ("pytest", "terraform test", "terraform validate", "terraform fmt -check", "gen-docs.py --check"):
            if required not in runs and required not in text:
                failures.setdefault(str(path.relative_to(repo.root)), []).append(f"CI never runs `{required}`")
        if "timeout-minutes" not in text:
            failures.setdefault(str(path.relative_to(repo.root)), []).append("jobs without timeout-minutes can burn runner minutes")
        if "permissions:" not in text:
            failures.setdefault(str(path.relative_to(repo.root)), []).append("workflow has no explicit `permissions:` block")
    assert_clean(failures, "Workflow problems:")


def test_requirements_match_the_imports(repo):
    requirements = (repo.root / "tests" / "requirements.txt").read_text().lower()
    imported = set()
    for path in (repo.root / "tests").rglob("*.py"):
        for line in path.read_text().splitlines():
            if line.startswith(("import hcl2", "from hcl2", "import yaml", "from yaml", "import pytest")):
                imported.add(line.split()[1].split(".")[0])
    missing = sorted(name for name in imported if name not in requirements)
    assert not missing, f"tests import {missing} but tests/requirements.txt does not pin them"


def test_run_all_is_executable_and_strict(repo):
    script = repo.root / "tests" / "run_all.sh"
    text = script.read_text()
    assert text.startswith("#!/usr/bin/env bash"), "run_all.sh needs a bash shebang"
    assert "set -euo pipefail" in text, "run_all.sh must fail fast"
    if hasattr(script.stat(), "st_mode"):
        assert script.stat().st_mode & 0o111, "run_all.sh must be executable (chmod +x)"


def test_editorconfig_matches_the_style_gate(repo):
    path = repo.root / ".editorconfig"
    if not path.exists():
        pytest.skip("no .editorconfig in this repository")
    text = path.read_text()
    assert text.startswith("#") or text.startswith("root"), "an .editorconfig should open with root = true"
    assert "root = true" in text, "missing `root = true` - parent configs would leak in"
    assert "\t" not in text, "the editorconfig file itself must not need tabs"
    assert text.count("[") >= 3, "expected per-glob sections for tf, python and markdown"
    for line in text.splitlines():
        if "=" in line and not line.strip().startswith(("#", "[")):
            assert not line.startswith((" ", "\t")), f"{line!r}: editorconfig keys must start at column 0"
            key, _value = line.split("=", 1)
            assert key.strip() and _value.strip(), f"{line!r} looks half written"
    assert "insert_final_newline = true" in text, "tests require exactly one trailing newline"
    assert "indent_style = space" in text, "the style gate rejects tabs"
    assert "end_of_line = lf" in text, "mixed line endings break `terraform fmt -check`"
    assert "trim_trailing_whitespace = false" in text, "markdown needs trailing whitespace preserved"


def test_provider_and_terraform_pins_are_consistent(owned_dirs):
    """Mixed pins mean `init` resolves different providers per directory."""
    failures: dict[str, list[str]] = {}
    azurerm: dict[str, str] = {}
    terraform: dict[str, str] = {}
    for label, directory in owned_dirs.items():
        for block in directory.terraform_blocks:
            for entry in block.blocks.get("required_providers", []) or []:
                for provider, spec in entry.items():
                    if provider == "azurerm" and isinstance(spec, dict):
                        azurerm[label] = str(spec.get("version", "")).strip('"')
            terraform[label] = str(block.get("required_version", "")).strip('"')
    assert azurerm, "no azurerm requirement found in any directory"
    if len(set(azurerm.values())) > 1:
        failures["azurerm version"] = [f"{label}: {value}" for label, value in sorted(azurerm.items())]
    if len(set(terraform.values())) > 1:
        failures["required_version"] = [f"{label}: {value}" for label, value in sorted(terraform.items())]
    assert_clean(failures, "Pins have drifted apart:")


def test_modules_and_examples_use_the_same_azurerm_major(owned_dirs):
    majors = set()
    for directory in owned_dirs.values():
        for block in directory.terraform_blocks:
            for entry in block.blocks.get("required_providers", []) or []:
                for provider, spec in entry.items():
                    if provider == "azurerm" and isinstance(spec, dict):
                        version = str(spec.get("version", "")).strip('"')
                        digits = [part for part in version.replace(",", " ").split() if part[0].isdigit()]
                        if digits:
                            majors.add(digits[0].split(".")[0])
    assert len(majors) <= 1, f"the repository mixes azurerm majors {sorted(majors)} - pick one and migrate deliberately"
