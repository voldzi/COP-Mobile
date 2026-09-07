import XCTest
import CSMCommunicationKit

@testable import COPMobile

@MainActor
final class DeviceBridgeCoordinatorTests: XCTestCase {
  private let productionURL = URL(string: "https://cop.zeleznalady.cz/app")!

  func testWebHostUsesDedicatedPersistentRuntime() {
    XCTAssertTrue(PersistentWebRuntime.websiteDataStore.isPersistent)
    XCTAssertNotNil(PersistentWebRuntime.websiteDataStore.identifier)
  }

  func testChatOnlyStartupDefersLocationServiceUntilItIsNeeded() {
    var createdProviders = 0
    let model = AppModel(
      makeDeviceLocationProvider: {
        createdProviders += 1
        return FakeLocationProvider()
      })

    XCTAssertEqual(createdProviders, 0)
    _ = model.deviceLocationProvider
    XCTAssertEqual(createdProviders, 1)
  }

  func testAIChatUsesAlreadyAuthorizedLocationWithoutPrompting() async throws {
    let provider = FakeLocationProvider()
    let model = AppModel(deviceLocationProvider: provider)

    let resolvedLocation = await model.currentCommunicationLocation()
    let location = try XCTUnwrap(resolvedLocation)

    XCTAssertEqual(location.latitude, 50.0755)
    XCTAssertEqual(location.longitude, 14.4378)
    XCTAssertEqual(location.accuracyMeters, 4.2)
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

  func testExplicitChatLocationShareRequestsPermissionAndReturnsFreshSample() async throws {
    let provider = FakeLocationProvider()
    provider.permission = "notDetermined"
    provider.permissionAfterAuthorizationRequest = "granted"
    let model = AppModel(deviceLocationProvider: provider)

    let location = try await model.requestCommunicationLocationShare()

    XCTAssertEqual(provider.authorizationRequestCount, 1)
    XCTAssertEqual(location.latitude, 50.0755)
    XCTAssertEqual(location.longitude, 14.4378)
    XCTAssertEqual(location.accuracyMeters, 4.2)
    XCTAssertEqual(location.label, "Moje poloha")
  }

  func testExplicitChatLocationShareReportsDeniedPermission() async {
    let provider = FakeLocationProvider()
    provider.permission = "denied"
    let model = AppModel(deviceLocationProvider: provider)

    do {
      _ = try await model.requestCommunicationLocationShare()
      XCTFail("Odmítnuté oprávnění nesmí vrátit polohu.")
    } catch let error as CSMCommunicationLocationShareError {
      guard case .permissionDenied = error else {
        return XCTFail("Očekávána chyba permissionDenied.")
      }
    } catch {
      XCTFail("Neočekávaná chyba: \(error)")
    }

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

  func testIncomingVoiceCallPushMatchesCSMMessagingContract() throws {
    let payload = try XCTUnwrap(
      VoiceCallPushPayload(dictionary: [
        "aps": ["content-available": 1],
        "callId": "b5ea7309-7f53-4e87-9225-fd38e9737540",
        "roomId": "!direct:msg.zeleznalady.cz",
        "senderDisplayName": "Jiřina Volková",
        "type": "chat.voice_call.incoming",
      ]))

    XCTAssertEqual(payload.event, .incoming)
    XCTAssertEqual(payload.callID, "b5ea7309-7f53-4e87-9225-fd38e9737540")
    XCTAssertEqual(payload.roomID, "!direct:msg.zeleznalady.cz")
    XCTAssertEqual(payload.callerDisplayName, "Jiřina Volková")
  }

  func testVoiceCallPushRejectsUnknownAndIncompletePayloads() {
    XCTAssertNil(
      VoiceCallPushPayload(dictionary: [
        "callId": "b5ea7309-7f53-4e87-9225-fd38e9737540",
        "roomId": "!direct:msg.zeleznalady.cz",
        "type": "chat.voice_call.progress",
      ]))
    XCTAssertNil(
      VoiceCallPushPayload(dictionary: [
        "callId": "not-a-uuid",
        "roomId": "!direct:msg.zeleznalady.cz",
        "type": "chat.voice_call.incoming",
      ]))
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

  func testAuthenticatedMainFrameCanOpenNativeChat() async throws {
    var openedSubjects: [String?] = []
    let bridge = try makeBridge(openNativeChat: { openedSubjects.append($0) })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(
        method: "communications.openChat",
        sessionID: sessionID,
        params: ["subjectId": "subject-jirina"]
      ),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual((response["result"] as? [String: Any])?["opened"] as? Bool, true)
    XCTAssertEqual(openedSubjects.count, 1)
    XCTAssertEqual(openedSubjects.first!, "subject-jirina")
  }

  func testNativeOnlyChatCanOpenWithoutWebIdentity() async throws {
    var openedSubjects: [String?] = []
    let bridge = try makeBridge(openNativeChat: { openedSubjects.append($0) })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(
        method: "communications.openChat",
        sessionID: sessionID,
        params: [:]
      ),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, true)
    XCTAssertEqual((response["result"] as? [String: Any])?["opened"] as? Bool, true)
    XCTAssertEqual(openedSubjects.count, 1)
    XCTAssertNil(openedSubjects.first!)
  }

  func testNativeChatRejectsUnexpectedIdentityFields() async throws {
    var opened = 0
    let bridge = try makeBridge(openNativeChat: { _ in opened += 1 })
    bridge.navigationDidCommit(url: productionURL)
    let ready = await bridge.handle(message: hello(), context: allowedContext())
    let sessionID = try XCTUnwrap(ready["sessionId"] as? String)

    let response = await bridge.handle(
      message: request(
        method: "communications.openChat",
        sessionID: sessionID,
        params: ["subjectId": "subject-jirina", "token": "forbidden"]
      ),
      context: allowedContext())

    XCTAssertEqual(response["ok"] as? Bool, false)
    XCTAssertEqual(opened, 0)
  }

  private func makeBridge(
    location: DeviceLocationProviding? = nil,
    notifications: PushNotificationProviding? = nil,
    isForeground: @escaping () -> Bool = { true },
    openNativeChat: @escaping (String?) -> Void = { _ in }
  ) throws -> DeviceBridgeCoordinator {
    let origin = try WebOrigin(configurationValue: "https://cop.zeleznalady.cz")
    let policy = OriginPolicy(bridgeOrigins: [origin], navigationOrigins: [origin])
    return DeviceBridgeCoordinator(
      originPolicy: policy,
      location: location ?? FakeLocationProvider(),
      notifications: notifications ?? FakeNotificationProvider(),
      isForeground: isForeground,
      openNativeChat: openNativeChat)
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
  private var eventReceiverOwnerID: UUID?
  private var eventReceiver: ((String, [String: Any]) -> Void)?

  func attachEventReceiver(
    ownerID: UUID,
    receiver: @escaping (String, [String: Any]) -> Void
  ) {
    eventReceiverOwnerID = ownerID
    eventReceiver = receiver
  }

  func detachEventReceiver(ownerID: UUID) {
    guard eventReceiverOwnerID == ownerID else { return }
    eventReceiverOwnerID = nil
    eventReceiver = nil
  }

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
  var permissionAfterAuthorizationRequest: String?
  var reducedAccuracy = false
  var locationAvailable = true
  var headingAvailable = true
  var authorizationRequestCount = 0
  var stopAllCount = 0
  private var locationReceiver: (([String: Any]) -> Void)?

  func requestWhenInUseAuthorization() async -> String {
    authorizationRequestCount += 1
    if let permissionAfterAuthorizationRequest {
      permission = permissionAfterAuthorizationRequest
    }
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
