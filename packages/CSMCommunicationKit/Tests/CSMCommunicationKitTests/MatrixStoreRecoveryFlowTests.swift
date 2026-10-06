import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class MatrixStoreRecoveryFlowTests: XCTestCase {
    func testForegroundTokenRefreshRestartsSelectedConversationEvenIfOldTransportDoesNotFinish() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let api = StoreRecoveryAPI(shortTokenLifetime: true)
        let live = StreamLifecycleMessaging(finishOnConfigure: false)
        let model = makeModel(api: api, messaging: live, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        let conversations = try await api.conversations()
        let conversation = try XCTUnwrap(conversations.first)
        await model.selectConversation(conversation)
        for _ in 0..<200 {
            if await live.activeCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let before = await live.subscriptionCount
        await model.appDidBecomeActive()
        for _ in 0..<200 {
            if await live.subscriptionCount > before, await live.activeCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let configured = await live.configurationCount
        XCTAssertGreaterThan(configured, 1)
        XCTAssertEqual(model.selectedConversation?.conversationId, conversation.conversationId)
        await live.emit(id: "$after-foreground-refresh", conversation: conversation)
        for _ in 0..<200 {
            if model.messages.contains(where: { $0.id == "$after-foreground-refresh" }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.messages.contains { $0.id == "$after-foreground-refresh" })
        let active = await live.activeCount
        XCTAssertEqual(active, 1)
        await model.signOut()
    }

    func testSupersededConfigureDoesNotSuspendNewerSelectedStream() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let api = StoreRecoveryAPI()
        let live = StreamLifecycleMessaging()
        let model = makeModel(api: api, messaging: live, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        let conversations = try await api.conversations()
        let conversation = try XCTUnwrap(conversations.first)
        await model.selectConversation(conversation)
        var a = try await api.messagingBootstrap(deviceId: "synthetic-device")
        a.accessToken = "synthetic-a"
        var b = a; b.accessToken = "synthetic-b"
        let pause = StreamConfigurationPause()
        await live.armConfigurationPause(pause)
        let old = Task { await model.configureMessagingTransport(with: a, statusText: "online") }
        await pause.waitUntilEntered()
        let fresh = await model.configureMessagingTransport(with: b, statusText: "online")
        XCTAssertTrue(fresh)
        await pause.release()
        let staleResult = await old.value
        XCTAssertFalse(staleResult)
        let suspends = await live.suspendCount
        XCTAssertEqual(suspends, 0)
        for _ in 0..<200 {
            if await live.activeCount == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await live.emit(id: "$newer-still-live", conversation: conversation)
        for _ in 0..<200 {
            if model.messages.contains(where: { $0.id == "$newer-still-live" }) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.messages.contains { $0.id == "$newer-still-live" })
        await model.signOut()
    }

    func testSignOutInvalidatesDeferredConfigureWithoutRestartingChatOrPusher() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let api = StoreRecoveryAPI()
        let live = StreamLifecycleMessaging()
        let push = RecoveryFlowPush(snapshot: MobilePushSnapshot(authorization: .authorized,
            deviceToken: "synthetic-apns-token", environment: "sandbox", registrationRequestedAt: .now, lastFailure: nil))
        let model = makeModel(api: api, messaging: live, cache: StoreRecoveryBootstrapCache(), defaults: defaults, push: push)
        await model.start()
        let initialPushers = await live.pusherCount
        XCTAssertGreaterThan(initialPushers, 0, "The signed-in baseline must be able to register a pusher.")
        let bootstrap = try await api.messagingBootstrap(deviceId: "synthetic-device")
        let pause = StreamConfigurationPause()
        await live.armConfigurationPause(pause)
        let old = Task { await model.configureMessagingTransport(with: bootstrap, statusText: "online") }
        await pause.waitUntilEntered()
        await model.signOut()
        await pause.release()
        let result = await old.value
        XCTAssertFalse(result)
        XCTAssertEqual(model.authState, .signedOut)
        XCTAssertNil(model.selectedConversation)
        let active = await live.activeCount
        let pushers = await live.pusherCount
        XCTAssertEqual(active, 0)
        XCTAssertEqual(pushers, initialPushers)
    }

    func test401RefreshesSameDeviceWithoutCryptoRecovery() async throws {
        let api = StoreRecoveryAPI()
        let live = StoreRecoveryMessaging(failure: MatrixAPIError.httpError(401, "M_UNKNOWN_TOKEN"), failOnlyOnce: true)
        let cache = StoreRecoveryBootstrapCache(cached: true)
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let model = makeModel(api: api, messaging: live, cache: cache, defaults: defaults)
        await model.start()
        let configuredIDs = await live.configuredIDs
        XCTAssertEqual(configuredIDs.count, 2)
        XCTAssertEqual(Set(configuredIDs).count, 1)
        let requested = await api.requestedDevices
        XCTAssertEqual(requested.count, 1)
        XCTAssertEqual(requested.first?.1, configuredIDs.first)
        XCTAssertNil(model.matrixLocalStoreFailure)
        let recoveries = await live.recoveries
        XCTAssertEqual(recoveries, 0)
        XCTAssertTrue(try recoveryRecords(defaults).isEmpty)
    }

    func testConfirmedRecoveryPreservesEncryptedOutboxAndStableSelectionWhenCacheSaveFails() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cop-recovery-flow-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = EncryptedMessageOutbox(keychain: KeychainCredentialStore(service: "synthetic-unused"),
            rootDirectory: root, fixedKeyData: Data(repeating: 9, count: 32))
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        let pending = ChatMessage(id: "synthetic-pending", roomId: conversation.conversationId,
            senderId: "synthetic-sender", senderDisplayName: "Synthetic", body: "Synthetic draft",
            reactions: [], sentAt: .now, deliveryState: .pending, isOwnMessage: true)
        try await outbox.enqueue(pending, conversation: conversation)
        let api = StoreRecoveryAPI()
        let live = StoreRecoveryMessaging()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        let cache = StoreRecoveryBootstrapCache(failSaves: true)
        let model = makeModel(api: api, messaging: wrapper, cache: cache, defaults: defaults, outbox: outbox)
        await model.start()
        XCTAssertEqual(model.matrixLocalStoreFailure, .cipherMismatch)
        do { try await model.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: false); XCTFail("Confirmation required") }
        catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .recoveryRequired) }
        try await model.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: true)
        XCTAssertNil(model.matrixLocalStoreFailure)
        let records = try recoveryRecords(defaults)
        let selected = try XCTUnwrap(records.first?.selectedDeviceID)
        XCTAssertEqual(records.count, 1)
        let remaining = try await outbox.pendingMessages(for: conversation.conversationId)
        XCTAssertEqual(remaining.map(\.id), [pending.id])
        let healthy = StoreRecoveryMessaging(failure: nil)
        let restarted = makeModel(api: api, messaging: healthy, cache: cache, defaults: defaults)
        await restarted.start()
        let restartedIDs = await healthy.configuredIDs
        XCTAssertEqual(restartedIDs.last, selected)
        XCTAssertEqual(try recoveryRecords(defaults).first?.selectedDeviceID, selected)
        let requests = await api.requestedDevices
        XCTAssertEqual(requests.suffix(2).map(\.1), [selected, selected])
    }

    func testTwoAccountsHaveIndependentDeviceRecoveryAndBootstrapCacheScopes() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let aAPI = StoreRecoveryAPI(subject: "account-a")
        let aLive = StoreRecoveryMessaging()
        let aCache = StoreRecoveryBootstrapCache()
        let a = makeModel(api: aAPI, messaging: aLive, cache: aCache, defaults: defaults)
        await a.start()
        try await a.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: true)
        let bAPI = StoreRecoveryAPI(subject: "account-b")
        let bLive = StoreRecoveryMessaging()
        let bCache = StoreRecoveryBootstrapCache()
        let b = makeModel(api: bAPI, messaging: bLive, cache: bCache, defaults: defaults)
        await b.start()
        try await b.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: true)
        let aIDs = await aLive.configuredIDs
        let bIDs = await bLive.configuredIDs
        XCTAssertTrue(Set(aIDs).isDisjoint(with: Set(bIDs)))
        let records = try recoveryRecords(defaults)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(Set(records.compactMap(\.selectedDeviceID)).count, 2)
        let aSaved = await aCache.savedSubjects
        let bSaved = await bCache.savedSubjects
        XCTAssertEqual(Set(aSaved), ["account-a"])
        XCTAssertEqual(Set(bSaved), ["account-b"])
    }

    func testChangingAccountDuringRecoveryNeverCommitsOldActorOrPublishesReady() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let pause = RecoveryFlowPause()
        let api = StoreRecoveryAPI(subject: "account-a")
        let live = StoreRecoveryMessaging(pause: pause)
        let model = makeModel(api: api, messaging: live, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        let recovery = Task { try await model.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: true) }
        await pause.waitUntilEntered()
        await model.signOut()
        await api.changeSubject("account-b")
        await model.signIn()
        await pause.release()
        do { try await recovery.value; XCTFail("Old actor recovery must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(model.actor?.subjectId, "account-b")
        XCTAssertTrue(try recoveryRecords(defaults).allSatisfy { $0.selectedDeviceID == nil })
        let suspended = await live.suspended
        XCTAssertGreaterThanOrEqual(suspended, 1)
        let users = await live.configuredUsers
        XCTAssertEqual(users.last, "@account-b:matrix.test")
    }

    func testModelKeepsKnownStoreFailureAcrossLater503AndClearsAfterSuccessfulOpen() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let live = StoreRecoveryMessaging()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        let model = makeModel(api: StoreRecoveryAPI(), messaging: wrapper, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        XCTAssertEqual(model.matrixLocalStoreFailure, .cipherMismatch)
        await live.setFailure(MatrixAPIError.httpError(503, "synthetic"))
        await model.appDidBecomeActive()
        XCTAssertEqual(model.matrixLocalStoreFailure, .cipherMismatch)
        XCTAssertTrue(try recoveryRecords(defaults).isEmpty)
        await live.setFailure(nil)
        await model.appDidBecomeActive()
        XCTAssertNil(model.matrixLocalStoreFailure)
        let count = await live.recoveries
        XCTAssertEqual(count, 0)
    }

    func testImplicitReopenReachesModelWithoutAnInjectedModelOutbox() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let live = StoreRecoveryMessaging(failure: MatrixAPIError.httpError(503, "synthetic"))
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        let model = makeModel(api: StoreRecoveryAPI(), messaging: wrapper, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        XCTAssertNil(model.matrixLocalStoreFailure)
        await live.setFailure(MatrixLocalStoreError(failure: .missingKey))
        let conversations = try await PreviewCopAPIClient().conversations()
        await model.selectConversation(try XCTUnwrap(conversations.first))
        XCTAssertEqual(model.matrixLocalStoreFailure, .missingKey)
        XCTAssertTrue(try recoveryRecords(defaults).isEmpty)
        let count = await live.recoveries
        XCTAssertEqual(count, 0)
    }

    func testAccountChangeClearsPriorFailureWithoutClaimingHealthyChat() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let api = StoreRecoveryAPI()
        let live = StoreRecoveryMessaging()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        let model = makeModel(api: api, messaging: wrapper, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        XCTAssertEqual(model.matrixLocalStoreFailure, .cipherMismatch)
        await model.signOut()
        await api.changeSubject("account-b")
        await live.setFailure(MatrixAPIError.httpError(503, "synthetic"))
        await model.signIn()
        XCTAssertEqual(model.actor?.subjectId, "account-b")
        XCTAssertNil(model.matrixLocalStoreFailure)
        XCTAssertEqual(model.messagingStatusText, "e2ee_queue")
        XCTAssertTrue(try recoveryRecords(defaults).isEmpty)
    }

    func testDelayedDiagnosticCannotRestoreFailureAfterNewSuccessfulConfigure() async throws {
        let defaults = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let live = DelayedDiagnosticMessaging()
        let model = makeModel(api: StoreRecoveryAPI(), messaging: live, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
        await model.start()
        XCTAssertEqual(model.matrixLocalStoreFailure, .cipherMismatch)
        let pause = RecoveryFlowPause()
        await live.arm(pause)
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        let refresh = Task { await model.selectConversation(conversation) }
        await pause.waitUntilEntered()
        await live.allowSuccessfulOpen()
        await model.appDidBecomeActive()
        XCTAssertNil(model.matrixLocalStoreFailure)
        await pause.release()
        await refresh.value
        XCTAssertNil(model.matrixLocalStoreFailure, "An older same-scope snapshot must not undo a newer verified open")
    }

    func testFresh503AndLockedKeychainDoNotAuthorizeLocalReset() async throws {
        for failure in [MatrixAPIError.httpError(503, "synthetic") as any Error, MatrixLocalStoreError(failure: .deviceLocked)] {
            let defaults = try isolatedDefaults()
            defer { defaults.removePersistentDomain(forName: defaultsSuite) }
            let live = StoreRecoveryMessaging(failure: failure)
            let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
            let model = makeModel(api: StoreRecoveryAPI(), messaging: wrapper, cache: StoreRecoveryBootstrapCache(), defaults: defaults)
            await model.start()
            if let typed = model.matrixLocalStoreFailure {
                XCTAssertEqual(typed, .deviceLocked)
                XCTAssertFalse(MatrixLocalStoreError(failure: typed).permitsRecovery)
            } else { XCTAssertTrue(failure is MatrixAPIError) }
            do { try await model.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: true); XCTFail("No reset permitted") }
            catch { XCTAssertNotNil(error as? MatrixLocalStoreError) }
            let count = await live.recoveries
            XCTAssertEqual(count, 0)
            XCTAssertTrue(try recoveryRecords(defaults).isEmpty)
        }
    }

    private var defaultsSuite = ""
    private func isolatedDefaults() throws -> UserDefaults {
        defaultsSuite = "cop.recovery-flow-tests." + UUID().uuidString
        return try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
    }
    private func recoveryRecords(_ defaults: UserDefaults) throws -> [MatrixDeviceRecoveryRouting.Record] {
        try defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("cz.voldzi.cop.matrix-store-recovery.") }
            .values.compactMap { $0 as? Data }.map { try JSONDecoder().decode(MatrixDeviceRecoveryRouting.Record.self, from: $0) }
    }
    private func makeModel(api: StoreRecoveryAPI, messaging: any MessagingClientProtocol,
                           cache: StoreRecoveryBootstrapCache, defaults: UserDefaults,
                           outbox: (any MessageOutboxStoring)? = nil,
                           push: RecoveryFlowPush? = nil) -> CommunicationModel {
        CommunicationModel(api: api, messaging: messaging, messageOutbox: outbox, messagingBootstrapStore: cache,
            localAI: DeterministicLocalAIService(), pushNotifications: push ?? RecoveryFlowPush(), authSession: RecoveryFlowAuth(),
            securityUnlock: PreviewSecurityUnlock(), matrixRecoveryDefaults: defaults, allowsChatRecoveryWithoutBackup: true)
    }
}

private actor StoreRecoveryBootstrapCache: MessagingBootstrapStoring {
    let cached: Bool
    let failSaves: Bool
    private(set) var savedSubjects: [String] = []
    init(cached: Bool = false, failSaves: Bool = false) { self.cached = cached; self.failSaves = failSaves }
    func load(subjectId: String, deviceId: String) async throws -> MessagingBootstrap? {
        guard cached else { return nil }
        var value = try await PreviewCopAPIClient().messagingBootstrap(deviceId: deviceId)
        value.userId = "@account-a:matrix.test"; value.homeserverBaseUrl = URL(string: "https://matrix.test")!
        return value
    }
    func save(_ bootstrap: MessagingBootstrap, subjectId: String, deviceId: String) throws {
        savedSubjects.append(subjectId)
        if failSaves { throw MatrixLocalStoreError(failure: .deviceLocked) }
    }
    func clear(subjectId: String, deviceId: String?) {}
}
private actor StoreRecoveryMessaging: MessagingClientProtocol, MatrixLocalStoreRecovering, MessagingLifecycleControlling {
    private var failure: (any Error)?
    let failOnlyOnce: Bool
    let pause: RecoveryFlowPause?
    private var recovered = false
    private(set) var configuredIDs: [String] = []
    private(set) var configuredUsers: [String] = []
    private(set) var recoveries = 0
    private(set) var suspended = 0
    init(failure: (any Error)? = MatrixLocalStoreError(failure: .cipherMismatch), failOnlyOnce: Bool = false, pause: RecoveryFlowPause? = nil) {
        self.failure = failure; self.failOnlyOnce = failOnlyOnce; self.pause = pause
    }
    func setFailure(_ value: (any Error)?) { failure = value }
    func configure(with bootstrap: MessagingBootstrap) throws {
        configuredIDs.append(bootstrap.deviceId ?? "missing"); configuredUsers.append(bootstrap.userId ?? "missing")
        if !recovered, let failure { if failOnlyOnce { self.failure = nil }; throw failure }
    }
    func recoverLocalStore(from previous: MessagingBootstrap, with bootstrap: MessagingBootstrap, authorization: CSMChatStoreRecoveryAuthorization) async throws {
        guard previous.deviceId != bootstrap.deviceId, previous.userId == bootstrap.userId else { throw MatrixLocalStoreError(failure: .deviceIdentityMismatch) }
        recoveries += 1
        await pause?.enterAndWait()
        recovered = true
        configuredIDs.append(bootstrap.deviceId ?? "missing"); configuredUsers.append(bootstrap.userId ?? "missing")
    }
    func resumeMessaging() {}
    func suspendMessaging() { suspended += 1 }
    func messages(for conversation: Conversation) -> [ChatMessage] { [] }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { throw MatrixAPIError.missingBootstrap }
}
private actor RecoveryFlowPause {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func enterAndWait() async {
        entered = true
        entryWaiter?.resume(); entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}
@MainActor private final class RecoveryFlowAuth: AuthSessionManaging {
    func canUseExistingSession() async -> Bool { true }
    func signIn() async throws {}
    func signOut() async throws {}
}
@MainActor private final class RecoveryFlowPush: PushNotificationManaging {
    var currentSnapshot: MobilePushSnapshot
    init(snapshot: MobilePushSnapshot = .unavailable) { currentSnapshot = snapshot }
    func prepareForRemoteNotifications() async -> MobilePushSnapshot { currentSnapshot }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}

private actor StoreRecoveryAPI: CopAPIClientProtocol {
    private var subject: String
    private(set) var requestedDevices: [(String, String)] = []
    let shortTokenLifetime: Bool
    init(subject: String = "account-a", shortTokenLifetime: Bool = false) {
        self.subject = subject; self.shortTokenLifetime = shortTokenLifetime
    }
    func changeSubject(_ value: String) { subject = value }
    func bootstrap(seconds: Int) async throws -> MobileBootstrap {
        var value = try await PreviewCopAPIClient().bootstrap(seconds: seconds)
        value.actor = AuthenticatedActor(subjectId: subject, username: subject, displayName: "Synthetic", roles: ["user"])
        return value
    }
    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap {
        requestedDevices.append((subject, deviceId))
        var value = try await PreviewCopAPIClient().messagingBootstrap(deviceId: deviceId)
        value.userId = "@" + subject + ":matrix.test"; value.homeserverBaseUrl = URL(string: "https://matrix.test")!
        if shortTokenLifetime {
            value.expiresAt = .now.addingTimeInterval(60)
            value.accessToken = "synthetic-token-" + String(requestedDevices.count)
        }
        return value
    }
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

private actor DelayedDiagnosticMessaging: MessagingClientProtocol, MessagingLocalStoreDiagnosing {
    private var failure: CSMChatLocalStoreFailure? = .cipherMismatch
    private var pause: RecoveryFlowPause?
    private var last: MessagingBootstrap?
    func arm(_ value: RecoveryFlowPause) { pause = value }
    func allowSuccessfulOpen() { failure = nil }
    func configure(with bootstrap: MessagingBootstrap) throws {
        last = bootstrap
        if let failure { throw MatrixLocalStoreError(failure: failure) }
    }
    func localStoreDiagnostic(for bootstrap: MessagingBootstrap) async -> MatrixLocalStoreDiagnostic? {
        guard last.flatMap(MatrixLocalStoreScope.init) == MatrixLocalStoreScope(bootstrap) else { return nil }
        let captured = MatrixLocalStoreDiagnostic(failure: failure, isVerifiedOpen: failure == nil)
        if let pause { self.pause = nil; await pause.enterAndWait() }
        return captured
    }
    func messages(for conversation: Conversation) -> [ChatMessage] { [] }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { throw MatrixAPIError.missingBootstrap }
}
