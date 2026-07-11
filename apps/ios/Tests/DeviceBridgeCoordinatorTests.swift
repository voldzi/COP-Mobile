import XCTest

@testable import COPMobile

@MainActor
final class DeviceBridgeCoordinatorTests: XCTestCase {
  private let productionURL = URL(string: "https://cop.zeleznalady.cz/app")!

  func testCompatibleHandshakeReturnsOnlyTruthfulFeasibilityCapabilities() throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)

    let response = bridge.handle(message: hello(), context: allowedContext())

    XCTAssertEqual(response["kind"] as? String, "ready")
    XCTAssertEqual(response["selectedVersion"] as? String, "1.0.0")
    let capabilities = try XCTUnwrap(response["capabilities"] as? [String: Any])
    XCTAssertEqual(
      (capabilities["system"] as? [String: Any])?["availability"] as? String, "supported")
    XCTAssertEqual(
      (capabilities["location"] as? [String: Any])?["availability"] as? String, "unsupported")
    XCTAssertEqual(
      (capabilities["tracking"] as? [String: Any])?["availability"] as? String, "unsupported")
    XCTAssertEqual(
      (capabilities["relay"] as? [String: Any])?["availability"] as? String, "unsupported")
  }

  func testIncompatibleHandshakeIsBlocked() throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)
    var message = hello()
    message["supportedVersions"] = ["2.0.0"]

    let response = bridge.handle(message: message, context: allowedContext())

    XCTAssertEqual(response["kind"] as? String, "blocked")
    XCTAssertEqual(
      (response["error"] as? [String: Any])?["code"] as? String, "PROTOCOL_VERSION_UNSUPPORTED")
  }

  func testIframeAndChangedMainFrameOriginCannotUseBridge() throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)

    let iframe = bridge.handle(
      message: hello(),
      context: .init(isMainFrame: false, frameURL: productionURL, mainFrameURL: productionURL)
    )
    XCTAssertEqual((iframe["error"] as? [String: Any])?["code"] as? String, "MAIN_FRAME_REQUIRED")

    bridge.navigationDidCommit(url: productionURL)
    let redirect = bridge.handle(
      message: hello(),
      context: .init(
        isMainFrame: true,
        frameURL: productionURL,
        mainFrameURL: URL(string: "https://login.zeleznalady.cz/realms/cop")!
      )
    )
    XCTAssertEqual((redirect["error"] as? [String: Any])?["code"] as? String, "ORIGIN_NOT_ALLOWED")
  }

  func testSystemCapabilitiesRequestRequiresCurrentSession() throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)
    let ready = bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)
    let requestID = UUID().uuidString.lowercased()
    let request: [String: Any] = [
      "kind": "request",
      "protocolVersion": "1.0.0",
      "id": requestID,
      "sessionId": sessionID,
      "method": "system.getCapabilities",
      "sentAt": "2026-07-11T10:00:01.000Z",
      "params": [:],
    ]

    let response = bridge.handle(message: request, context: allowedContext())
    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertNotNil(response["result"] as? [String: Any])

    var replayWithDifferentContent = request
    replayWithDifferentContent["method"] = "location.getCurrent"
    let replay = bridge.handle(message: replayWithDifferentContent, context: allowedContext())
    XCTAssertEqual((replay["error"] as? [String: Any])?["code"] as? String, "INVALID_REQUEST")

    bridge.navigationDidCommit(url: productionURL)
    let stale = bridge.handle(message: request, context: allowedContext())
    XCTAssertEqual((stale["error"] as? [String: Any])?["code"] as? String, "SESSION_EXPIRED")
  }

  private func makeBridge() throws -> DeviceBridgeCoordinator {
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    return DeviceBridgeCoordinator(
      originPolicy: OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    )
  }

  private func hello() -> [String: Any] {
    [
      "kind": "hello",
      "id": "10000000-0000-4000-8000-000000000001",
      "sentAt": "2026-07-11T10:00:00.000Z",
      "supportedVersions": ["1.0.0"],
      "webBuildId": "cop-web-test",
    ]
  }

  private func allowedContext() -> DeviceBridgeCoordinator.RequestContext {
    .init(isMainFrame: true, frameURL: productionURL, mainFrameURL: productionURL)
  }
}
