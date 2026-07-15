import XCTest

@testable import COPMobile

@MainActor
final class DeviceBridgeCoordinatorTests: XCTestCase {
  private let productionURL = URL(string: "https://cop.zeleznalady.cz/app")!

  func testWebHostUsesDedicatedPersistentRuntime() {
    XCTAssertTrue(PersistentWebRuntime.websiteDataStore.isPersistent)
    XCTAssertNotNil(PersistentWebRuntime.websiteDataStore.identifier)
  }

  func testStartingVoiceCallFromNativeChatKeepsChatSurfaceMounted() {
    let model = AppModel()
    var startRequests: [(String, String, Bool)] = []

    model.openNativeChat()
    model.startNativeVoiceCall(
      roomID: "!ops:example.cz",
      title: "COP Operator",
      isGroup: false
    ) { roomID, title, isGroup in
      startRequests.append((roomID, title, isGroup))
    }

    XCTAssertEqual(model.surface, .chat)
    XCTAssertEqual(startRequests.count, 1)
    XCTAssertEqual(startRequests.first?.0, "!ops:example.cz")
    XCTAssertEqual(startRequests.first?.1, "COP Operator")
    XCTAssertEqual(startRequests.first?.2, false)
  }

  func testAIChatUsesAlreadyAuthorizedLocationWithoutPrompting() async throws {
    let provider = FakeLocationProvider()
    let model = AppModel(deviceLocationProvider: provider)

    let resolvedLocation = await model.currentCommunicationLocation()
    let location = try XCTUnwrap(resolvedLocation)

    XCTAssertEqual(location.latitude, 50.0755)
    XCTAssertEqual(location.longitude, 14.4378)
    XCTAssertEqual(location.radiusKilometers, 15)
    XCTAssertEqual(location.label, "Aktuální poloha")
    XCTAssertEqual(provider.authorizationRequestCount, 0)
  }

  func testAIChatDoesNotRequestLocationWhenPermissionIsMissing() async {
    let provider = FakeLocationProvider()
    provider.permission = "notDetermined"
    let model = AppModel(deviceLocationProvider: provider)

    let location = await model.currentCommunicationLocation()

    XCTAssertNil(location)
    XCTAssertEqual(provider.authorizationRequestCount, 0)
  }

  func testOnlyOpeningNotificationActionsNavigateToNativeChat() {
    XCTAssertTrue(
      PushNotificationService.shouldOpenNativeChat(
        for: "com.apple.UNNotificationDefaultActionIdentifier"))
    XCTAssertTrue(PushNotificationService.shouldOpenNativeChat(for: "CSM_OPEN"))
    XCTAssertTrue(PushNotificationService.shouldOpenNativeChat(for: "CSM_REPLY"))
    XCTAssertFalse(PushNotificationService.shouldOpenNativeChat(for: "CSM_MARK_READ"))
    XCTAssertFalse(PushNotificationService.shouldOpenNativeChat(for: "CSM_ACKNOWLEDGE"))
    XCTAssertFalse(
      PushNotificationService.shouldOpenNativeChat(
        for: "com.apple.UNNotificationDismissActionIdentifier"))
  }

  func testRemoteRegistrationUsesCanonicalNotificationCategories() {
    XCTAssertEqual(
      Set(PushNotificationService.registrationCategories),
      Set([
        "community.report",
        "message.direct",
        "message.group",
        "message.voice_call",
        "safety.alert",
        "safety.area_update",
        "system.account",
        "system.delivery",
      ]))
    XCTAssertFalse(PushNotificationService.registrationCategories.contains("system"))
  }

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
      message: request(
        method: "location.getCurrent", sessionID: sessionID, params: ["desiredAccuracy": "best"]),
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
      payload: [
        "actionId": "10000000-0000-4000-8000-000000000001",
        "callId": "call-1",
        "roomId": "!ops:example.cz",
      ])
    bridge.navigationDidCommit(url: productionURL)

    _ = await bridge.handle(message: hello(), context: allowedContext())
    await Task.yield()
    await Task.yield()

    XCTAssertEqual(events.first?["type"] as? String, "calls.answerRequested")
    XCTAssertEqual((events.first?["payload"] as? [String: Any])?["callId"] as? String, "call-1")
  }

  func testCallActionAcknowledgementIsIdentityBoundAndDeliveredToCallService() async throws {
    var acknowledgements: [(String, String, String, String)] = []
    let bridge = try makeBridge(acknowledgeCallAction: {
      acknowledgements.append(($0, $1, $2, $3))
      return true
    })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(
        method: "calls.acknowledgeAction",
        sessionID: sessionID,
        params: [
          "actionId": "10000000-0000-4000-8000-000000000001",
          "callId": "call-1",
          "outcome": "succeeded",
          "roomId": "!ops:example.cz",
        ]),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual((response["result"] as? [String: Any])?["acknowledged"] as? Bool, true)
    XCTAssertEqual(acknowledgements.first?.0, "10000000-0000-4000-8000-000000000001")
    XCTAssertEqual(acknowledgements.first?.3, "succeeded")
  }

  func testFailedJavaScriptEventDeliveryInvalidatesAndRequeuesStableAction() async throws {
    let notifications = FakeNotificationProvider()
    var invalidations = 0
    let bridge = try makeBridge(
      notifications: notifications,
      invalidateCallPresentation: { invalidations += 1 }
    )
    var events: [[String: Any]] = []
    bridge.eventSink = { events.append($0) }
    bridge.navigationDidCommit(url: productionURL)
    _ = await bridge.handle(message: hello(), context: allowedContext())
    notifications.emit(
      type: "calls.answerRequested",
      payload: [
        "actionId": "10000000-0000-4000-8000-000000000001",
        "callId": "call-1",
        "roomId": "!ops:example.cz",
      ])
    let failedEvent = try XCTUnwrap(events.first)

    bridge.eventDeliveryDidFail(failedEvent)
    XCTAssertEqual(invalidations, 1)
    events.removeAll()
    bridge.navigationDidCommit(url: productionURL)
    _ = await bridge.handle(message: hello(), context: allowedContext())

    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(
      (events.first?["payload"] as? [String: Any])?["actionId"] as? String,
      "10000000-0000-4000-8000-000000000001")
  }

  func testAuthenticatedMainFrameCanOpenNativeChat() async throws {
    var opened = 0
    let bridge = try makeBridge(openNativeChat: { opened += 1 })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(method: "communications.openChat", sessionID: sessionID, params: [:]),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual((response["result"] as? [String: Any])?["opened"] as? Bool, true)
    XCTAssertEqual(opened, 1)
  }

  func testCallPresentationAcceptsOnlyBoundedStateWithoutMediaPayload() async throws {
    var updates: [(
      String, String, String?, String, String, VoiceCallKind, [VoiceCallParticipant],
      [VoiceCallParticipant]
    )] = []
    let bridge = try makeBridge(updateCallPresentation: {
      updates.append(($0, $1, $2, $3, $4, $5, $6, $7))
      return true
    })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(
        method: "calls.updatePresentation",
        sessionID: sessionID,
        params: [
          "callId": "call-1", "roomId": "!ops:example.cz", "title": "COP Operator",
          "direction": "incoming", "phase": "connected", "kind": "group",
          "participants": [
            ["userId": "@alice:example.cz", "displayName": "Alice", "connected": true]
          ],
          "eligibleParticipants": [
            ["userId": "@bob:example.cz", "displayName": "Bob", "connected": false]
          ],
        ]),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual(updates.count, 1)
    XCTAssertEqual(updates.first?.0, "call-1")
    XCTAssertEqual(updates.first?.4, "connected")
    XCTAssertEqual(updates.first?.5, .group)
    XCTAssertEqual(updates.first?.6.first?.userID, "@alice:example.cz")
    XCTAssertEqual(updates.first?.7.first?.userID, "@bob:example.cz")

    let rejected = await bridge.handle(
      message: request(
        method: "calls.updatePresentation",
        sessionID: sessionID,
        params: [
          "callId": "call-2", "roomId": "!ops:example.cz", "direction": "incoming",
          "phase": "ringing", "sdp": "forbidden",
        ]),
      context: allowedContext())
    XCTAssertEqual((rejected["error"] as? [String: Any])?["code"] as? String, "INVALID_REQUEST")
    XCTAssertEqual(updates.count, 1)
  }

  func testCallPresentationRequiresForegroundAndInvalidatesWithBridgeSession() async throws {
    var updates = 0
    var invalidations = 0
    let bridge = try makeBridge(
      isForeground: { false },
      updateCallPresentation: { _, _, _, _, _, _, _, _ in
        updates += 1
        return true
      },
      invalidateCallPresentation: { invalidations += 1 }
    )
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let rejected = await bridge.handle(
      message: request(
        method: "calls.updatePresentation",
        sessionID: sessionID,
        params: [
          "callId": "call-1", "roomId": "!ops:example.cz", "direction": "incoming",
          "phase": "ringing",
        ]),
      context: allowedContext())

    XCTAssertEqual((rejected["error"] as? [String: Any])?["code"] as? String, "NOT_FOREGROUND")
    XCTAssertEqual(updates, 0)
    bridge.invalidateSession()
    XCTAssertEqual(invalidations, 1)
  }

  func testCallPresentationRateLimitSurvivesBridgeRehandshake() async throws {
    let bridge = try makeBridge(updateCallPresentation: { _, _, _, _, _, _, _, _ in true })
    bridge.navigationDidCommit(url: productionURL)
    var ready = await bridge.handle(message: hello(), context: allowedContext())
    var sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    for index in 0..<40 {
      if index == 20 {
        ready = await bridge.handle(message: hello(), context: allowedContext())
        sessionID = try XCTUnwrap(ready["sessionId"] as? String)
      }
      let response = await bridge.handle(
        message: request(
          method: "calls.updatePresentation",
          sessionID: sessionID,
          params: [
            "callId": "call-1", "roomId": "!ops:example.cz", "direction": "incoming",
            "phase": "ringing",
          ]),
        context: allowedContext())
      XCTAssertEqual(response["ok"] as? Bool, true)
    }

    let rejected = await bridge.handle(
      message: request(
        method: "calls.updatePresentation",
        sessionID: sessionID,
        params: [
          "callId": "call-1", "roomId": "!ops:example.cz", "direction": "incoming",
          "phase": "ringing",
        ]),
      context: allowedContext())
    XCTAssertEqual((rejected["error"] as? [String: Any])?["code"] as? String, "RATE_LIMITED")
  }

  private func makeBridge(
    location: DeviceLocationProviding? = nil,
    notifications: PushNotificationProviding? = nil,
    isForeground: @escaping () -> Bool = { true },
    openNativeChat: @escaping () -> Void = {},
    updateCallPresentation: @escaping (
      String, String, String?, String, String, VoiceCallKind, [VoiceCallParticipant],
      [VoiceCallParticipant]
    ) -> Bool = {
      _, _, _, _, _, _, _, _ in true
    },
    acknowledgeCallAction: @escaping (String, String, String, String) -> Bool = {
      _, _, _, _ in false
    },
    invalidateCallPresentation: @escaping () -> Void = {}
  ) throws -> DeviceBridgeCoordinator {
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let policy = OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    return DeviceBridgeCoordinator(
      originPolicy: policy,
      location: location ?? FakeLocationProvider(),
      notifications: notifications ?? FakeNotificationProvider(),
      isForeground: isForeground,
      openNativeChat: openNativeChat,
      updateCallPresentation: updateCallPresentation,
      acknowledgeCallAction: acknowledgeCallAction,
      invalidateCallPresentation: invalidateCallPresentation)
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
  func registerRemote(ticket: String, messagingBaseURL: String) async throws -> [String: Any] {
    [:]
  }
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
