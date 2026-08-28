"""Repository model: modules, examples and their parsed Terraform config."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .tf import (
    Body,
    iter_data_sources,
    iter_modules,
    iter_outputs,
    iter_providers,
    iter_resources,
    iter_terraform_blocks,
    iter_variables,
    locals_of,
    normalize_body,
    parse,
    references,
    tf_files,
)

CONFIG_PATTERNS = ("*.tf",)
TEST_PATTERNS = ("*.tftest.hcl",)


def _all_expressions(paths) -> list[str]:
    expressions: list[str] = []
    for path in paths:
        config = parse(path)
        expressions.extend(str(item) for item in _walk_strings(config))
    return expressions


def _walk_strings(node):
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for key, value in node.items():
            if key == "__comments__":
                continue
            yield key
            yield from _walk_strings(value)
    elif isinstance(node, (list, tuple, set)):
        for item in node:
            yield from _walk_strings(item)


@dataclass
class TfDirectory:
    """A directory holding Terraform configuration, parsed once."""

    path: Path
    kind: str
    config: dict = field(default_factory=dict)

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def relative_path(self) -> str:
        return self.path.name

    @property
    def tf_files(self) -> list[Path]:
        return tf_files(self.path, "*.tf")

    @property
    def test_files(self) -> list[Path]:
        return sorted(self.path.glob("tests/**/*.tftest.hcl"))

    @property
    def tfvars_files(self) -> list[Path]:
        return sorted(self.path.glob("environments/*.tfvars"))

    @property
    def variables(self) -> dict[str, Body]:
        return dict(iter_variables(self.config))

    @property
    def outputs(self) -> dict[str, Body]:
        return dict(iter_outputs(self.config))

    @property
    def resources(self) -> dict[tuple[str, str], Body]:
        return {(rtype, rname): body for rtype, rname, body in iter_resources(self.config)}

    @property
    def data_sources(self) -> dict[tuple[str, str], Body]:
        return {(dtype, dname): body for dtype, dname, body in iter_data_sources(self.config)}

    @property
    def modules(self) -> dict[str, Body]:
        return dict(iter_modules(self.config))

    @property
    def providers(self) -> dict[str, Body]:
        return dict(iter_providers(self.config))

    @property
    def terraform_blocks(self) -> list[Body]:
        return list(iter_terraform_blocks(self.config))

    @property
    def locals(self) -> set[str]:
        return locals_of(self.config)

    @property
    def resource_types(self) -> set[str]:
        return {rtype for rtype, _ in self.resources}

    @property
    def expressions(self) -> list[str]:
        return _all_expressions(self.tf_files)

    @property
    def refs(self) -> dict[str, set]:
        return references(self.expressions)


@dataclass
class Module(TfDirectory):
    """A reusable module in ``modules/<name>``."""

    @property
    def relative_path(self) -> str:
        return f"modules/{self.name}"

    @property
    def required_variables(self) -> set[str]:
        """Variables without a default are required by callers."""
        return {name for name, body in self.variables.items() if not body.has("default")}

    @property
    def variable_defaults(self) -> dict[str, object]:
        return {name: body.get("default") for name, body in self.variables.items() if body.has("default")}


@dataclass
class Example(TfDirectory):
    """A runnable example in ``examples/<name>``."""

    @property
    def relative_path(self) -> str:
        return f"examples/{self.name}"

    @property
    def module_calls(self) -> dict[str, tuple[str, Body]]:
        """``{module_name: (source_path, body)}`` for every module block."""
        calls: dict[str, tuple[str, Body]] = {}
        for name, body in self.modules.items():
            source = body.get("source")
            if isinstance(source, str):
                source = source.strip('"')
            calls[name] = (str(source), body)
        return calls


@dataclass
class Repo:
    root: Path
    modules: dict[str, Module] = field(default_factory=dict)
    examples: dict[str, Example] = field(default_factory=dict)
    root_configs: dict[str, TfDirectory] = field(default_factory=dict)

    @property
    def all_tf_files(self) -> list[Path]:
        return sorted(
            path
            for path in self.root.rglob("*.tf")
            if ".terraform" not in path.parts and "node_modules" not in path.parts
        )

    @property
    def all_test_files(self) -> list[Path]:
        return sorted(path for path in self.root.rglob("*.tftest.hcl") if ".terraform" not in path.parts)

    @property
    def all_tfvars_files(self) -> list[Path]:
        return sorted(path for path in self.root.rglob("*.tfvars") if ".terraform" not in path.parts)


def discover_repo(root: Path | None = None) -> Repo:
    root = Path(root) if root else Path(__file__).resolve().parents[2]
    repo = Repo(root=root)

    modules_dir = root / "modules"
    if modules_dir.is_dir():
        for child in sorted(p for p in modules_dir.iterdir() if p.is_dir()):
            if list(child.glob("*.tf")):
                repo.modules[child.name] = Module(path=child, kind="module", config=_load(child))

    examples_dir = root / "examples"
    if examples_dir.is_dir():
        for child in sorted(p for p in examples_dir.iterdir() if p.is_dir()):
            if list(child.glob("*.tf")):
                repo.examples[child.name] = Example(path=child, kind="example", config=_load(child))

    # Any other root module in the repository (e.g. an existing hand-written stack).
    for child in sorted(p for p in root.iterdir() if p.is_dir() and p.name not in {"modules", "examples", "tests", "docs"}):
        hidden = child.name.startswith(".")
        if hidden or child.name in {"modules", "examples"}:
            continue
        if list(child.glob("*.tf")):
            repo.root_configs[child.name] = TfDirectory(path=child, kind="root", config=_load(child))

    return repo


def _load(directory: Path) -> dict:
    from .tf import merge_configs

    return merge_configs(parse(path) for path in tf_files(directory, "*.tf"))
