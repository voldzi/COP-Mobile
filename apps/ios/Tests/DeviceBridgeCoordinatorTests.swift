import XCTest

@testable import COPMobile

@MainActor
final class DeviceBridgeCoordinatorTests: XCTestCase {
  private let productionURL = URL(string: "https://cop.zeleznalady.cz/app")!

  func testCompatibleHandshakeReturnsLocationAndHeadingCapabilities() async throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)

    let response = await bridge.handle(message: hello(), context: allowedContext())

    XCTAssertEqual(response["kind"] as? String, "ready")
    XCTAssertEqual(response["selectedVersion"] as? String, "1.0.0")
    let capabilities = try XCTUnwrap(response["capabilities"] as? [String: Any])
    XCTAssertEqual(
      (capabilities["system"] as? [String: Any])?["availability"] as? String, "supported")
    XCTAssertEqual(
      (capabilities["location"] as? [String: Any])?["availability"] as? String, "supported")
    XCTAssertEqual(
      (capabilities["heading"] as? [String: Any])?["supportsBackground"] as? Bool, false)
    XCTAssertEqual(
      (capabilities["tracking"] as? [String: Any])?["availability"] as? String, "unsupported")
    XCTAssertEqual(
      (capabilities["relay"] as? [String: Any])?["availability"] as? String, "unsupported")
  }

  func testIncompatibleHandshakeIsBlocked() async throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)
    var message = hello()
    message["supportedVersions"] = ["2.0.0"]

    let response = await bridge.handle(message: message, context: allowedContext())

    XCTAssertEqual(response["kind"] as? String, "blocked")
    XCTAssertEqual(
      (response["error"] as? [String: Any])?["code"] as? String, "PROTOCOL_VERSION_UNSUPPORTED")
  }

  func testIframeAndChangedMainFrameOriginCannotUseBridge() async throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)

    let iframe = await bridge.handle(
      message: hello(),
      context: .init(isMainFrame: false, frameURL: productionURL, mainFrameURL: productionURL)
    )
    XCTAssertEqual((iframe["error"] as? [String: Any])?["code"] as? String, "MAIN_FRAME_REQUIRED")

    bridge.navigationDidCommit(url: productionURL)
    let redirect = await bridge.handle(
      message: hello(),
      context: .init(
        isMainFrame: true,
        frameURL: productionURL,
        mainFrameURL: URL(string: "https://login.zeleznalady.cz/realms/cop")!
      )
    )
    XCTAssertEqual((redirect["error"] as? [String: Any])?["code"] as? String, "ORIGIN_NOT_ALLOWED")
  }

  func testSystemCapabilitiesRequestRequiresCurrentSession() async throws {
    let bridge = try makeBridge()
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
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

    let response = await bridge.handle(message: request, context: allowedContext())
    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertNotNil(response["result"] as? [String: Any])

    var replayWithDifferentContent = request
    replayWithDifferentContent["method"] = "location.getCurrent"
    let replay = await bridge.handle(message: replayWithDifferentContent, context: allowedContext())
    XCTAssertEqual((replay["error"] as? [String: Any])?["code"] as? String, "INVALID_REQUEST")

    bridge.navigationDidCommit(url: productionURL)
    let stale = await bridge.handle(message: request, context: allowedContext())
    XCTAssertEqual((stale["error"] as? [String: Any])?["code"] as? String, "SESSION_EXPIRED")
  }

  func testCurrentLocationReturnsContractSampleWithoutPrompting() async throws {
    let provider = FakeLocationProvider()
    let bridge = try makeBridge(location: provider)
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(method: "location.getCurrent", sessionID: sessionID, params: ["desiredAccuracy": "best"]),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual((response["result"] as? [String: Any])?["latitude"] as? Double, 50.0755)
    XCTAssertEqual(provider.authorizationRequestCount, 0)
  }

  func testLocationSubscriptionEmitsSequencedEventAndStopsWithSession() async throws {
    let provider = FakeLocationProvider()
    let bridge = try makeBridge(location: provider)
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)
    provider.stopAllCount = 0
    var events: [[String: Any]] = []
    bridge.eventSink = { events.append($0) }

    let response = await bridge.handle(
      message: request(method: "location.startUpdates", sessionID: sessionID, params: [:]),
      context: allowedContext())
    provider.emitLocation()

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual(events.first?["type"] as? String, "location.updated")
    XCTAssertEqual(events.first?["sequence"] as? Int, 1)
    bridge.invalidateSession()
    XCTAssertEqual(provider.stopAllCount, 1)
  }

  func testCallActionQueuedBeforeHandshakeIsDeliveredAfterBridgeReady() async throws {
    let notifications = FakeNotificationProvider()
    let bridge = try makeBridge(notifications: notifications)
    var events: [[String: Any]] = []
    bridge.eventSink = { events.append($0) }
    notifications.emit(
      type: "calls.answerRequested",
      payload: ["callId": "call-1", "roomId": "!ops:example.cz"])
    bridge.navigationDidCommit(url: productionURL)

    _ = await bridge.handle(message: hello(), context: allowedContext())
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(events.first?["type"] as? String, "calls.answerRequested")
    XCTAssertEqual((events.first?["payload"] as? [String: Any])?["callId"] as? String, "call-1")
  }

  private func makeBridge(
    location: DeviceLocationProviding? = nil,
    notifications: PushNotificationProviding? = nil
  ) throws -> DeviceBridgeCoordinator {
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let policy = OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    if location != nil || notifications != nil {
      return DeviceBridgeCoordinator(
        originPolicy: policy,
        location: location ?? FakeLocationProvider(),
        notifications: notifications ?? FakeNotificationProvider(),
        isForeground: { true })
    }
    return DeviceBridgeCoordinator(originPolicy: policy)
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

  private func request(method: String, sessionID: String, params: [String: Any]) -> [String: Any] {
    [
      "kind": "request", "protocolVersion": "1.0.0", "id": UUID().uuidString.lowercased(),
      "sessionId": sessionID, "method": method, "sentAt": "2026-07-11T10:00:01.000Z",
      "params": params,
    ]
  }
}

@MainActor
private final class FakeNotificationProvider: PushNotificationProviding {
  var deviceToken: String?
  var eventReceiver: ((String, [String: Any]) -> Void)?

  func status() async -> [String: Any] { ["authorization": "authorized"] }
  func requestAuthorization() async -> [String: Any] { ["authorization": "authorized"] }
  func registrationContext() -> [String: Any] { [:] }
  func registerRemote(ticket: String, messagingBaseURL: String) async throws -> [String: Any] { [:] }
  func recordDeviceToken(_ data: Data) {}
  func recordRegistrationFailure(_ error: any Error) {}
  func receiveRemoteNotification(_ userInfo: [AnyHashable: Any], interaction: Bool) {}

  func emit(type: String, payload: [String: Any]) {
    eventReceiver?(type, payload)
  }
}

@MainActor
private final class FakeLocationProvider: DeviceLocationProviding {
  var permission = "granted"
  var reducedAccuracy = false
  var locationAvailable = true
  var headingAvailable = true
  var authorizationRequestCount = 0
  var stopAllCount = 0
  private var locationReceiver: (([String: Any]) -> Void)?

  func requestWhenInUseAuthorization() async -> String {
    authorizationRequestCount += 1
    return permission
  }

  func currentLocation(timeout: Duration) async throws -> [String: Any] { sample }

  func startLocationUpdates(_ receive: @escaping ([String: Any]) -> Void) throws {
    locationReceiver = receive
  }

  func stopLocationUpdates() { locationReceiver = nil }
  func startHeadingUpdates(_ receive: @escaping ([String: Any]) -> Void) throws {}
  func stopHeadingUpdates() {}
  func stopAllUpdates() {
    stopAllCount += 1
    locationReceiver = nil
  }

  func emitLocation() { locationReceiver?(sample) }

  private var sample: [String: Any] {
    [
      "sampleId": UUID().uuidString.lowercased(), "measuredAt": "2026-07-11T10:00:02.000Z",
      "receivedAt": "2026-07-11T10:00:02.050Z", "source": "live", "latitude": 50.0755,
      "longitude": 14.4378, "horizontalAccuracyM": 4.2, "altitudeM": 235.1,
      "verticalAccuracyM": 7.1, "speedMps": 0.3, "courseDeg": NSNull(),
      "reducedAccuracy": false, "valid": true,
    ]
  }
}
