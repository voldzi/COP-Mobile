import XCTest
@testable import CSMCommunicationKit

@MainActor
final class EmbeddedCommunicationSurfaceTests: XCTestCase {
    func testVerifiedIdentitySurfaceDoesNotWaitForPushRegistrationToComplete() async throws {
        let push = PausingSurfacePush()
        let model = CommunicationModel(api: SurfaceBootstrapAPI(), messaging: PreviewMessagingClient(),
            localAI: DeterministicLocalAIService(), pushNotifications: push,
            authSession: PreviewAuthSession(hasExistingSession: true), securityUnlock: PreviewSecurityUnlock())
        let runtime = CSMCommunicationRuntime(model: model)
        let start = Task { await runtime.startIfNeeded() }
        let reachedPush = await push.waitUntilPreparing()
        guard reachedPush else { start.cancel(); XCTFail("Push preparation not reached"); return }
        XCTAssertEqual(model.authState, .signedIn)
        XCTAssertNotNil(model.actor)
        XCTAssertFalse(model.isLoading, "Verified identity must not wait for a notification service")
        XCTAssertEqual(runtime.surfaceAccessState(expectedSubjectID: nil), .ready)
        XCTAssertEqual(runtime.surfaceAccessState(expectedSubjectID: "other-account"), .accountMismatch)
        push.resume()
        await start.value
        await model.signOut()
    }

    func testSurfaceResolvesCompletedWarmStartDespiteStalePreparationState() async throws {
        let model = CommunicationModel(api: PreviewCopAPIClient(), messaging: PreviewMessagingClient(),
            localAI: DeterministicLocalAIService(), pushNotifications: SurfacePush(),
            authSession: PreviewAuthSession(hasExistingSession: true), securityUnlock: PreviewSecurityUnlock())
        let runtime = CSMCommunicationRuntime(model: model)
        // Registration/host-independent warmup starts the actual model before
        // any mounted host prepare refreshes the cached accessState.
        await runtime.startIfNeeded()
        XCTAssertEqual(runtime.accessState, .checking)
        XCTAssertEqual(model.authState, .signedIn)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(runtime.surfaceAccessState(expectedSubjectID: nil), .ready)
        XCTAssertEqual(runtime.surfaceAccessState(expectedSubjectID: "different-synthetic-account"), .accountMismatch)
        await model.signOut()
        XCTAssertEqual(runtime.surfaceAccessState(expectedSubjectID: nil), .signInRequired)
    }
}

@MainActor private final class SurfacePush: PushNotificationManaging {
    var currentSnapshot = MobilePushSnapshot.unavailable
    func prepareForRemoteNotifications() async -> MobilePushSnapshot { currentSnapshot }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}

private actor SurfaceBootstrapAPI: CopAPIClientProtocol {
    func bootstrap(seconds: Int) async throws -> MobileBootstrap {
        var value = try await PreviewCopAPIClient().bootstrap(seconds: seconds)
        value.capabilities.pushNotifications = true
        return value
    }
    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap { try await PreviewCopAPIClient().messagingBootstrap(deviceId: deviceId) }
    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int) async throws -> [CSMVoiceCall] { [] }
    func drivingCapabilities() async throws -> CSMDriverRoutingCatalog { return try await PreviewCopAPIClient().drivingCapabilities() }
    func drivingRoutes(_ request: CSMDriverRouteRequest) async throws -> CSMDriverRouteResponse { return try await PreviewCopAPIClient().drivingRoutes(request) }
    func offlineSnapshot(seconds: Int) async throws -> MobileOfflineSnapshot { return try await PreviewCopAPIClient().offlineSnapshot(seconds: seconds) }
    func mapCatalog(locale: String, includeDiagnostics: Bool, includePartner: Bool) async throws -> MapLayerCatalog { return try await PreviewCopAPIClient().mapCatalog(locale: locale, includeDiagnostics: includeDiagnostics, includePartner: includePartner) }
    func mapFeatures(_ request: MapFeatureQueryRequest) async throws -> MapFeatureQueryResponse { return try await PreviewCopAPIClient().mapFeatures(request) }
    func transitVehicleDetail(featureId: String, sourceId: String?) async throws -> TransitVehicleDetail { return try await PreviewCopAPIClient().transitVehicleDetail(featureId: featureId, sourceId: sourceId) }
    func mapRasterOverlayImage(url: String) async throws -> Data { return try await PreviewCopAPIClient().mapRasterOverlayImage(url: url) }
    func weatherWebcamResource(url: String) async throws -> Data { return try await PreviewCopAPIClient().weatherWebcamResource(url: url) }
    func weatherRadarFrames(product: String, hours: Int, limit: Int) async throws -> WeatherRadarFrameCatalog { return try await PreviewCopAPIClient().weatherRadarFrames(product: product, hours: hours, limit: limit) }
    func sketchPalettes() async throws -> SketchPaletteCatalog { return try await PreviewCopAPIClient().sketchPalettes() }
    func sketchDrawings(bbox: MapFeatureBoundingBox?, limit: Int) async throws -> SketchDrawingCollection { return try await PreviewCopAPIClient().sketchDrawings(bbox: bbox, limit: limit) }
    func sketchDrawing(drawingId: String) async throws -> SketchDrawing { return try await PreviewCopAPIClient().sketchDrawing(drawingId: drawingId) }
    func createSketchDrawing(_ request: SketchDrawingCreateRequest) async throws -> SketchDrawing { return try await PreviewCopAPIClient().createSketchDrawing(request) }
    func updateSketchDrawing(drawingId: String, request: SketchDrawingUpdateRequest) async throws -> SketchDrawing { return try await PreviewCopAPIClient().updateSketchDrawing(drawingId: drawingId, request: request) }
    func deleteSketchDrawing(drawingId: String) async throws { try await PreviewCopAPIClient().deleteSketchDrawing(drawingId: drawingId) }
    func userPreferenceProfile() async throws -> UserPreferenceProfile { return try await PreviewCopAPIClient().userPreferenceProfile() }
    func updateUserPreferences(_ update: UserPreferenceUpdate) async throws -> UserPreferenceProfile { return try await PreviewCopAPIClient().updateUserPreferences(update) }
    func alerts(includeAcknowledged: Bool) async throws -> [CopAlert] { return try await PreviewCopAPIClient().alerts(includeAcknowledged: includeAcknowledged) }
    func acknowledgeAlert(alertId: String, note: String?) async throws -> CopAlert { return try await PreviewCopAPIClient().acknowledgeAlert(alertId: alertId, note: note) }
    func messagingStatus() async throws -> MessagingStatus { return try await PreviewCopAPIClient().messagingStatus() }
    func messagingIdentityLookup(conversationId: String) async throws -> MessagingIdentityLookup { return try await PreviewCopAPIClient().messagingIdentityLookup(conversationId: conversationId) }
    func startVoiceCall(_ request: CSMVoiceCallStartRequest) async throws -> CSMVoiceCallSession { return try await PreviewCopAPIClient().startVoiceCall(request) }
    func voiceCall(callId: String) async throws -> CSMVoiceCallSession { return try await PreviewCopAPIClient().voiceCall(callId: callId) }
    func transitionVoiceCall(callId: String, request: CSMVoiceCallActionRequest) async throws -> CSMVoiceCallSession { return try await PreviewCopAPIClient().transitionVoiceCall(callId: callId, request: request) }
    func mobilePairingSession(code: String) async throws -> MobilePairingSessionResponse { return try await PreviewCopAPIClient().mobilePairingSession(code: code) }
    func claimMobilePairingSession(code: String, request: MobilePairingClaimRequest) async throws -> MobilePairingSessionResponse { return try await PreviewCopAPIClient().claimMobilePairingSession(code: code, request: request) }
    func conversations() async throws -> [Conversation] { return try await PreviewCopAPIClient().conversations() }
    func queryAIChatAgent(_ request: CopAIChatAgentRequest) async throws -> CopAIChatAgentResponse { return try await PreviewCopAPIClient().queryAIChatAgent(request) }
    func registerDevice(_ registration: MobileDeviceRegistration) async throws -> MobileDeviceRegistrationResponse { return try await PreviewCopAPIClient().registerDevice(registration) }
    func deviceRegistrationTicket(appInstanceId: String, bundleId: String) async throws -> MobileDeviceRegistrationTicketResponse { return try await PreviewCopAPIClient().deviceRegistrationTicket(appInstanceId: appInstanceId, bundleId: bundleId) }
    func submitCommunityReport(_ draft: CommunityReportDraft) async throws -> CommunityReportSubmission { return try await PreviewCopAPIClient().submitCommunityReport(draft) }
    func communityReports(query: DriverReportQuery?) async throws -> [CommunityReport] { return try await PreviewCopAPIClient().communityReports(query: query) }
    func confirmCommunityReport(reportId: String, value: CommunityReportConfirmationValue) async throws -> CommunityReport { return try await PreviewCopAPIClient().confirmCommunityReport(reportId: reportId, value: value) }
}
@MainActor private final class PausingSurfacePush: PushNotificationManaging {
    var currentSnapshot = MobilePushSnapshot.unavailable
    private var preparing = false
    private var release: CheckedContinuation<Void, Never>?
    func waitUntilPreparing() async -> Bool {
        for _ in 0..<100 {
            if preparing { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
    func resume() { release?.resume(); release = nil }
    func prepareForRemoteNotifications() async -> MobilePushSnapshot {
        preparing = true
        await withCheckedContinuation { release = $0 }
        return currentSnapshot
    }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}
