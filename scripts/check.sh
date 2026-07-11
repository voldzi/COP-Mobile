#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

bash scripts/validate-skeleton.sh
python3 scripts/validate-device-contract.py
python3 scripts/validate-ios-project.py
bash scripts/test-ios.sh
git diff --check
