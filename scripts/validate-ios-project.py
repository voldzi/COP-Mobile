#!/usr/bin/env python3
import json
import plistlib
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "apps" / "ios"
COMMUNICATION_KIT = ROOT / "packages" / "CSMCommunicationKit"


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

    if project.count('iOS: "26.0"') != 1 or project.count('deploymentTarget: "26.0"') != 3:
        failures.append("project.yml must pin project, host and both test targets to iOS 26.0")
    if "IPHONEOS_DEPLOYMENT_TARGET = 26.0" not in base:
        failures.append("Base.xcconfig must pin IPHONEOS_DEPLOYMENT_TARGET to 26.0")
    if "SWIFT_VERSION = 6.0" not in base:
        failures.append("Base.xcconfig must pin Swift 6.0")
    if "PRODUCT_BUNDLE_IDENTIFIER = cz.zeleznalady.csm.messenger" not in base:
        failures.append("Base.xcconfig must use the approved legacy bundle ID")
    if "DEVELOPMENT_TEAM: LM6W548X36" not in project:
        failures.append("project.yml must use the approved Apple Development Team")
    if "path: ../../packages/CSMCommunicationKit" not in project:
        failures.append("project.yml must consume the COP Mobile-owned local CSMCommunicationKit package")
    if "CSM-messenger.git" in project or "04 CSM messenger" in project:
        failures.append("release project must not depend on the legacy app repository or its Git package")
    communication_package = COMMUNICATION_KIT / "Package.swift"
    if not communication_package.is_file():
        failures.append("packages/CSMCommunicationKit/Package.swift must exist")
    else:
        package_text = communication_package.read_text(encoding="utf-8")
        required_chat_sources = {
            "ConversationListView.swift",
            "ConversationWorkspace.swift",
            "LoginView.swift",
            "MessageComposerView.swift",
            "MessageTimelineViews.swift",
            "Sources/CSMCommunicationKit",
        }
        for filename in required_chat_sources:
            if filename not in package_text:
                failures.append(f"local CSMCommunicationKit must explicitly compile {filename}")
        forbidden_application_sources = {
            "MapWorkspaceView.swift",
            "ReportDraftView.swift",
            "SettingsView.swift",
            "RootView.swift",
            "RelayView.swift",
        }
        for filename in forbidden_application_sources:
            if filename in package_text:
                failures.append(f"local CSMCommunicationKit must not compile legacy application UI {filename}")
        if '.testTarget(' not in package_text or 'name: "CSMCommunicationKitTests"' not in package_text:
            failures.append("local CSMCommunicationKit must retain its communication test target")

    communication_model = COMMUNICATION_KIT / "Sources" / "CSMCore" / "CommunicationModel.swift"
    legacy_app_model = COMMUNICATION_KIT / "Sources" / "CSMCore" / "AppModel.swift"
    if legacy_app_model.exists():
        failures.append("local CSMCommunicationKit must not contain the legacy cross-domain AppModel.swift")
    if not communication_model.is_file():
        failures.append("local CSMCommunicationKit must contain CommunicationModel.swift")
    else:
        communication_model_text = communication_model.read_text(encoding="utf-8")
        forbidden_domain_ownership = {
            "communityReports": "community-report state",
            "mapDisplayProfile": "map display state",
            "offlineMapPacks": "offline map state",
            "weatherRadarOverlay": "weather-radar state",
            "CrisisRelayServing": "relay runtime ownership",
            "WatchBridgeSyncing": "watch synchronization ownership",
        }
        for token, description in forbidden_domain_ownership.items():
            if token in communication_model_text:
                failures.append(
                    f"CommunicationModel.swift must not restore {description}"
                )

    removed_native_domains = {
        "CSMMeshProtocol.swift",
        "CrisisRelayGatewayClient.swift",
        "CrisisRelayService.swift",
        "CrisisRelayTransportPolicy.swift",
        "FieldReadinessSnapshot.swift",
        "MapDensityProfile.swift",
        "MapSearchIndex.swift",
        "RadioPlanningModels.swift",
        "WatchBridgeService.swift",
    }
    for filename in removed_native_domains:
        if (COMMUNICATION_KIT / "Sources" / "CSMCore" / filename).exists():
            failures.append(
                f"local CSMCommunicationKit must not contain removed cross-domain source {filename}"
            )

    chat_architecture = COMMUNICATION_KIT / "Sources" / "CSMCore" / "ChatArchitecture.swift"
    if not chat_architecture.is_file():
        failures.append("local CSMCommunicationKit must contain ChatArchitecture.swift")
    else:
        architecture_text = chat_architecture.read_text(encoding="utf-8")
        required_architecture_symbols = {
            "final class ChatSessionStore",
            "final class ConversationListStore",
            "final class TimelineStore",
            "enum TimelineReducer",
            "final class TimelineSynchronizationController",
            "actor OutboxActor",
            "actor MediaPipelineActor",
            "actor SearchIndex",
            "enum ChatPerformanceBudget",
        }
        for symbol in required_architecture_symbols:
            if symbol not in architecture_text:
                failures.append(f"native chat architecture must retain {symbol}")

    chat_architecture_tests = (
        COMMUNICATION_KIT
        / "Tests"
        / "CSMCommunicationKitTests"
        / "ChatArchitectureTests.swift"
    )
    if not chat_architecture_tests.is_file():
        failures.append("local CSMCommunicationKit must contain ChatArchitectureTests.swift")
    else:
        architecture_test_text = chat_architecture_tests.read_text(encoding="utf-8")
        required_release_fixtures = {
            "testTimelineFixturesStayBoundedAtAllReleaseSizes",
            "testEarlierPagingShiftsBoundedWindowAndCanReturnToLatest",
            "testBurstOfOneHundredEventsLosesNothingAndCreatesNoDuplicates",
            "testEncryptedOutboxSurvivesRestartAndDeduplicatesStableTransaction",
            "testOfflineClientReturnsBoundedCacheWithoutWaitingForLiveTransport",
            "testTimelinePresentationP95StaysWithinInteractionBudget",
        }
        for test_name in required_release_fixtures:
            if test_name not in architecture_test_text:
                failures.append(f"native chat release gate must retain {test_name}")

    communication_sources = COMMUNICATION_KIT / "Sources"
    forbidden_chat_regressions = {
        "activeMessageStreamTask": "parallel timeline stream ownership",
        "activeMessageRefreshTask": "parallel timeline polling ownership",
        "maximumLoadedTimelineItems = 5_000": "an unbounded 5,000-message in-memory timeline",
        "maximumLoadedTimelineItems = 5000": "an unbounded 5,000-message in-memory timeline",
    }
    for source_file in communication_sources.rglob("*.swift"):
        source_text = source_file.read_text(encoding="utf-8")
        for pattern, description in forbidden_chat_regressions.items():
            if pattern in source_text:
                failures.append(
                    f"{source_file.relative_to(ROOT)} must not restore {description}"
                )
    nested_projects = list(COMMUNICATION_KIT.rglob("*.xcodeproj"))
    if nested_projects:
        failures.append("local CSMCommunicationKit must not embed a legacy Xcode application project")
    if "- path: Resources" not in project:
        failures.append("application target must compile the Resources asset catalog")
    if "ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon" not in project:
        failures.append("application target must compile AppIcon as its launcher icon")
    if "COPMobileUITests:" not in project or "type: bundle.ui-testing" not in project:
        failures.append("application target must retain the native UI smoke-test target")
    if "- COPMobileUITests" not in project:
        failures.append("COPMobile scheme must run the native UI smoke-test target")
    ui_smoke_test = ROOT / "apps" / "ios" / "UITests" / "COPMobileLaunchUITests.swift"
    if not ui_smoke_test.is_file():
        failures.append("native UI smoke-test source must be present")

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
        "COP Mobile používá polohu k zobrazení vaší pozice a směru; polohu "
        "připojí jen k akci, kterou sami spustíte."
    )
    microphone_purpose = (
        "COP Mobile používá mikrofon jen během hovoru nebo nahrávání hlasové "
        "zprávy, které sami spustíte."
    )
    face_id_purpose = (
        "COP Mobile použije Face ID jen tehdy, když bezpečnostní politika COP "
        "vyžaduje místní odemknutí chráněných dat."
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
        "iOS project configuration is standalone, fail-closed, APNs-enabled, location-When-In-Use and voice-call microphone enabled, "
        "and pinned to the COP Mobile-owned communication package, iOS 26.0 / Swift 6 / approved signing identity."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
