#!/usr/bin/env python3
import plistlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "apps" / "ios"


def read_plist(name: str):
    with (IOS / "Config" / name).open("rb") as handle:
        return plistlib.load(handle)


def main() -> int:
    failures: list[str] = []
    project = (IOS / "project.yml").read_text(encoding="utf-8")
    base = (IOS / "Config" / "Base.xcconfig").read_text(encoding="utf-8")
    debug = read_plist("Info-Debug.plist")
    staging = read_plist("Info-Staging.plist")
    release = read_plist("Info-Release.plist")

    if project.count('iOS: "26.0"') != 1 or project.count('deploymentTarget: "26.0"') != 2:
        failures.append("project.yml must pin project and both targets to iOS 26.0")
    if "IPHONEOS_DEPLOYMENT_TARGET = 26.0" not in base:
        failures.append("Base.xcconfig must pin IPHONEOS_DEPLOYMENT_TARGET to 26.0")
    if "SWIFT_VERSION = 6.0" not in base:
        failures.append("Base.xcconfig must pin Swift 6.0")

    if release.get("COPWebOrigin") != "https://cop.zeleznalady.cz":
        failures.append("release COP origin must be exact production HTTPS origin")
    if release.get("COPOIDCOrigin") != "https://login.zeleznalady.cz":
        failures.append("release OIDC origin must be exact login HTTPS origin")
    if set(release.get("WKAppBoundDomains", [])) != {"cop.zeleznalady.cz", "login.zeleznalady.cz"}:
        failures.append("release App-Bound Domains must contain only COP and login hosts")
    if "NSAppTransportSecurity" in release:
        failures.append("release Info.plist must not contain ATS exceptions")
    if debug.get("COPAdditionalDebugBridgeOrigins") != ["http://localhost:4311"]:
        failures.append("debug bridge origin must be the explicit local COP port")
    if staging.get("COPWebOrigin") or staging.get("COPOIDCOrigin"):
        failures.append("staging must remain fail-closed until OQ-001 supplies exact origins")

    forbidden_keys = {"NSLocationAlwaysUsageDescription", "UIBackgroundModes"}
    for name, plist in (("debug", debug), ("staging", staging), ("release", release)):
        present = forbidden_keys.intersection(plist)
        if present:
            failures.append(f"{name} enables out-of-scope phase 2 capabilities: {sorted(present)}")

    if list(IOS.rglob("*.entitlements")):
        failures.append("phase 2 feasibility host must not add entitlements")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print("iOS project configuration is fail-closed and pinned to iOS 26.0 / Swift 6.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
