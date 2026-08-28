"""Gate 2 - house style.

`terraform fmt` is the authority for alignment; these checks cover the things
fmt does *not* police (tabs, trailing spaces, indentation width, file
termination) and assert the repository's comment-banner convention so new
modules look like the existing ones.
"""

from __future__ import annotations

import re
from pathlib import Path

from conftest import assert_clean  # noqa: F401

MAX_LINE_LENGTH = 200
ALLOW_LONG_LINE = re.compile(r"(error_message|description|^\s*#)")

# ``Secound/`` is a pre-existing stack in this repository; the style gates below
# govern the module/example code and do not reformat unrelated history.
EXCLUDED = {".git", ".terraform", "fixtures"}


def _in_scope(path: Path, root: Path) -> bool:
    parts = path.relative_to(root).parts
    return not (EXCLUDED & set(parts)) and "Secound" not in parts


def _all_repo_files(repo) -> list[Path]:
    interesting = ("*.tf", "*.tfvars", "*.tftest.hcl", "*.md", "*.yml", "*.sh", "*.py")
    files: list[Path] = []
    for pattern in interesting:
        files.extend(path for path in repo.root.rglob(pattern) if _in_scope(path, repo.root))
    return sorted(set(files))


def test_no_tabs_in_terraform_files(repo):
    offenders: dict[str, list[str]] = {}
    for path in _all_repo_files(repo):
        for index, line in enumerate(path.read_text().splitlines(), 1):
            if "\t" in line and not line.lstrip().startswith("#"):
                offenders.setdefault(str(path.relative_to(repo.root)), []).append(f"line {index}: tab character")
    assert_clean(offenders, "Terraform files must indent with spaces:")


def test_no_trailing_whitespace(repo):
    offenders: dict[str, list[str]] = {}
    for path in _all_repo_files(repo):
        if path.suffix == ".md":
            continue  # markdown uses trailing double spaces for line breaks
        for index, line in enumerate(path.read_text().splitlines(), 1):
            if line.rstrip() != line:
                offenders.setdefault(str(path.relative_to(repo.root)), []).append(f"line {index}: trailing whitespace")
    assert_clean(offenders, "Remove trailing whitespace:")


def test_files_end_with_single_newline(repo):
    offenders: dict[str, list[str]] = {}
    for path in _all_repo_files(repo):
        text = path.read_text()
        if not text:
            offenders[str(path.relative_to(repo.root))] = ["file is empty"]
        elif not text.endswith("\n") or text.endswith("\n\n"):
            offenders[str(path.relative_to(repo.root))] = ["file must end with exactly one newline"]
    assert_clean(offenders, "Fix end-of-file newlines:")


def test_terraform_indentation_is_two_spaces(repo):
    offenders: dict[str, list[str]] = {}
    for path in _files(repo):
        for index, line in enumerate(path.read_text().splitlines(), 1):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            if indent % 2:
                offenders.setdefault(str(path.relative_to(repo.root)), []).append(f"line {index}: indent {indent} is not a multiple of 2")
    assert_clean(offenders, "Indent Terraform with two spaces per level:")


def _files(repo) -> list[Path]:
    return sorted(
        path
        for path in list(repo.root.rglob("*.tf")) + list(repo.root.rglob("*.tftest.hcl"))
        if _in_scope(path, repo.root)
    )


def test_terraform_lines_stay_readable(repo):
    offenders: dict[str, list[str]] = {}
    for path in _files(repo):
        for index, line in enumerate(path.read_text().splitlines(), 1):
            if len(line) > MAX_LINE_LENGTH and not ALLOW_LONG_LINE.search(line):
                offenders.setdefault(str(path.relative_to(repo.root)), []).append(f"line {index}: {len(line)} chars")
    assert_clean(offenders, f"Keep Terraform lines under {MAX_LINE_LENGTH} characters (comments and long messages excepted):")


def test_modules_and_examples_have_block_comment_headers(repo):
    """The repository style opens each file with a ╔═╗ banner - new code should match."""
    offenders: dict[str, list[str]] = {}
    for directory in list(repo.modules.values()) + list(repo.examples.values()):
        for path in sorted(directory.path.glob("*.tf")):
            first = path.read_text().splitlines()[0] if path.read_text().splitlines() else ""
            if not first.startswith("#"):
                offenders.setdefault(str(path.relative_to(repo.root)), []).append("first line should be a # banner comment")
    assert_clean(offenders, "Follow the banner-comment file header convention:")
