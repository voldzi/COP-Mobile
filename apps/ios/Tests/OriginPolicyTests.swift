import XCTest

@testable import COPMobile

final class OriginPolicyTests: XCTestCase {
  func testExactOriginAllowsPathsButRejectsLookalikesAndPorts() throws {
    let production = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let oidc = try WebOrigin(configurationValue: "https://login.zeleznalady.cz")
    let policy = OriginPolicy(
      bridgeOrigins: [production],
      navigationOrigins: [production, oidc]
    )

    XCTAssertTrue(
      policy.allowsInternalNavigation(to: try url("https://cop.zeleznalady.cz/map?layer=flood")))
    XCTAssertTrue(
      policy.allowsInternalNavigation(to: try url("https://login.zeleznalady.cz/realms/cop")))
    XCTAssertFalse(policy.allowsInternalNavigation(to: try url("http://cop.zeleznalady.cz")))
    XCTAssertFalse(
      policy.allowsInternalNavigation(to: try url("https://cop.zeleznalady.cz.evil.example")))
    XCTAssertFalse(policy.allowsInternalNavigation(to: try url("https://sub.cop.zeleznalady.cz")))
    XCTAssertFalse(policy.allowsInternalNavigation(to: try url("https://cop.zeleznalady.cz:444")))
    XCTAssertFalse(policy.allowsInternalNavigation(to: try url("https://user@cop.zeleznalady.cz")))
  }

  func testBridgeRequiresFrameAndCurrentMainFrameToShareAllowedOrigin() throws {
    let production = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let policy = OriginPolicy(bridgeOrigins: [production], navigationOrigins: [production])

    XCTAssertTrue(
      policy.allowsBridge(
        frameURL: try url("https://cop.zeleznalady.cz/app"),
        mainFrameURL: try url("https://cop.zeleznalady.cz/map")
      )
    )
    XCTAssertFalse(
      policy.allowsBridge(
        frameURL: try url("https://cop.zeleznalady.cz/app"),
        mainFrameURL: try url("https://login.zeleznalady.cz/realms/cop")
      )
    )
  }

  func testMicrophoneCaptureRequiresExactAllowedMainFrameAndRejectsVideo() throws {
    let allowed = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let policy = OriginPolicy(bridgeOrigins: [allowed], navigationOrigins: [allowed])
    let frameURL = URL(string: "https://cop.zeleznalady.cz/chat")!

    XCTAssertTrue(
      policy.allowsMicrophoneCapture(
        frameURL: frameURL,
        mainFrameURL: frameURL,
        requestingScheme: "https",
        requestingHost: "cop.zeleznalady.cz",
        requestingPort: 443,
        isMainFrame: true,
        microphoneOnly: true
      ))
    XCTAssertFalse(
      policy.allowsMicrophoneCapture(
        frameURL: frameURL,
        mainFrameURL: frameURL,
        requestingScheme: "https",
        requestingHost: "cop.zeleznalady.cz",
        requestingPort: 443,
        isMainFrame: false,
        microphoneOnly: true
      ))
    XCTAssertFalse(
      policy.allowsMicrophoneCapture(
        frameURL: frameURL,
        mainFrameURL: frameURL,
        requestingScheme: "https",
        requestingHost: "cop.zeleznalady.cz",
        requestingPort: 443,
        isMainFrame: true,
        microphoneOnly: false
      ))
    XCTAssertFalse(
      policy.allowsMicrophoneCapture(
        frameURL: frameURL,
        mainFrameURL: frameURL,
        requestingScheme: "https",
        requestingHost: "lookalike.example",
        requestingPort: 443,
        isMainFrame: true,
        microphoneOnly: true
      ))
  }

  private func url(_ value: String) throws -> URL {
    try XCTUnwrap(URL(string: value))
  }
}
