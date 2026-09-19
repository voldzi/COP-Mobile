#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ios="$root/apps/ios"

command -v xcodegen >/dev/null || {
  echo "xcodegen is required" >&2
  exit 1
}

(
  cd "$ios"
  xcodegen generate
)

destination="${COP_IOS_SIMULATOR_ID:-}"
if [[ -z "$destination" ]]; then
  destination="$({ xcrun simctl list devices available -j || true; } | python3 -c '
import json, sys
data = json.load(sys.stdin)
candidates = []
for runtime, devices in data.get("devices", {}).items():
    marker = "iOS-"
    if marker not in runtime:
        continue
    version = runtime.split(marker, 1)[1].replace("-", ".")
    try:
        major = int(version.split(".", 1)[0])
    except ValueError:
        continue
    if major < 26:
        continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            candidates.append((runtime, device.get("name", ""), device.get("udid", "")))
if not candidates:
    raise SystemExit("no available iOS 26 or newer iPhone simulator")
# Prefer the oldest supported runtime so the minimum deployment target gets
# exercised whenever it is installed; otherwise use the nearest newer runtime.
print(sorted(candidates)[0][2])
')"
fi

xcodebuild \
  -project "$ios/COPMobile.xcodeproj" \
  -scheme COPMobile \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$destination" \
  -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO \
  test
