#!/usr/bin/env python3
"""Generate the module/example README tables from the Terraform sources.

Why a generator: ``terraform-docs`` needs a ``terraform`` binary, which the
offline test lane (and many CI images) does not have. This script parses the
same HCL the contract tests parse, so the tables in every README always match
``variables.tf`` / ``outputs.tf``.

Usage:
    python3 tools/gen-docs.py            # rewrite README.md files
    python3 tools/gen-docs.py --check    # exit 1 if they are out of date

Run from the repository root.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from textwrap import shorten

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from harness.tf import parse  # noqa: E402

DOCS_BEGIN = "<!-- BEGIN_TF_DOCS -->"
DOCS_END = "<!-- END_TF_DOCS -->"
WIDTH = 66


class Block(dict):
    """A parsed HCL block: arguments as keys, nested blocks under `blocks`."""

    def __init__(self, raw: dict):
        super().__init__()
        self.arguments: dict[str, str] = {}
        self.blocks: dict[str, list] = {}
        for key, value in raw.items():
            if key.startswith("__"):
                continue
            if isinstance(value, list) and value and isinstance(value[0], dict) and value[0].get("__is_block__"):
                self.blocks[key] = value
            else:
                self.arguments[key] = value

    def get(self, key: str, default=None):
        return self.arguments.get(key, default)

    def has(self, key: str) -> bool:
        return key in self.arguments


def load(path: Path) -> tuple[dict[str, Block], dict[str, Block]]:
    """Return (variables, outputs) for a directory."""
    variables: dict[str, Block] = {}
    outputs: dict[str, Block] = {}
    for file in sorted(path.glob("*.tf")):
        config = parse(file)
        for entry in config.get("variable", []) or []:
            for name, body in entry.items():
                variables[name.strip('"')] = Block(body if isinstance(body, dict) else {})
        for entry in config.get("output", []) or []:
            for name, body in entry.items():
                outputs[name.strip('"')] = Block(body if isinstance(body, dict) else {})
    return variables, outputs


HEREDOC = re.compile(r"^<<-?\s*([A-Za-z0-9_]+)\s*(.*)", re.S)


def clean(value, limit: int = 150) -> str:
    """Render a raw HCL expression as a single markdown table cell."""
    if value is None:
        return "-"
    text = str(value).strip()
    # python-hcl2 keeps the quotes of a literal string and wraps non literal
    # expressions in `${ ... }`; a heredoc survives as quoted text.
    text = re.sub(r'^"|"$', "", text)
    if text.startswith("${") and text.endswith("}"):
        text = text[2:-1].strip()
    heredoc = HEREDOC.match(text.strip())
    if heredoc:
        body = re.sub(rf"\n\s*{heredoc.group(1)}\s*$", "", heredoc.group(2), flags=re.S)
        text = " ".join(part.strip() for part in body.splitlines() if part.strip())
    text = re.sub(r"\s+", " ", text).replace('\n', " ").strip()
    text = text.replace("|", "\\|")
    if len(text) > limit:
        return text[: limit - 1].rstrip() + "…"
    return text or "-"


def table(headers: list[str], rows: list[list[str]]) -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(row) + " |" for row in rows]
    return "\n".join(out)


def module_docs(path: Path) -> str:
    variables, outputs = load(path)
    lines = [DOCS_BEGIN, "", "## Inputs", ""]
    rows = []
    for name in sorted(variables):
        body = variables[name]
        required = "yes" if not body.has("default") else "no"
        rows.append([f"`{name}`", clean(body.get("description")), clean(body.get("type")), clean(body.get("default"), 60), required])
    lines.append(table(["Name", "Description", "Type", "Default", "Required"], rows))
    lines += ["", "## Outputs", ""]
    rows = []
    for name in sorted(outputs):
        body = outputs[name]
        rows.append([f"`{name}`", clean(body.get("description")), "yes" if body.get("sensitive") is True else "no"])
    lines.append(table(["Name", "Description", "Sensitive"], rows))
    lines.append(DOCS_END)
    return "\n".join(lines)


def example_docs(path: Path) -> str:
    variables, outputs = load(path)
    lines = [DOCS_BEGIN, "", "## Variables you can set", ""]
    rows = []
    for name in sorted(variables):
        body = variables[name]
        rows.append([f"`{name}`", clean(body.get("description")), clean(body.get("default"), 60), "yes" if not body.has("default") else "no"])
    lines.append(table(["Name", "Description", "Default", "Required"], rows))
    lines += ["", "## Outputs", ""]
    rows = [[f"`{name}`", clean(body.get("description"))] for name, body in sorted(outputs.items())]
    lines.append(table(["Name", "Description"], rows))
    lines.append(DOCS_END)
    return "\n".join(lines)


def render(directory: Path, kind: str) -> str:
    return module_docs(directory) if kind == "module" else example_docs(directory)


def apply_docs(text: str, generated: str) -> str:
    """Return `text` with the generated block spliced in between the markers."""
    if DOCS_BEGIN in text and DOCS_END in text:
        head, rest = text.split(DOCS_BEGIN, 1)
        # everything after the closing marker is hand written and stays put
        tail = rest.split(DOCS_END, 1)[1]
        new = head + generated + tail
    elif text.strip():
        new = text.rstrip() + "\n\n" + generated + "\n"
    else:
        new = generated + "\n"
    if not new.endswith("\n"):
        new += "\n"
    return new


def splice(readme: Path, generated: str) -> bool:
    text = readme.read_text() if readme.exists() else ""
    new = apply_docs(text, generated)
    if new == text:
        return False
    readme.write_text(new)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if any README is out of date")
    args = parser.parse_args()

    targets = [(path, "module") for path in sorted((ROOT / "modules").glob("*")) if path.is_dir()]
    targets += [(path, "example") for path in sorted((ROOT / "examples").glob("*")) if path.is_dir()]

    changed = []
    for directory, kind in targets:
        generated = render(directory, kind)
        readme = directory / "README.md"
        text = readme.read_text() if readme.exists() else ""
        if args.check:
            if apply_docs(text, generated) != text:
                changed.append(str(readme.relative_to(ROOT)))
        elif splice(readme, generated):
            changed.append(str(readme.relative_to(ROOT)))

    if args.check:
        if changed:
            print("README tables are stale, run: python3 tools/gen-docs.py")
            for name in changed:
                print(f"  {name}")
            return 1
        print("README tables are up to date.")
        return 0

    print(f"updated {len(changed)} README file(s)")
    for name in changed:
        print(f"  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
