#!/usr/bin/env python3
import json
import plistlib
import struct
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
    if "PRODUCT_BUNDLE_IDENTIFIER = cz.zeleznalady.csm.messenger" not in base:
        failures.append("Base.xcconfig must use the approved legacy bundle ID")
    if "DEVELOPMENT_TEAM: LM6W548X36" not in project:
        failures.append("project.yml must use the approved Apple Development Team")
    if "url: https://github.com/voldzi/CSM-messenger.git" not in project:
        failures.append("project.yml must consume CSMCommunicationKit from the published GitHub repository")
    if "revision: a1b8928a1f5d18fc2c664e24bdc8a2f844c40fa9" not in project:
        failures.append("project.yml must pin the reviewed CSMCommunicationKit Git revision")
    if 'path: "../../../04 CSM messenger"' in project:
        failures.append("release project must not depend on a local sibling CSM checkout")
    if "- path: Resources" not in project:
        failures.append("application target must compile the Resources asset catalog")
    if "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" not in project:
        failures.append("application target must compile AppIcon as its launcher icon")

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

    forbidden_keys = {
        "NSLocationAlwaysUsageDescription",
        "NSLocationAlwaysAndWhenInUseUsageDescription",
    }
    location_purpose = (
        "CSM používá polohu při práci s COP k zobrazení vaší pozice, směru a "
        "k připojení polohy pouze k akci, kterou spustíte."
    )
    microphone_purpose = (
        "CSM používá mikrofon pouze během hovoru nebo při nahrávání hlasové "
        "zprávy, které sami spustíte v COP Chatu."
    )
    face_id_purpose = (
        "CSM používá Face ID pouze tehdy, když bezpečnostní politika COP vyžaduje "
        "místní biometrické odemknutí před zobrazením krizových dat."
    )
    required_phone_orientations = {
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    }
    required_pad_orientations = required_phone_orientations | {
        "UIInterfaceOrientationPortraitUpsideDown"
    }
    for name, plist in (("debug", debug), ("staging", staging), ("release", release)):
        if plist.get("CFBundleDisplayName") != "COP Mobile":
            failures.append(f"{name} launcher name must be COP Mobile")
        present = forbidden_keys.intersection(plist)
        if present:
            failures.append(f"{name} enables out-of-scope phase 2 capabilities: {sorted(present)}")
        if plist.get("NSLocationWhenInUseUsageDescription") != location_purpose:
            failures.append(f"{name} must contain the approved location purpose string")
        if plist.get("NSMicrophoneUsageDescription") != microphone_purpose:
            failures.append(f"{name} must contain the approved call and voice-message microphone purpose string")
        if plist.get("NSFaceIDUsageDescription") != face_id_purpose:
            failures.append(f"{name} must contain the approved policy-gated Face ID purpose string")
        if plist.get("CSMCopBaseURL") != "https://cop.zeleznalady.cz":
            failures.append(f"{name} native communications COP endpoint must be exact production HTTPS URL")
        if plist.get("CSMessagingBaseURL") != "https://msg.zeleznalady.cz":
            failures.append(f"{name} native communications endpoint must be exact production HTTPS URL")
        if plist.get("CSMOIDCIssuer") != "https://login.zeleznalady.cz/realms/cop":
            failures.append(f"{name} native OIDC issuer must be the exact COP realm")
        if plist.get("CSMOIDCClientId") != "csm-mobile" or plist.get("CSMOIDCRedirectScheme") != "csm":
            failures.append(f"{name} native OIDC public client and redirect scheme are not approved")
        url_schemes = {
            scheme
            for entry in plist.get("CFBundleURLTypes", [])
            for scheme in entry.get("CFBundleURLSchemes", [])
        }
        if url_schemes != {"csm"}:
            failures.append(f"{name} must register only the approved csm callback scheme")
        if set(plist.get("UIBackgroundModes", [])) != {"audio", "remote-notification", "voip"}:
            failures.append(
                f"{name} must enable only active-call audio, remote-notification and real-call voip background modes"
            )
        if set(plist.get("UISupportedInterfaceOrientations", [])) != required_phone_orientations:
            failures.append(f"{name} must support the approved iPhone orientations")
        if set(plist.get("UISupportedInterfaceOrientations~ipad", [])) != required_pad_orientations:
            failures.append(f"{name} must support every iPad orientation")

    entitlements = list(IOS.rglob("*.entitlements"))
    expected_entitlements = [IOS / "Config" / "COPMobile.entitlements"]
    if entitlements != expected_entitlements:
        failures.append("iOS host must contain only Config/COPMobile.entitlements")
    else:
        with entitlements[0].open("rb") as handle:
            entitlement_values = plistlib.load(handle)
        expected_entitlement_values = {
            "aps-environment": "$(APS_ENVIRONMENT)",
            "com.apple.developer.usernotifications.time-sensitive": True,
        }
        if entitlement_values != expected_entitlement_values:
            failures.append(
                "COPMobile.entitlements must contain only the configuration-bound aps-environment "
                "and the Time Sensitive Notifications entitlement"
            )
    xcconfig_expectations = {
        "Debug.xcconfig": "APS_ENVIRONMENT = development",
        "Staging.xcconfig": "APS_ENVIRONMENT = production",
        "Release.xcconfig": "APS_ENVIRONMENT = production",
    }
    for filename, expected in xcconfig_expectations.items():
        if expected not in (IOS / "Config" / filename).read_text():
            failures.append(f"{filename} must declare {expected}")
    if "CODE_SIGN_ENTITLEMENTS: Config/COPMobile.entitlements" not in project:
        failures.append("application target must sign with the approved APNs entitlements file")

    app_icon_set = IOS / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
    app_icon = app_icon_set / "AppIcon-1024.png"
    app_icon_manifest = app_icon_set / "Contents.json"
    if not app_icon_manifest.is_file():
        failures.append("AppIcon.appiconset must contain Contents.json")
    else:
        manifest = json.loads(app_icon_manifest.read_text(encoding="utf-8"))
        expected_image = {
            "filename": "AppIcon-1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }
        if expected_image not in manifest.get("images", []):
            failures.append("AppIcon.appiconset must declare the opaque universal 1024x1024 icon")
    if not app_icon.is_file():
        failures.append("AppIcon.appiconset must contain AppIcon-1024.png")
    else:
        png = app_icon.read_bytes()
        if png[:8] != b"\x89PNG\r\n\x1a\n" or len(png) < 33:
            failures.append("AppIcon-1024.png must be a valid PNG")
        else:
            width, height, _, color_type = struct.unpack(">IIBB", png[16:26])
            if (width, height) != (1024, 1024):
                failures.append("AppIcon-1024.png must be exactly 1024x1024 pixels")
            if color_type in {4, 6} or b"tRNS" in png:
                failures.append("AppIcon-1024.png must be opaque")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        return 1
    print(
        "iOS project configuration is fail-closed, APNs-enabled, location-When-In-Use and voice-call microphone enabled, and pinned "
        "to iOS 26.0 / Swift 6 / approved signing identity."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
