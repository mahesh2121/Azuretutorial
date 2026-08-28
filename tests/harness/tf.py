"""Static analysis helpers for the Terraform configuration in this repository.

The tests in ``tests/`` validate every module and example *without* contacting
Azure or the Terraform registry: they parse the HCL into a small AST
(``python-hcl2``) and then assert on structure, the provider contract, naming,
security posture and input/output wiring.

Everything is deliberately dependency-light so the suite also runs in CI
containers that only have Python installed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator

import hcl2

# Terraform meta-arguments: never part of the provider schema.
META_ARGUMENTS = {
    "count",
    "depends_on",
    "for_each",
    "lifecycle",
    "local-exec",
    "provider",
    "provisioner",
    "connection",
    "timeouts",
    "create_before_destroy",
    "prevent_destroy",
    "ignore_changes",
    "replace_triggered_by",
    "precondition",
    "postcondition",
}

BLOCK_MARKERS = ("resource", "data", "module", "variable", "output", "locals", "provider", "terraform", "moved", "import", "check", "removed")


class HCLParseError(AssertionError):
    """Raised when a ``.tf``/``.tfvars``/``.tftest.hcl`` file cannot be parsed."""


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def unquote(value: str) -> str:
    """python-hcl2 keeps block labels (and some literals) as quoted strings."""
    value = str(value)
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def parse(path: Path) -> dict:
    """Parse one Terraform-family file into a dict, raising a readable error."""
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:  # pragma: no cover - filesystem problem
        raise HCLParseError(f"{path}: cannot read file: {exc}") from exc
    try:
        data = hcl2.loads(text)
    except Exception as exc:
        raise HCLParseError(f"{path}: HCL syntax error -> {type(exc).__name__}: {str(exc).splitlines()[0]}") from exc
    if data is None:
        return {}
    if isinstance(data, list):  # pragma: no cover - defensive
        merged: dict = {}
        for item in data:
            merged.update(item)
        return merged
    if not isinstance(data, dict):  # pragma: no cover - defensive
        raise HCLParseError(f"{path}: unexpected parse result {type(data)!r}")
    return data


def parse_tfvars(path: Path) -> dict:
    return parse(path)


def tf_files(directory: Path, pattern: str = "*.tf") -> list[Path]:
    return sorted(p for p in directory.glob(pattern) if p.is_file())


def merge_configs(configs: Iterable[dict]) -> dict:
    """Merge several parsed files into a single config (lists are concatenated)."""
    merged: dict = {}
    for config in configs:
        for key, value in config.items():
            if key == "__comments__":
                continue
            if key in merged and isinstance(merged[key], list) and isinstance(value, list):
                merged[key].extend(value)
            else:
                merged[key] = value
    return merged


def load_directory(directory: Path, patterns: tuple[str, ...] = ("*.tf",)) -> dict:
    configs = [parse(path) for path in _files_for(directory, patterns)]
    return merge_configs(configs)


def _files_for(directory: Path, patterns: Iterable[str]) -> list[Path]:
    files: list[Path] = []
    for pattern in patterns:
        files.extend(path for path in directory.glob(pattern) if path.is_file())
    return sorted(set(files))


# ---------------------------------------------------------------------------
# body walking
# ---------------------------------------------------------------------------


def _is_block_list(value) -> bool:
    if isinstance(value, dict):
        return bool(value.get("__is_block__"))
    if isinstance(value, list):
        return bool(value) and all(isinstance(item, dict) for item in value)
    return False


@dataclass
class Body:
    """A normalised block body: plain arguments separated from nested blocks.

    ``dynamic "x" { content { ... } }`` is folded into ``blocks["x"]`` so that
    callers can validate the schema of a block no matter how it was written.
    """

    arguments: dict = field(default_factory=dict)
    blocks: dict = field(default_factory=dict)
    source: dict = field(default_factory=dict)

    def get(self, name, default=None):
        return self.arguments.get(name, default)

    def has(self, name) -> bool:
        return name in self.arguments

    def block_bodies(self, name: str) -> list[dict]:
        return self.blocks.get(name, [])

    @property
    def expressions(self) -> list[str]:
        return list(collect_strings({"arguments": self.arguments, "blocks": self.blocks}))

    @property
    def all_keys(self) -> set[str]:
        return set(self.arguments) | set(self.blocks)


def normalize_body(body: dict) -> Body:
    result = Body(source=dict(body))
    if not isinstance(body, dict):
        return result
    for key, value in body.items():
        if key in ("__is_block__", "__line_count__", "__dependent_blocks__", "__comments__"):
            continue
        if key == "dynamic":
            for entry in value if isinstance(value, list) else [value]:
                if not isinstance(entry, dict):
                    continue
                for name, content in entry.items():
                    name = unquote(name)
                    content = content if isinstance(content, dict) else {}
                    inner = content.get("content", [])
                    if isinstance(inner, dict):
                        inner = [inner]
                    for item in inner:
                        result.blocks.setdefault(name, []).append(item)
            continue
        if _is_block_list(value):
            items = value if isinstance(value, list) else [value]
            result.blocks.setdefault(key, []).extend([i for i in items if isinstance(i, dict)])
            continue
        result.arguments[key] = value
    return result


def collect_strings(node) -> Iterator[str]:
    """Yield every string leaf of an AST node (i.e. every raw expression)."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for key, value in node.items():
            if key == "__comments__":
                continue
            if isinstance(key, str):
                yield key
            yield from collect_strings(value)
    elif isinstance(node, (list, tuple, set)):
        for item in node:
            yield from collect_strings(item)


# ---------------------------------------------------------------------------
# block iterators
# ---------------------------------------------------------------------------


def _entries(config: dict, block_type: str) -> Iterator[tuple]:
    for entry in config.get(block_type, []) or []:
        if not isinstance(entry, dict):
            continue
        for labels, body in entry.items():
            if labels in ("__is_block__",):
                continue
            yield unquote(labels), body


def iter_resources(config: dict) -> Iterator[tuple[str, str, Body]]:
    """Yield ``(type, name, body)`` for every managed resource."""
    for rtype, by_name in _entries(config, "resource"):
        if isinstance(by_name, dict):
            for rname, body in by_name.items():
                if rname == "__is_block__":
                    continue
                yield rtype, unquote(rname), normalize_body(body if isinstance(body, dict) else {})


def iter_data_sources(config: dict) -> Iterator[tuple[str, str, Body]]:
    for dtype, by_name in _entries(config, "data"):
        if isinstance(by_name, dict):
            for dname, body in by_name.items():
                if dname == "__is_block__":
                    continue
                yield dtype, unquote(dname), normalize_body(body if isinstance(body, dict) else {})


def iter_variables(config: dict) -> Iterator[tuple[str, Body]]:
    for name, body in _entries(config, "variable"):
        yield name, normalize_body(body if isinstance(body, dict) else {})


def iter_outputs(config: dict) -> Iterator[tuple[str, Body]]:
    for name, body in _entries(config, "output"):
        yield name, normalize_body(body if isinstance(body, dict) else {})


def iter_modules(config: dict) -> Iterator[tuple[str, Body]]:
    for name, body in _entries(config, "module"):
        yield name, normalize_body(body if isinstance(body, dict) else {})


def iter_providers(config: dict) -> Iterator[tuple[str, Body]]:
    for name, body in _entries(config, "provider"):
        yield name, normalize_body(body if isinstance(body, dict) else {})


def iter_terraform_blocks(config: dict) -> Iterator[Body]:
    for entry in config.get("terraform", []) or []:
        if isinstance(entry, dict):
            yield normalize_body(entry)


def locals_of(config: dict) -> set[str]:
    names: set[str] = set()
    for entry in config.get("locals", []) or []:
        if isinstance(entry, dict):
            # python-hcl2 injects __comments__/__inline_comments__/__is_block__
            names.update(k for k in entry if not k.startswith("__"))
    return names


# ---------------------------------------------------------------------------
# expression level helpers
# ---------------------------------------------------------------------------

VAR_REF = re.compile(r"\bvar\.([a-zA-Z0-9_-]+)")
LOCAL_REF = re.compile(r"\blocal\.([a-zA-Z0-9_-]+)")
MODULE_REF = re.compile(r"\bmodule\.([a-zA-Z0-9_-]+)")
MODULE_ATTR = re.compile(r"\bmodule\.([a-zA-Z0-9_-]+)\.([a-zA-Z0-9_-]+)")
# resource / data reference with optional index expression, e.g.
#   azurerm_container_registry.this.id
#   azurerm_container_registry_token.this[each.key].id
RESOURCE_REF = re.compile(
    r"(?<![a-zA-Z0-9_.])(?P<kind>azurerm_[a-z0-9_]+)\.(?P<name>[a-zA-Z0-9_-]+)(?P<index>(?:\[[^\]]*\])*)\.(?P<attr>[a-zA-Z0-9_]+)"
)
DATA_REF = re.compile(
    r"\bdata\.(?P<kind>azurerm_[a-z0-9_]+)\.(?P<name>[a-zA-Z0-9_-]+)(?P<index>(?:\[[^\]]*\])*)\.(?P<attr>[a-zA-Z0-9_]+)"
)


def references(expressions: Iterable[str]) -> dict[str, set[str]]:
    """Bucket every identifier found in a set of raw expressions."""
    buckets = {
        "var": set(),
        "local": set(),
        "module": set(),
        "module_attr": set(),
        "resource_attr": set(),
        "data_attr": set(),
    }
    for expression in expressions:
        buckets["var"].update(VAR_REF.findall(expression))
        buckets["local"].update(LOCAL_REF.findall(expression))
        buckets["module_attr"].update(MODULE_ATTR.findall(expression))
        for match in RESOURCE_REF.finditer(expression):
            buckets["resource_attr"].add((match.group("kind"), match.group("name"), match.group("attr")))
        for match in DATA_REF.finditer(expression):
            buckets["data_attr"].add((match.group("kind"), match.group("name"), match.group("attr")))
    return buckets


def is_interpolation(value) -> bool:
    return isinstance(value, str) and value.strip().startswith("${") and value.strip().endswith("}")


def literal_or_expression(value):
    """Best-effort decode of a raw HCL value for assertions in tests."""
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, list):
        return [literal_or_expression(item) for item in value]
    if isinstance(value, dict):
        return {unquote(str(k)): literal_or_expression(v) for k, v in value.items() if not str(k).startswith("__")}
    if isinstance(value, str):
        text = unquote(value)
        if "${" in text:
            return value  # dynamic - callers must treat it as opaque
        return text
    return value


def strip_quotes(value: str) -> str:
    return unquote(value)
