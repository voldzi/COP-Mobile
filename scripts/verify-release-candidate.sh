#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "FAIL: Release candidate musí vzniknout z čisté, commitnuté pracovní kopie." >&2
  exit 1
fi

bash scripts/check.sh
git diff --check

echo "Release candidate preflight passed: kontrola konfigurace, testů a čistoty pracovní kopie je úspěšná."
