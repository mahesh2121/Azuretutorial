"""Shared fixtures for the repository contract tests.

Run them with:

    python -m pytest tests -q            # from the repository root
    make test                            # same thing via the Makefile
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

TESTS_DIR = Path(__file__).resolve().parent
ROOT = TESTS_DIR.parent
if str(TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(TESTS_DIR))

from harness import discover_repo, load_provider_schema  # noqa: E402


@pytest.fixture(scope="session")
def root() -> Path:
    return ROOT


@pytest.fixture(scope="session")
def repo():
    return discover_repo(ROOT)


@pytest.fixture(scope="session")
def schema():
    return load_provider_schema(ROOT)


@pytest.fixture(scope="session")
def module_dirs(repo) -> dict:
    assert repo.modules, "no modules found under modules/ - did the repository move?"
    return repo.modules


@pytest.fixture(scope="session")
def example_dirs(repo) -> dict:
    assert repo.examples, "no examples found under examples/ - did the repository move?"
    return repo.examples


@pytest.fixture(scope="session")
def owned_dirs(repo) -> dict:
    """Modules and examples together, keyed by their repository-relative path."""
    out = {f"modules/{name}": item for name, item in repo.modules.items()}
    out.update({f"examples/{name}": item for name, item in repo.examples.items()})
    return out


@pytest.fixture(scope="session")
def all_configs(repo) -> dict:
    """Every Terraform directory in the repo (modules, examples, root stacks)."""
    merged: dict = {}
    merged.update({f"modules/{name}": item for name, item in repo.modules.items()})
    merged.update({f"examples/{name}": item for name, item in repo.examples.items()})
    merged.update({name: item for name, item in repo.root_configs.items()})
    return merged


@pytest.fixture(scope="session")
def terraform_files(repo) -> list[Path]:
    files = list(repo.all_tf_files)
    files += repo.all_tfvars_files
    files += repo.all_test_files
    return sorted(set(files))


def assert_clean(findings: dict[str, list[str]], context: str) -> None:
    """Fail once with every finding, so a run reports all problems."""
    broken = {key: value for key, value in findings.items() if value}
    assert not broken, f"{context}\n\n" + "\n".join(
        f"  {key}:\n" + "\n".join(f"    - {item}" for item in items) for key, items in sorted(broken.items())
    )
