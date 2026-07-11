#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock="$root/packages/cop-device-contract/contract.lock.json"
destination="$root/packages/cop-device-contract/artifact"
mode="sync"

if [[ "${1:-}" == "--check" ]]; then
  mode="check"
  shift
fi

source_repository="${1:-${COP_REPOSITORY_PATH:-}}"
if [[ -z "$source_repository" ]]; then
  echo "usage: $0 [--check] /path/to/01-COP" >&2
  exit 2
fi

read -r version commit package_path < <(
  python3 - "$lock" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    lock = json.load(handle)
print(lock["contractVersion"], lock["sourceCommit"], lock["sourcePackagePath"])
PY
)

if ! git -C "$source_repository" cat-file -e "$commit^{commit}"; then
  echo "pinned COP commit is unavailable locally: $commit" >&2
  exit 1
fi

temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT

git -C "$source_repository" archive "$commit" \
  "$package_path/schemas" \
  "$package_path/fixtures/v1" | tar -xf - -C "$temporary"

candidate="$temporary/$package_path"

if [[ "$mode" == "check" ]]; then
  diff -ru "$candidate/schemas" "$destination/schemas"
  diff -ru "$candidate/fixtures" "$destination/fixtures"
  echo "COP Device contract $version matches $commit."
  exit 0
fi

mkdir -p "$destination/schemas" "$destination/fixtures"
rsync -a --delete "$candidate/schemas/" "$destination/schemas/"
rsync -a --delete "$candidate/fixtures/" "$destination/fixtures/"
echo "Synchronized COP Device contract $version from $commit."
