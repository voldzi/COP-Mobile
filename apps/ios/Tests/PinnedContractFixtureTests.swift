import XCTest

@testable import COPMobile

@MainActor
final class PinnedContractFixtureTests: XCTestCase {
  func testPinnedValidHelloFixtureDrivesNativeHandshake() throws {
    let fixture = try fixtureJSON(subdirectory: "fixtures/v1/valid", name: "bridge-hello")
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let url = try XCTUnwrap(URL(string: "https://cop.zeleznalady.cz"))
    let bridge = DeviceBridgeCoordinator(
      originPolicy: OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    )
    bridge.navigationDidCommit(url: url)

    let response = bridge.handle(
      message: fixture,
      context: .init(isMainFrame: true, frameURL: url, mainFrameURL: url)
    )

    XCTAssertEqual(response["kind"] as? String, "ready")
    XCTAssertEqual(response["id"] as? String, fixture["id"] as? String)
  }

  func testPinnedInvalidRequestFixtureIsRejected() throws {
    let fixture = try fixtureJSON(
      subdirectory: "fixtures/v1/invalid",
      name: "bridge-request-missing-session"
    )
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let url = try XCTUnwrap(URL(string: "https://cop.zeleznalady.cz"))
    let bridge = DeviceBridgeCoordinator(
      originPolicy: OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    )
    bridge.navigationDidCommit(url: url)

    let response = bridge.handle(
      message: fixture,
      context: .init(isMainFrame: true, frameURL: url, mainFrameURL: url)
    )

    XCTAssertEqual(response["ok"] as? Bool, false)
    XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? String, "INVALID_REQUEST")
  }

  private func fixtureJSON(subdirectory: String, name: String) throws -> [String: Any] {
    let bundle = Bundle(for: Self.self)
    let url = try XCTUnwrap(
      bundle.url(forResource: name, withExtension: "json", subdirectory: subdirectory))
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return try XCTUnwrap(value as? [String: Any])
  }
}
