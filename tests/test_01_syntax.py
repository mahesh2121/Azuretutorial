"""Gate 1 - every Terraform file in the repository must be parseable HCL.

This is the cheapest possible regression test and it catches:
  * unbalanced braces / missing quotes introduced by copy-paste edits,
  * HCL constructs the language does not know (typos such as `dynmic`),
  * truncated files from a bad merge.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from conftest import assert_clean  # noqa: F401  (shared helper)

from harness.tf import HCLParseError, parse

# Only these block types are legal at the top level of a .tf file.
TOP_LEVEL_BLOCKS = {
    "terraform",
    "provider",
    "variable",
    "output",
    "locals",
    "resource",
    "data",
    "module",
    "moved",
    "import",
    "check",
    "removed",
}

RUN_LEVEL_KEYS = {
    "command",
    "variables",
    "providers",
    "assert",
    "expect_failures",
    "module",
    "state_key",
    "parallel",
    "plan_options",
    "destroy",
    "skip",
    "override_path",
    "test",
}


def _files(repo, pattern: str) -> list[Path]:
    return sorted(path for path in repo.root.rglob(pattern) if ".terraform" not in path.parts)


def test_repository_contains_terraform_code(repo):
    assert repo.all_tf_files, "no .tf files found - the repository layout is unexpected"


def test_every_terraform_file_parses(repo):
    failures: dict[str, list[str]] = {}
    for path in _files(repo, "*.tf") + _files(repo, "*.tfvars") + _files(repo, "*.tftest.hcl"):
        try:
            parse(path)
        except HCLParseError as exc:
            failures[str(path.relative_to(repo.root))] = [str(exc)]
    assert_clean(failures, "Terraform files that do not parse:")


@pytest.mark.parametrize("kind", ["modules", "examples"])
def test_top_level_blocks_are_valid(repo, kind):
    base = repo.root / kind
    failures: dict[str, list[str]] = {}
    for path in sorted(base.glob("*/*.tf")):
        config = parse(path)
        unknown = sorted(key for key in config if not key.startswith("__") and key not in TOP_LEVEL_BLOCKS)
        if unknown:
            failures[str(path.relative_to(repo.root))] = [f"unknown top level block(s): {', '.join(unknown)}"]
    assert_clean(failures, f"{kind}/*.tf use unsupported top level blocks:")


def test_test_files_only_use_run_blocks(repo):
    failures: dict[str, list[str]] = {}
    for path in _files(repo, "*.tftest.hcl"):
        config = parse(path)
        for key in config:
            if key.startswith("__"):
                continue
            if key in {"run", "variable", "locals", "provider", "terraform", "mock_provider", "override_resource", "override_data", "override_module"}:
                continue
            failures.setdefault(str(path.relative_to(repo.root)), []).append(f"unexpected top level block {key!r} in a test file")
        for entry in config.get("run", []) or []:
            for run_name, body in entry.items():
                if not isinstance(body, dict):
                    continue
                for key in body:
                    if key.startswith("__"):
                        continue
                    if key not in RUN_LEVEL_KEYS:
                        failures.setdefault(str(path.relative_to(repo.root)), []).append(f"run {run_name!r}: unknown key {key!r}")
    assert_clean(failures, "Native Terraform tests use keys the test framework does not know:")


def test_no_merge_conflict_markers_or_todo_leftovers(repo):
    offenders: dict[str, list[str]] = {}
    pattern = re.compile(r"(<<<<<<<|>>>>>>>{1,2}|FIXME|TODO: (remove|fill|fill in))")
    for path in _files(repo, "*.tf") + _files(repo, "*.tfvars") + _files(repo, "*.tftest.hcl"):
        hits = [f"line {index}: {line.strip()[:90]}" for index, line in enumerate(path.read_text().splitlines(), 1) if pattern.search(line)]
        if hits:
            offenders[str(path.relative_to(repo.root))] = hits
    assert_clean(offenders, "Files contain leftover markers:")
