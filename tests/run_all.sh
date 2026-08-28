#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  run_all.sh                                                        ║
# ╠══════════════════════════════════════════════════════════════════╣
# ║  One entry point for both test lanes. Safe to run in CI and on a  ║
# ║  laptop without terraform installed.                               ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON="${PYTHON:-python3}"
TERRAFORM="${TERRAFORM:-terraform}"

banner() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

failures=0
run() {
  local label="$1"
  shift
  banner "$label"
  if "$@"; then
    printf 'PASS  %s\n' "$label"
  else
    printf 'FAIL  %s\n' "$label"
    failures=$((failures + 1))
  fi
}

# --------------------------------------------------------------------------
# Lane 1: offline contract tests. No credentials, no provider download.
# --------------------------------------------------------------------------
if ! "$PYTHON" -c 'import hcl2, pytest' >/dev/null 2>&1; then
  echo "missing python deps - run:  $PYTHON -m pip install -r tests/requirements.txt" >&2
  exit 3
fi

run "terraform parse + style gates" "$PYTHON" -m pytest tests -c tests/pytest.ini -q

# --------------------------------------------------------------------------
# Lane 2: terraform itself, when it is installed.
# --------------------------------------------------------------------------
if command -v "$TERRAFORM" >/dev/null 2>&1; then
  run "terraform fmt" "$TERRAFORM" fmt -recursive -check -diff .

  for dir in modules/* examples/*; do
    [ -f "$dir"/main.tf ] || continue
    (
      cd "$dir"
      "$TERRAFORM" init -input=false -backend=false >/dev/null
      "$TERRAFORM" validate
    ) && printf 'PASS  validate %s\n' "$dir" || {
      printf 'FAIL  validate %s\n' "$dir"
      failures=$((failures + 1))
    }
  done

  for module in modules/*; do
    [ -d "$module/tests" ] || continue
    (
      cd "$module"
      "$TERRAFORM" init -input=false -backend=false >/dev/null
      "$TERRAFORM" test
    ) && printf 'PASS  terraform test %s\n' "$module" || {
      printf 'FAIL  terraform test %s\n' "$module"
      failures=$((failures + 1))
    }
  done
else
  banner "terraform not installed - skipping fmt/validate/terraform-test"
  echo "       those steps run in CI (.github/workflows/terraform.yml)"
fi

# --------------------------------------------------------------------------
# Lane 3: documentation drift.
# --------------------------------------------------------------------------
run "README tables up to date" "$PYTHON" tools/gen-docs.py --check

banner "summary"
if [ "$failures" -eq 0 ]; then
  echo "all lanes green"
else
  echo "$failures lane(s) failed"
  exit 1
fi
