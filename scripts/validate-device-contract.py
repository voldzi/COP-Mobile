#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "packages" / "cop-device-contract"
LOCK = PACKAGE / "contract.lock.json"
ARTIFACT = PACKAGE / "artifact"


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read valid JSON from {path.relative_to(ROOT)}: {error}") from error


def main() -> int:
    failures: list[str] = []
    try:
        lock = read_json(LOCK)
        manifest_path = ARTIFACT / "fixtures" / "v1" / "manifest.json"
        manifest = read_json(manifest_path)
    except ValueError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1

    version = lock.get("contractVersion")
    commit = lock.get("sourceCommit")
    if version != "1.0.0":
        failures.append(f"contract version must remain pinned to 1.0.0, got {version!r}")
    if manifest.get("contractVersion") != version:
        failures.append("fixture manifest version does not match contract.lock.json")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        failures.append("sourceCommit must be a full lowercase Git commit SHA")

    cases = manifest.get("cases")
    if not isinstance(cases, list) or not cases:
        failures.append("fixture manifest must contain cases")
        cases = []

    listed_files: set[Path] = set()
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            failures.append(f"fixture case {index} is not an object")
            continue
        fixture = ARTIFACT / "fixtures" / "v1" / str(case.get("file", ""))
        schema = ARTIFACT / "schemas" / str(case.get("schema", ""))
        listed_files.add(fixture)
        if not fixture.is_file():
            failures.append(f"fixture is missing: {fixture.relative_to(ROOT)}")
        if not schema.is_file():
            failures.append(f"schema is missing: {schema.relative_to(ROOT)}")
        if not isinstance(case.get("valid"), bool):
            failures.append(f"fixture case {index} has no boolean valid expectation")

    fixture_root = ARTIFACT / "fixtures" / "v1"
    actual_files = {path for path in fixture_root.rglob("*.json") if path.name != "manifest.json"}
    for unlisted in sorted(actual_files - listed_files):
        failures.append(f"fixture is not listed in manifest: {unlisted.relative_to(ROOT)}")

    for schema_path in sorted((ARTIFACT / "schemas").glob("*.schema.json")):
        try:
            schema = read_json(schema_path)
        except ValueError as error:
            failures.append(str(error))
            continue
        if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
            failures.append(f"schema does not use draft 2020-12: {schema_path.relative_to(ROOT)}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(f"COP Device contract {version} is internally consistent ({len(cases)} fixtures).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
