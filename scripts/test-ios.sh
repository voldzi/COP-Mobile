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
    if "iOS-26" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device.get("name", ""):
            candidates.append((runtime, device.get("name", ""), device.get("udid", "")))
if not candidates:
    raise SystemExit("no available iOS 26 iPhone simulator")
print(sorted(candidates, reverse=True)[0][2])
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
