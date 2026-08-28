"""Gate 10 - documentation must match code.

Undocumented modules get bypassed; documentation that drifted from the code is
worse than none. These tests assert that every input and output of every module
appears in its README, that the root README points at what exists, and that the
tooling files (Makefile, CI, .gitignore) cover the repository.
"""

from __future__ import annotations

import re
import tempfile
from pathlib import Path

from conftest import assert_clean  # noqa: F401

from harness.tf import HCLParseError, parse


def test_module_readmes_exist_and_document_every_input_and_output(repo):
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        readme = module.path / "README.md"
        if not readme.exists():
            failures.setdefault(f"modules/{name}", []).append("missing README.md")
            continue
        text = readme.read_text()
        for variable in module.variables:
            if not re.search(rf"[`\"]{re.escape(variable)}[`\"]", text):
                failures.setdefault(f"modules/{name}", []).append(f"README does not document variable {variable!r}")
        for output in module.outputs:
            if not re.search(rf"[`\"]{re.escape(output)}[`\"]", text):
                failures.setdefault(f"modules/{name}", []).append(f"README does not document output {output!r}")
    assert_clean(failures, "Module documentation:")


def test_module_readmes_cover_the_required_sections(repo):
    required = ["Inputs", "Outputs", "Guardrails", "Example"]
    failures: dict[str, list[str]] = {}
    for name, module in repo.modules.items():
        readme = module.path / "README.md"
        if not readme.exists():
            continue
        text = readme.read_text().lower()
        missing = [section for section in required if section.lower() not in text]
        if missing:
            failures.setdefault(f"modules/{name}/README.md", []).append(f"missing section(s): {', '.join(missing)}")
    assert_clean(failures, "Each module README needs Inputs / Outputs / Guardrails / Example:")


def test_example_readmes_exist(repo):
    failures: dict[str, list[str]] = {}
    for name, example in repo.examples.items():
        readme = example.path / "README.md"
        if not readme.exists():
            failures.setdefault(f"examples/{name}", []).append("missing README.md")
            continue
        text = readme.read_text()
        if "terraform plan" not in text or "terraform apply" not in text:
            failures.setdefault(f"examples/{name}/README.md", []).append("must show the plan/apply commands to run it")
    assert_clean(failures, "Examples need a README with run instructions:")


def test_root_readme_lists_every_module_and_example(repo):
    readme = repo.root / "README.md"
    assert readme.exists(), "root README.md is missing"
    text = readme.read_text()
    failures: dict[str, list[str]] = {}
    for name in repo.modules:
        if f"modules/{name}" not in text:
            failures.setdefault("README.md", []).append(f"modules/{name} is not linked")
    for name in repo.examples:
        if f"examples/{name}" not in text:
            failures.setdefault("README.md", []).append(f"examples/{name} is not linked")
    assert_clean(failures, "The root README must index the repository:")


def test_repository_tooling_is_present(repo):
    failures: dict[str, list[str]] = {}
    for name in [".gitignore", "Makefile", "tests/README.md", "tests/requirements.txt", "tests/run_all.sh"]:
        if not (repo.root / name).exists():
            failures.setdefault("tooling", []).append(f"{name} is missing")
    workflows = list((repo.root / ".github" / "workflows").glob("*.yml")) if (repo.root / ".github" / "workflows").is_dir() else []
    if not workflows:
        failures.setdefault("tooling", []).append(".github/workflows/*.yml is missing")
    else:
        text = "\n".join(path.read_text() for path in workflows)
        for step in ("terraform fmt", "terraform init", "pytest", "terraform validate"):
            if step not in text:
                failures.setdefault(".github/workflows", []).append(f"CI does not run `{step}`")
    makefile = repo.root / "Makefile"
    if makefile.exists():
        targets = set(re.findall(r"^([a-zA-Z0-9_-]+):", makefile.read_text(), flags=re.M))
        for target in ("fmt", "validate", "test", "test-terraform"):
            if target not in targets:
                failures.setdefault("Makefile", []).append(f"target {target!r} is missing")
    assert_clean(failures, "Repository tooling:")


def test_tests_are_self_documenting(repo):
    """Every gate should say why it exists."""
    failures: dict[str, list[str]] = {}
    for path in sorted((repo.root / "tests").glob("test_*.py")):
        text = path.read_text()
        match = re.match(r'^"""(.*?)"""', text, flags=re.S)
        if not match or len(match.group(1).strip()) < 80:
            failures.setdefault(str(path.relative_to(repo.root)), []).append("module docstring must explain what the gate protects")
    assert_clean(failures, "Test files need a purpose docstring:")


HCL_FENCE = re.compile(r"```hcl\n(.*?)```", re.S)


def test_every_hcl_snippet_in_the_docs_parses(repo):
    """Documentation that does not parse is documentation nobody can copy."""
    failures: dict[str, list[str]] = {}
    for readme in sorted(repo.root.rglob("*.md")):
        if ".git" in readme.parts or "Secound" in readme.parts:
            continue
        for index, block in enumerate(HCL_FENCE.findall(readme.read_text()), 1):
            # snippets with an elision are illustrative, not runnable
            if "…" in block or "..." in block:
                continue
            try:
                parse_text(block)
            except HCLParseError as exc:
                failures.setdefault(str(readme.relative_to(repo.root)), []).append(f"hcl snippet #{index} does not parse: {exc}")
    assert_clean(failures, "Fix the fenced HCL in these READMEs:")


def parse_text(text: str) -> dict:
    """Parse an HCL snippet without touching the filesystem."""
    import tempfile

    with tempfile.NamedTemporaryFile("w", suffix=".tf", delete=True) as handle:
        handle.write(text)
        handle.flush()
        from pathlib import Path as _Path

        return parse(_Path(handle.name))
