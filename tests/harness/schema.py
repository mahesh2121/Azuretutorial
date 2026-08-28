"""Provider contract checks driven by ``tests/schemas/azurerm_<version>.json``.

The JSON file mirrors the *documented* argument reference of the pinned
``hashicorp/azurerm`` provider.  The tests use it to reject typos, removed
arguments and deprecated blocks before they ever reach an Azure subscription.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .tf import META_ARGUMENTS, Body, normalize_body

SCHEMA_DIR = "tests/schemas"


@dataclass
class ProviderSchema:
    """A curated snapshot of provider resource schemas."""

    provider: str
    version: str
    resources: dict
    data_sources: dict
    path: Path

    # ---- lookups ---------------------------------------------------------
    def knows(self, resource_type: str) -> bool:
        return resource_type in self.resources

    def unknown_types(self, resource_types) -> set[str]:
        return {name for name in resource_types if name not in self.resources}

    def _allowed(self, spec: dict) -> set[str]:
        return set(spec.get("arguments", [])) | set(spec.get("blocks", {}))

    def arguments(self, resource_type: str) -> set[str]:
        return set(self.resources.get(resource_type, {}).get("arguments", []))

    def readable(self, resource_type: str) -> set[str]:
        spec = self.resources.get(resource_type, {})
        return set(spec.get("arguments", [])) | set(spec.get("exported", [])) | set(spec.get("blocks", {})) | {"id"}

    def required(self, resource_type: str) -> list[str]:
        return list(self.resources.get(resource_type, {}).get("required", []))

    def deprecated(self, resource_type: str) -> set[str]:
        return set(self.resources.get(resource_type, {}).get("deprecated", []))

    # ---- validation ------------------------------------------------------
    def validate_resource(self, resource_type: str, body: Body) -> list[str]:
        """Return human readable findings for one resource block."""
        if not self.knows(resource_type):
            return [f"resource type {resource_type!r} is not in the provider contract"]
        spec = self.resources[resource_type]
        findings: list[str] = []
        _walk_body(body, spec, self._allowed(spec), f"{resource_type}", spec.get("blocks", {}), findings)

        missing = [name for name in self.required(resource_type) if name not in body.all_keys]
        if missing:
            findings.append(f"missing required argument(s): {', '.join(sorted(missing))}")

        used_deprecated = sorted(name for name in body.all_keys if name in self.deprecated(resource_type))
        if used_deprecated:
            findings.append(f"deprecated argument(s) in use: {', '.join(used_deprecated)}")
        return findings

    def validate_data_source(self, data_type: str, body: Body) -> list[str]:
        if data_type not in self.data_sources:
            return [f"data source {data_type!r} is not in the provider contract"]
        spec = self.data_sources[data_type]
        allowed = set(spec.get("arguments", []))
        findings = [f"unknown argument {key!r}" for key in body.arguments if key not in allowed and key not in META_ARGUMENTS]
        return findings

    def validate_deprecated(self, resource_type: str, body: Body) -> list[str]:
        """Focused check: a single resource must not use deprecated arguments."""
        if not self.knows(resource_type):
            return []
        used = sorted(name for name in body.all_keys if name in self.deprecated(resource_type))
        return [f"{name!r} is deprecated on {resource_type} - migrate to the replacement before azurerm 4.x" for name in used]

    def validate_attribute_reference(self, resource_type: str, attribute: str) -> bool:
        if not self.knows(resource_type):
            return True  # covered by unknown_types()
        return attribute in self.readable(resource_type)


def _walk_body(body: dict | Body, spec_owner, allowed: set[str], path: str, block_map: dict, findings: list[str]) -> None:
    arguments = body.arguments if isinstance(body, Body) else dict(body)
    blocks = body.blocks if isinstance(body, Body) else {}

    for key in arguments:
        if key in META_ARGUMENTS:
            continue
        if key not in allowed:
            findings.append(f"{path}: {key!r} is not a documented argument")

    for name, inner in blocks.items():
        if name in META_ARGUMENTS:
            continue
        if name not in allowed:
            findings.append(f"{path}: {name!r} is not a documented block")
            continue
        child_allowed = set(block_map.get(name, []))
        for index, child in enumerate(inner):
            _walk_body(
                normalize_body(child),
                spec_owner,
                child_allowed,
                f"{path}.{name}[{index}]",
                block_map,
                findings,
            )


def load_provider_schema(root: Path, version_glob: str = "azurerm_*.json") -> ProviderSchema:
    candidates = sorted((root / SCHEMA_DIR).glob(version_glob))
    if not candidates:  # pragma: no cover - repo always ships the contract
        raise FileNotFoundError(f"no provider contract found in {root / SCHEMA_DIR}")
    path = candidates[-1]
    payload = json.loads(path.read_text(encoding="utf-8"))
    meta = payload.get("_meta", {})
    return ProviderSchema(
        provider=meta.get("provider", "hashicorp/azurerm"),
        version=meta.get("provider_version", "unknown"),
        resources=payload.get("resources", {}),
        data_sources=payload.get("data_sources", {}),
        path=path,
    )
