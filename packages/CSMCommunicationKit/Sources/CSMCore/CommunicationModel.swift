import CryptoKit
import Foundation
import Observation
import OSLog

enum ConversationListLoadState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
final class CommunicationModel {
    private static let diagnostics = Logger(
        subsystem: "cz.zeleznalady.csm.messenger",
        category: "communication"
    )
    private static let deviceRegistrationDiagnosticStatusKey =
        "cz.zeleznalady.csm.deviceRegistrationDiagnosticStatus"
    private static let deviceRegistrationDiagnosticUpdatedAtKey =
        "cz.zeleznalady.csm.deviceRegistrationDiagnosticUpdatedAt"
    let chatSessionStore = ChatSessionStore()
    let conversationListStore = ConversationListStore()
    let timelineStore = TimelineStore()
    @ObservationIgnored private let timelineSynchronization = TimelineSynchronizationController()

    /// Matrix device-id generation for the native Rust E2EE adapter.
    ///
    /// Builds before 0.1.26 used the same deterministic Matrix device id while
    /// the pilot E2EE adapter was still changing its local crypto-store
    /// behavior. Keeping the same physical-device binding but advancing this
    /// generation gives affected phones a clean Matrix device and store without
    /// changing the server contract or storing secrets in the app.
    private static let matrixDeviceGeneration = "matrix-rust-e2ee-v7"
    private static let matrixInstallationSeedStorageKey = "cz.zeleznalady.csm.matrixInstallationSeed"
    private static let aiAssistantUserId = "cop.ai.agent"
    private static let aiAssistantDisplayName = "COP AI Assistant"

    private(set) var authState: AuthState {
        get { chatSessionStore.snapshot.authState }
        set {
            chatSessionStore.update(
                authState: newValue,
                actor: actor,
                isBusy: isLoading,
                deviceID: messagingDeviceId
            )
        }
    }
    private(set) var connectionMode: ConnectionMode = .offline
    private(set) var actor: AuthenticatedActor? {
        get { chatSessionStore.snapshot.actor }
        set {
            chatSessionStore.update(
                authState: authState,
                actor: newValue,
                isBusy: isLoading,
                deviceID: messagingDeviceId
            )
        }
    }
    private(set) var policy: MobileNativePolicy?
    private(set) var userProfile: UserProfile?
    private(set) var conversations: [Conversation] {
        get { conversationListStore.snapshot.conversations }
        set {
            ChatPerformance.measure(
                "conversation-list-local",
                budgetMilliseconds: ChatPerformanceBudget.localConversationListMilliseconds
            ) {
                conversationListStore.replace(
                    newValue,
                    selection: selectedConversation,
                    loadState: conversationListLoadState
                )
            }
        }
    }
    private(set) var selectedConversation: Conversation? {
        get { conversationListStore.snapshot.selectedConversation }
        set { conversationListStore.setSelection(newValue) }
    }
    private(set) var pinnedConversationId: String?
    private(set) var chatPreferences: ChatConversationPreferences = .empty
    private(set) var messages: [ChatMessage] {
        get { timelineStore.state.messages }
        set {
            timelineStore.send(
                .replaceRemote(
                    newValue,
                    hasEarlier: timelineStore.state.hasEarlierMessages
                )
            )
        }
    }
    private(set) var voiceCallTimelineMessages: [ChatMessage] {
        get { timelineStore.state.voiceCallMessages }
        set { timelineStore.send(.replaceVoiceCalls(newValue)) }
    }
    private(set) var loadingConversationId: String? {
        get {
            timelineStore.state.isLoading
                ? timelineStore.state.conversationID
                : nil
        }
        set {
            if let newValue {
                if timelineStore.state.conversationID != newValue {
                    timelineStore.send(.open(conversationID: newValue))
                } else {
                    timelineStore.send(.setLoading(true))
                }
            } else {
                timelineStore.send(.setLoading(false))
            }
        }
    }
    private(set) var pendingMessageCount = 0
    private(set) var matrixEncryptionRecoveryStatus: MatrixEncryptionRecoveryStatus = .notLoaded
    private(set) var matrixEncryptionRecoveryGeneratedKey: String?
    private(set) var matrixEncryptionRecoveryErrorText: String?
    private(set) var matrixEncryptionRecoveryErrorTechnicalDetail: String?
    private(set) var matrixEncryptionRecoveryWorking = false
    private(set) var localAIAvailability: LocalAIAvailability = .unavailable
    private(set) var pushSnapshot: MobilePushSnapshot = .unavailable
    private(set) var mobilePairingPresentation: MobilePairingPresentation?
    private(set) var devicePosture: MobileDevicePosture = .unknown
    private(set) var managedAppPolicy: MobileManagedAppPolicy = .unmanaged
    private(set) var deviceSessionId: String?
    private(set) var messagingDeviceId: String? {
        get { chatSessionStore.snapshot.deviceID }
        set {
            chatSessionStore.update(
                authState: authState,
                actor: actor,
                isBusy: isLoading,
                deviceID: newValue
            )
        }
    }
    private(set) var messagingDeviceRegistrationStatusText: String = "not_registered"
    var notificationPreferences: CSMNotificationPreferences = .default
    private(set) var notificationSubscriptions: CSMNotificationSubscriptions = .empty
    private(set) var lastError: String?
    private(set) var conversationActionStatusText: String?
    private(set) var conversationOperationErrorText: String?
    private(set) var conversationListLoadState: ConversationListLoadState {
        get { conversationListStore.snapshot.loadState }
        set { conversationListStore.setLoadState(newValue) }
    }
    private(set) var conversationListErrorText: String?
    private var conversationListRefreshGeneration = 0
    private(set) var aiAgentStatusText: String?
    private(set) var aiAgentStatusConversationId: String?
    private(set) var activeLiveLocationShare: ActiveLiveLocationShare?
    private(set) var messagingStatusText: String = "disabled"
    private(set) var conversationMetadataSourceText: String = "not_loaded"
    private(set) var messageOutboxSyncStatusText: String = "idle"
    private(set) var messagingTransportErrorText: String?
    private var messagingBootstrapExpiresAt: Date?
    private var messagingBootstrapIssuedAt: Date?
    private var lastMessagingBootstrap: MessagingBootstrap?
    private(set) var isLoading: Bool {
        get { chatSessionStore.snapshot.isBusy }
        set {
            chatSessionStore.update(
                authState: authState,
                actor: actor,
                isBusy: newValue,
                deviceID: messagingDeviceId
            )
        }
    }

    var messagingTrustPresentation: MessagingTrustPresentation {
        MessagingTrustPresentation.make(status: messagingStatusText, pendingCount: pendingMessageCount)
    }

    var appBuildText: String {
        "\(appConfiguration.appVersion) (\(appConfiguration.buildNumber)) \(appConfiguration.buildConfiguration)"
    }

    var messagingSendBlockedMessage: String? {
        if selectedConversationRequiresMatrixRecovery,
           matrixEncryptionRecoveryStatus.blocksSending {
            return matrixEncryptionRecoveryStatus.userMessage
        }
        let trust = messagingTrustPresentation
        return trust.blocksSending ? trust.userMessage : nil
    }

    var selectedConversationRequiresMatrixRecovery: Bool {
        guard let selectedConversation else { return false }
        return selectedConversation.e2eeRequired || selectedConversation.encrypted
    }

    var pinnedMessages: [ChatMessage] {
        messages
            .filter { $0.isPinned && !$0.isDeleted }
            .sorted { $0.sentAt > $1.sentAt }
    }

    var knownConversationRecipients: [ConversationRecipient] {
        Self.knownRecipients(actor: actor, conversations: conversations)
    }

    func searchConversationRecipients(
        matching query: String,
        excludingUserIds: Set<String> = [],
        limit: Int = 20
    ) async throws -> [ConversationRecipient] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2, let conversationMetadata else {
            return []
        }

        let directoryRecipients = try await conversationMetadata.searchUserDirectory(
            query: normalizedQuery,
            limit: limit
        )
        let blockedIds = Self.selfIdentifierSet(actor)
            .union(excludingUserIds.map(ConversationIdentity.canonicalKey))
        return Self.mergedRecipients(
            directoryRecipients.filter { recipient in
                let userId = ConversationIdentity.canonicalKey(recipient.userId)
                return !userId.isEmpty && !blockedIds.contains(userId)
            }
        )
    }

    func clearConversationOperationError() {
        conversationOperationErrorText = nil
    }

    var effectiveOperatorProfile: OperatorProfilePreferences {
        (userProfile?.operatorProfile ?? OperatorProfilePreferences())
            .mergedWithIdentity(actor: actor)
    }

    @ObservationIgnored private let appConfiguration: AppConfiguration
    @ObservationIgnored private let api: any CopAPIClientProtocol
    @ObservationIgnored private let messaging: any MessagingClientProtocol
    @ObservationIgnored private let messageOutbox: (any MessageOutboxStoring)?
    @ObservationIgnored private let messageHistory: (any MessageHistoryStoring)?
    @ObservationIgnored private let messagingBootstrapStore: (any MessagingBootstrapStoring)?
    @ObservationIgnored private let localAI: any LocalAIServiceProtocol
    @ObservationIgnored private let pushNotifications: any PushNotificationManaging
    @ObservationIgnored private let deviceRegistration: (any DeviceRegistrationProviding)?
    @ObservationIgnored private let devicePostureProvider: any DevicePostureProviding
    @ObservationIgnored private let messagingDeviceRegistration: (any CSMMessagingDeviceRegistering)?
    @ObservationIgnored private let conversationMetadata: (any ConversationMetadataProviding)?
    @ObservationIgnored private let authSession: any AuthSessionManaging
    @ObservationIgnored private let securityUnlock: any SecurityUnlockManaging
    @ObservationIgnored private var registeredMessagingDeviceTokenFingerprint: String?
    @ObservationIgnored private var registeredMatrixPusherTokenFingerprint: String?
    @ObservationIgnored private var registeredMatrixPusherGatewayURL: URL?
    @ObservationIgnored private var messagingTransportReadyForPusher = false
    @ObservationIgnored private var messagingBootstrapRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var mobilePairingConfirmationTask: Task<Void, Never>?
    @ObservationIgnored private var messagingBootstrapNetworkRetryNotBefore: Date?
    @ObservationIgnored private var pendingAutoSyncAttemptedConversationIds: Set<String> = []
    @ObservationIgnored private var pendingAutoSyncInFlightConversationIds: Set<String> = []
    @ObservationIgnored private var aiCurrentLocationProvider:
        (@MainActor @Sendable () async -> CopAIChatAgentLocation?)?
    @ObservationIgnored private var voipDeviceTokenProvider:
        (@MainActor @Sendable () async -> String?)?
    @ObservationIgnored private var liveLocationShareTask: Task<Void, Never>?
    @ObservationIgnored private var activeLiveLocationConversation: Conversation?

    init(
        appConfiguration: AppConfiguration = .preview,
        api: any CopAPIClientProtocol,
        messaging: any MessagingClientProtocol,
        messageOutbox: (any MessageOutboxStoring)? = nil,
        messageHistory: (any MessageHistoryStoring)? = nil,
        messagingBootstrapStore: (any MessagingBootstrapStoring)? = nil,
        localAI: any LocalAIServiceProtocol,
        pushNotifications: any PushNotificationManaging,
        deviceRegistration: (any DeviceRegistrationProviding)? = nil,
        devicePostureProvider: any DevicePostureProviding = SystemDevicePostureProvider.shared,
        messagingDeviceRegistration: (any CSMMessagingDeviceRegistering)? = nil,
        conversationMetadata: (any ConversationMetadataProviding)? = nil,
        authSession: any AuthSessionManaging,
        securityUnlock: any SecurityUnlockManaging
    ) {
        self.appConfiguration = appConfiguration
        self.api = api
        self.messaging = messaging
        self.messageOutbox = messageOutbox
        self.messageHistory = messageHistory
        self.messagingBootstrapStore = messagingBootstrapStore
        self.localAI = localAI
        self.pushNotifications = pushNotifications
        self.deviceRegistration = deviceRegistration
        self.devicePostureProvider = devicePostureProvider
        self.messagingDeviceRegistration = messagingDeviceRegistration
        self.conversationMetadata = conversationMetadata
        self.authSession = authSession
        self.securityUnlock = securityUnlock
    }

    func start() async {
        Self.recordDeviceRegistrationDiagnostic("runtime_starting")
        authState = .checking
        if await authSession.canUseExistingSession() {
            Self.recordDeviceRegistrationDiagnostic("session_restored")
            authState = .signedIn
            await bootstrapCommunication()
        } else {
            Self.recordDeviceRegistrationDiagnostic("session_signed_out")
            authState = .signedOut
            connectionMode = .offline
        }
    }

    func setAICurrentLocationProvider(
        _ provider: (@MainActor @Sendable () async -> CopAIChatAgentLocation?)?
    ) {
        aiCurrentLocationProvider = provider
    }

    func setVoIPDeviceTokenProvider(
        _ provider: (@MainActor @Sendable () async -> String?)?
    ) {
        voipDeviceTokenProvider = provider
    }

    func startVoiceCall(
        roomID: String,
        title: String?,
        participantSubjectIDs: [String]?
    ) async throws -> CSMVoiceCallSession {
        guard authState == .signedIn else {
            throw CSMVoiceCallControlError.authenticationRequired
        }
        return try await api.startVoiceCall(
            CSMVoiceCallStartRequest(
                participantSubjectIds: participantSubjectIDs,
                roomId: roomID,
                title: title
            )
        )
    }

    func voiceCall(callID: String) async throws -> CSMVoiceCallSession {
        guard authState == .signedIn else {
            throw CSMVoiceCallControlError.authenticationRequired
        }
        return try await api.voiceCall(callId: callID)
    }

    func activeVoiceCalls() async throws -> [CSMVoiceCall] {
        guard authState == .signedIn else {
            throw CSMVoiceCallControlError.authenticationRequired
        }
        return try await api.voiceCalls(roomId: nil, activeOnly: true, limit: 20)
    }

    func refreshVoiceCallTimeline(for conversation: Conversation) async {
        guard
            authState == .signedIn,
            conversation.type == .direct,
            !conversation.isAIAssistantConversation,
            let roomID = conversation.activeMatrixRoomId
        else {
            if selectedConversation?.conversationId == conversation.conversationId {
                voiceCallTimelineMessages = []
            }
            return
        }

        do {
            let calls = try await api.voiceCalls(roomId: roomID, activeOnly: false, limit: 100)
            guard selectedConversation?.conversationId == conversation.conversationId else { return }
            voiceCallTimelineMessages = calls
                .filter(\.phase.isTerminal)
                .map {
                    ChatMessagePresentationFactory.voiceCallMessage(
                        for: $0,
                        conversation: conversation,
                        actor: actor
                    )
                }
                .sorted { $0.sentAt < $1.sentAt }
        } catch {
            guard selectedConversation?.conversationId == conversation.conversationId else { return }
            // Hovorová historie je doplněk časové osy. Její dočasná
            // nedostupnost nesmí skrýt zprávy ani zobrazit technickou chybu.
            voiceCallTimelineMessages = []
        }
    }

    func transitionVoiceCall(
        callID: String,
        action: CSMVoiceCallAction,
        expectedRevision: Int?,
        reason: String?
    ) async throws -> CSMVoiceCallSession {
        guard authState == .signedIn else {
            throw CSMVoiceCallControlError.authenticationRequired
        }
        return try await api.transitionVoiceCall(
            callId: callID,
            request: CSMVoiceCallActionRequest(
                action: action,
                expectedRevision: expectedRevision,
                reason: reason
            )
        )
    }

    func signIn(forceAuthentication: Bool = false) async {
        authState = .signingIn
        isLoading = true
        defer { isLoading = false }
        do {
            try await authSession.signIn(forceAuthentication: forceAuthentication)
            authState = .signedIn
            await bootstrapCommunication()
        } catch {
            authState = .signedOut
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        try? await stopLiveLocationShare()
        if let messagingDeviceId, let messagingDeviceRegistration {
            try? await messagingDeviceRegistration.deleteDevice(deviceId: messagingDeviceId)
        }
        if let actor {
            await clearCachedMessagingBootstrap(for: actor)
        }
        do {
            try await authSession.signOut()
        } catch {
            lastError = error.localizedDescription
        }
        actor = nil
        policy = nil
        userProfile = nil
        conversations = []
        conversationListRefreshGeneration &+= 1
        conversationListLoadState = .notLoaded
        conversationListErrorText = nil
        conversationOperationErrorText = nil
        selectedConversation = nil
        timelineSynchronization.stop()
        pinnedConversationId = nil
        chatPreferences = .empty
        messages = []
        loadingConversationId = nil
        pendingMessageCount = 0
        matrixEncryptionRecoveryStatus = .notLoaded
        matrixEncryptionRecoveryGeneratedKey = nil
        matrixEncryptionRecoveryErrorText = nil
        matrixEncryptionRecoveryErrorTechnicalDetail = nil
        matrixEncryptionRecoveryWorking = false
        localAIAvailability = .unavailable
        mobilePairingConfirmationTask?.cancel()
        mobilePairingConfirmationTask = nil
        mobilePairingPresentation = nil
        pushSnapshot = pushNotifications.currentSnapshot
        devicePosture = .unknown
        managedAppPolicy = .unmanaged
        deviceSessionId = nil
        messagingDeviceId = nil
        registeredMessagingDeviceTokenFingerprint = nil
        messagingDeviceRegistrationStatusText = "not_registered"
        registeredMatrixPusherTokenFingerprint = nil
        registeredMatrixPusherGatewayURL = nil
        messagingTransportReadyForPusher = false
        notificationPreferences = .default
        notificationSubscriptions = .empty
        messageOutboxSyncStatusText = "idle"
        messagingBootstrapExpiresAt = nil
        messagingBootstrapIssuedAt = nil
        lastMessagingBootstrap = nil
        messagingBootstrapRefreshTask = nil
        messagingBootstrapNetworkRetryNotBefore = nil
        await pushNotifications.updateApplicationBadgeCount(0)
        messagingStatusText = "disabled"
        connectionMode = .offline
        authState = .signedOut
        pendingAutoSyncAttemptedConversationIds = []
        pendingAutoSyncInFlightConversationIds = []
    }

    func refreshSession() async {
        guard authState == .signedIn else { return }
        guard await authSession.canUseExistingSession() else {
            authState = .signedOut
            connectionMode = .offline
            return
        }
        await bootstrapCommunication()
    }

    func unlockSession() async {
        guard authState == .locked else { return }
        authState = .signedIn
        await bootstrapCommunication()
    }

    func appDidBecomeActive() async {
        guard authState == .signedIn else { return }
        guard await authSession.canUseExistingSession() else {
            authState = .signedOut
            connectionMode = .offline
            return
        }
        let shouldRecoverMessagingTransport = messagingStatusText == "e2ee_queue" ||
            messagingStatusText == "degraded" ||
            messagingStatusText == "offline_queue"
        await ensureMessagingBootstrapFreshIfNeeded(force: shouldRecoverMessagingTransport)
        await refreshMatrixEncryptionRecoveryStatus()
        await refreshPendingMessageCount()
        if let selectedConversation {
            await automaticallySynchronizePendingMessagesIfPossible(for: selectedConversation, force: true)
        }
        await updateApplicationBadgeCount()
    }

    private func bootstrapCommunication() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let bootstrap = try await api.bootstrap(seconds: 180)
            try await enforceSecurityUnlockIfRequired(
                by: bootstrap.policy,
                subjectId: bootstrap.actor.subjectId
            )
            actor = bootstrap.actor
            policy = bootstrap.policy
            userProfile = bootstrap.profile
            connectionMode = .online
            lastError = nil

            if appConfiguration.resetStateForUITesting {
                Self.clearChatConversationPreferences(subjectId: bootstrap.actor.subjectId)
            }
            chatPreferences =
                Self.readChatConversationPreferences(subjectId: bootstrap.actor.subjectId) ?? .empty
            pinnedConversationId = chatPreferences.pinnedConversationIds.first
                ?? Self.readPinnedConversationId(subjectId: bootstrap.actor.subjectId)
            notificationPreferences =
                Self.readNotificationPreferences(subjectId: bootstrap.actor.subjectId) ?? .default
            notificationSubscriptions =
                Self.readNotificationSubscriptions(subjectId: bootstrap.actor.subjectId) ?? .empty

            await reconcileMatrixDeviceGeneration(for: bootstrap.actor.subjectId)
            await preparePushIfAllowed(by: bootstrap)
            await registerDeviceIfPossible()
            await registerMessagingDeviceIfPossible()
            await configureMessaging(for: bootstrap.actor)
            pendingAutoSyncAttemptedConversationIds = []
            pendingAutoSyncInFlightConversationIds = []
            await refreshConversations()
        } catch {
            if authState == .signedOut || authState == .locked {
                connectionMode = .offline
            } else {
                connectionMode = .degraded
            }
            lastError = error.localizedDescription
        }
    }

    private func configureMessaging(for actor: AuthenticatedActor) async {
        if let messagingBootstrapRefreshTask {
            await messagingBootstrapRefreshTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performConfigureMessaging(for: actor)
        }
        messagingBootstrapRefreshTask = task
        await task.value
        messagingBootstrapRefreshTask = nil
    }

    private func performConfigureMessaging(for actor: AuthenticatedActor) async {
        let deviceId = Self.matrixDeviceId(
            actor: actor,
            deviceRegistration: deviceRegistration,
            posture: devicePosture
        )
        let currentStatus = try? await api.messagingStatus()
        if let currentStatus, (!currentStatus.enabled || !currentStatus.chatAvailable) {
            messagingStatusText = currentStatus.status
            lastError = currentStatus.warnings.first
            return
        }
        if let cachedBootstrap = await cachedMessagingBootstrap(for: actor, deviceId: deviceId) {
            let configured = await configureMessagingTransport(
                with: cachedBootstrap,
                statusText: currentStatus?.status ?? Self.statusTextForCachedMessagingBootstrap(cachedBootstrap)
            )
            if configured || !Self.messagingTransportFailureNeedsFreshBootstrap(messagingTransportErrorText) {
                return
            }
            try? await messagingBootstrapStore?.clear(subjectId: actor.subjectId, deviceId: deviceId)
            lastMessagingBootstrap = nil
            messagingBootstrapExpiresAt = nil
            messagingBootstrapIssuedAt = nil
        }

        do {
            let status: MessagingStatus
            if let currentStatus {
                status = currentStatus
            } else {
                status = try await api.messagingStatus()
            }
            let matrixBootstrap = try await api.messagingBootstrap(deviceId: deviceId)
            messagingBootstrapIssuedAt = .now
            messagingBootstrapExpiresAt = Self.resolvedMatrixBootstrapExpiry(matrixBootstrap)
            lastMessagingBootstrap = matrixBootstrap
            messagingBootstrapNetworkRetryNotBefore = nil
            try? await messagingBootstrapStore?.save(matrixBootstrap, subjectId: actor.subjectId, deviceId: deviceId)
            _ = await configureMessagingTransport(with: matrixBootstrap, statusText: status.status)
        } catch {
            if let retryDelay = Self.messagingBootstrapRetryDelay(after: error) {
                messagingBootstrapNetworkRetryNotBefore = Date().addingTimeInterval(retryDelay)
            }
            if let lastMessagingBootstrap,
               Self.messagingBootstrapStillUsable(lastMessagingBootstrap) {
                messagingBootstrapExpiresAt = Self.resolvedMatrixBootstrapExpiry(lastMessagingBootstrap)
                _ = await configureMessagingTransport(
                    with: lastMessagingBootstrap,
                    statusText: lastMessagingBootstrap.status.isEmpty ? "online" : lastMessagingBootstrap.status
                )
                return
            }
            messagingStatusText = "degraded"
            lastError = error.localizedDescription
            messagingBootstrapExpiresAt = nil
            messagingBootstrapIssuedAt = nil
        }
    }

    private func cachedMessagingBootstrap(
        for actor: AuthenticatedActor,
        deviceId: String
    ) async -> MessagingBootstrap? {
        if let lastMessagingBootstrap,
           Self.messagingBootstrapStillUsable(lastMessagingBootstrap),
           lastMessagingBootstrap.deviceId == nil || lastMessagingBootstrap.deviceId == deviceId {
            return lastMessagingBootstrap
        }

        guard let messagingBootstrapStore,
              let cached = try? await messagingBootstrapStore.load(subjectId: actor.subjectId, deviceId: deviceId) else {
            return nil
        }
        guard Self.messagingBootstrapStillUsable(cached) else {
            try? await messagingBootstrapStore.clear(subjectId: actor.subjectId, deviceId: deviceId)
            return nil
        }

        messagingBootstrapIssuedAt = .now
        messagingBootstrapExpiresAt = Self.resolvedMatrixBootstrapExpiry(cached)
        lastMessagingBootstrap = cached
        return cached
    }

    @discardableResult
    private func configureMessagingTransport(with bootstrap: MessagingBootstrap, statusText: String) async -> Bool {
        do {
            try await messaging.configure(with: bootstrap)
            messagingStatusText = MessagingRuntimeStatusResolver.configuredStatus(
                bootstrap: bootstrap,
                serverStatus: statusText
            )
            messagingTransportErrorText = nil
            messagingTransportReadyForPusher = true
            await refreshMatrixEncryptionRecoveryStatus()
            await registerMatrixPusherIfPossible()
            return true
        } catch {
            messagingTransportReadyForPusher = false
            messagingTransportErrorText = error.localizedDescription
            matrixEncryptionRecoveryStatus = .unavailable(error.localizedDescription)
            if bootstrap.e2eeRequired {
                messagingStatusText = "e2ee_queue"
                await appendEvent(
                    kind: .messagingTransportQueued,
                    summary: "Messaging obsah zustane v sifrovane lokalni fronte do dostupnosti E2EE adapteru.",
                    metadata: [
                        "provider": bootstrap.providerId,
                        "e2eeRequired": "true"
                    ]
                )
            } else {
                messagingStatusText = "degraded"
                lastError = error.localizedDescription
            }
            return false
        }
    }

    private func ensureMessagingBootstrapFreshIfNeeded(force: Bool = false) async {
        guard let actor else { return }

        let expiresSoon = messagingBootstrapExpiresAt.map { $0.timeIntervalSinceNow < 90 } ?? false
        let unknownExpiryIsStale = messagingBootstrapExpiresAt == nil &&
            (messagingBootstrapIssuedAt.map { Date().timeIntervalSince($0) > 240 } ?? true)
        let transportNeedsRetry = messagingStatusText == "e2ee_queue" ||
            messagingStatusText == "degraded" ||
            messagingStatusText == "offline_queue"

        if force,
           let cachedBootstrap = lastMessagingBootstrap,
           Self.messagingBootstrapStillUsable(cachedBootstrap) {
            let configured = await configureMessagingTransport(
                with: cachedBootstrap,
                statusText: Self.statusTextForCachedMessagingBootstrap(cachedBootstrap)
            )
            if configured || !Self.messagingTransportFailureNeedsFreshBootstrap(messagingTransportErrorText) {
                return
            }
        }

        if force || expiresSoon || unknownExpiryIsStale {
            guard Self.messagingBootstrapNetworkRefreshIsAllowed(retryNotBefore: messagingBootstrapNetworkRetryNotBefore) else {
                return
            }
            await configureMessaging(for: actor)
        } else if transportNeedsRetry, let lastMessagingBootstrap {
            _ = await configureMessagingTransport(
                with: lastMessagingBootstrap,
                statusText: Self.statusTextForCachedMessagingBootstrap(lastMessagingBootstrap)
            )
        }
    }

    private static func resolvedMatrixBootstrapExpiry(_ bootstrap: MessagingBootstrap) -> Date? {
        if let expiresAt = bootstrap.expiresAt {
            return expiresAt
        }
        guard let expiresInMs = bootstrap.expiresInMs, expiresInMs > 0 else {
            return nil
        }
        return Date().addingTimeInterval(Double(expiresInMs) / 1_000.0)
    }

    private static func messagingBootstrapStillUsable(_ bootstrap: MessagingBootstrap) -> Bool {
        guard bootstrap.enabled, bootstrap.chatAvailable, bootstrap.tokenAvailable else {
            return false
        }
        guard let expiresAt = resolvedMatrixBootstrapExpiry(bootstrap) else {
            return true
        }
        return expiresAt.timeIntervalSinceNow > 30
    }

    private static func statusTextForCachedMessagingBootstrap(_ bootstrap: MessagingBootstrap) -> String {
        bootstrap.status.isEmpty ? "online" : bootstrap.status
    }

    private static func messagingBootstrapNetworkRefreshIsAllowed(retryNotBefore: Date?) -> Bool {
        guard let retryNotBefore else { return true }
        return retryNotBefore <= Date()
    }

    private static func messagingBootstrapRetryDelay(after error: any Error) -> TimeInterval? {
        let description = error.localizedDescription.lowercased()
        if description.contains("429") ||
            description.contains("too many") ||
            description.contains("rate limit") ||
            description.contains("rc_login") {
            return 120
        }
        if description.contains("timeout") ||
            description.contains("network") ||
            description.contains("connection") ||
            description.contains("503") ||
            description.contains("504") {
            return 20
        }
        return nil
    }

    private static func messagingTransportFailureNeedsFreshBootstrap(_ error: String?) -> Bool {
        guard let description = error?.lowercased() else { return false }
        return description.contains("m_unknown_token") ||
            description.contains("unknown token") ||
            description.contains("access token") ||
            description.contains("expired") ||
            description.contains("unauthorized") ||
            description.contains("401")
    }

    @MainActor
    static func matrixDeviceId(
        actor: AuthenticatedActor,
        deviceRegistration: (any DeviceRegistrationProviding)?,
        posture: MobileDevicePosture?,
        installationSeed: String? = nil
    ) -> String {
        let platformDeviceId = deviceRegistration?
            .registration(push: nil, posture: posture)
            .deviceId ?? "ios-unknown-device"
        let installationSeed = installationSeed ?? matrixInstallationSeed()
        let seed = "\(matrixDeviceGeneration)|\(actor.subjectId)|\(actor.username)|\(platformDeviceId)|\(installationSeed)"
        let digest = SHA256.hash(data: Data(seed.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
        return "CSMIOS.\(digest)"
    }

    /// Matrix crypto state lives in the application container while the COP
    /// sign-in token and physical-device registration survive an app reinstall
    /// in Keychain. Reusing the previous Matrix device id with a new empty
    /// crypto store causes the homeserver and peer devices to retain stale
    /// identity keys. This non-secret installation seed survives upgrades but
    /// is regenerated after a reinstall, so Matrix provisions a genuinely new
    /// E2EE device instead of impersonating the erased one.
    private static func matrixInstallationSeed() -> String {
        if let existing = UserDefaults.standard.string(forKey: matrixInstallationSeedStorageKey),
           !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString.lowercased()
        UserDefaults.standard.set(created, forKey: matrixInstallationSeedStorageKey)
        return created
    }

    private func registerDeviceIfPossible() async {
        guard let deviceRegistration else { return }
        do {
            let registration = deviceRegistration.registration(
                push: nil,
                posture: devicePosture
            )
            let response = try await api.registerDevice(registration)
            deviceSessionId = response.deviceSessionId
            policy = response.policy
            await appendEvent(
                kind: .deviceRegistered,
                relatedId: response.deviceSessionId,
                summary: "Zarizeni registrovano u COP.",
                metadata: [
                    "pushTokenRegistered": response.pushTokenRegistered ? "true" : "false",
                    "platform": registration.platform
                ]
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func registerMessagingDeviceIfPossible() async {
        guard let messagingDeviceRegistration else { return }
        guard let token = pushSnapshot.deviceToken, pushSnapshot.environment != "unavailable" else {
            messagingDeviceRegistrationStatusText = "waiting_for_apns"
            Self.recordDeviceRegistrationDiagnostic("waiting_for_apns")
            Self.diagnostics.notice("device-registration=waiting_for_apns")
            return
        }
        guard let voipToken = await voipDeviceTokenProvider?(), !voipToken.isEmpty else {
            messagingDeviceRegistrationStatusText = "waiting_for_voip"
            Self.recordDeviceRegistrationDiagnostic("waiting_for_voip")
            Self.diagnostics.notice("device-registration=waiting_for_voip")
            return
        }

        do {
            let tokenFingerprint = Self.tokenFingerprint("\(token):\(voipToken)")
            if let messagingDeviceId,
               let registeredMessagingDeviceTokenFingerprint,
               registeredMessagingDeviceTokenFingerprint != tokenFingerprint {
                try? await messagingDeviceRegistration.deleteDevice(deviceId: messagingDeviceId)
                self.messagingDeviceId = nil
                messagingDeviceRegistrationStatusText = "refreshing_apns_token"
            }

            let request = makeMessagingDeviceRegistrationRequest(
                deviceToken: token,
                voipDeviceToken: voipToken
            )
            let ticket = try await api.deviceRegistrationTicket(
                appInstanceId: request.appInstanceId,
                bundleId: request.appBundleId
            )
            guard ticket.messagingBaseUrl.host == appConfiguration.messagingBaseURL.host else {
                throw CSMServiceError.invalidState("Registrační ticket směřuje na neočekávanou službu.")
            }
            let response = try await messagingDeviceRegistration.registerDevice(
                request,
                authorizationTicket: ticket.ticket
            )
            messagingDeviceId = response.device.deviceId
            registeredMessagingDeviceTokenFingerprint = tokenFingerprint
            messagingDeviceRegistrationStatusText = response.device.status ?? "active"
            applyMessagingDeviceServerState(response.device)
            Self.recordDeviceRegistrationDiagnostic(
                "active_\(Self.apnsEnvironment)"
            )
            Self.diagnostics.notice(
                "device-registration=active apns-environment=\(Self.apnsEnvironment, privacy: .public)"
            )
            await appendEvent(
                kind: .messagingDeviceRegistered,
                relatedId: response.device.deviceId,
                summary: "Zarizeni registrovano u CSM Messaging pro push dorucovani.",
                metadata: [
                    "platform": response.device.platform ?? "ios",
                    "provider": response.providerId ?? "csm.messaging",
                    "apns": "token-present",
                    "voip": "token-present"
                ]
            )
        } catch {
            messagingDeviceRegistrationStatusText = "failed"
            lastError = error.localizedDescription
            Self.recordDeviceRegistrationDiagnostic(
                "failed_\(String(describing: type(of: error)))"
            )
            Self.diagnostics.error(
                "device-registration=failed error-type=\(String(describing: type(of: error)), privacy: .public)"
            )
            await appendEvent(
                kind: .messagingDeviceRegistrationFailed,
                summary: "Registrace zarizeni u CSM Messaging selhala.",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    private func registerMatrixPusherIfPossible(force: Bool = false) async {
        guard messagingTransportReadyForPusher else { return }
        guard let token = pushSnapshot.deviceToken, pushSnapshot.environment != "unavailable" else { return }
        guard let gatewayURL = matrixPushGatewayURL else { return }

        let tokenFingerprint = Self.tokenFingerprint(token)
        guard force ||
            registeredMatrixPusherTokenFingerprint != tokenFingerprint ||
            registeredMatrixPusherGatewayURL != gatewayURL
        else {
            return
        }

        await messaging.registerPusher(pushKey: token, pushGatewayURL: gatewayURL)
        registeredMatrixPusherTokenFingerprint = tokenFingerprint
        registeredMatrixPusherGatewayURL = gatewayURL
        await appendEvent(
            kind: .pushRegistrationUpdated,
            summary: "Matrix pusher pro chatove push notifikace byl aktualizovan.",
            metadata: [
                "gateway": gatewayURL.absoluteString,
                "pushKey": "token-present"
            ]
        )
    }

    private var matrixPushGatewayURL: URL? {
        let base = appConfiguration.messagingBaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/api/v1/matrix/push/notify")
    }

    private func makeMessagingDeviceRegistrationRequest(
        deviceToken: String,
        voipDeviceToken: String
    ) -> CSMMessagingDeviceRegistrationRequest {
        return CSMMessagingDeviceRegistrationRequest(
            apnsEnvironment: Self.apnsEnvironment,
            appBundleId: Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm.messenger",
            appInstanceId: Self.appInstanceId,
            capabilities: .init(
                criticalAlerts: false,
                e2ee: true,
                liveActivities: false,
                voip: true
            ),
            deviceToken: deviceToken,
            voipDeviceToken: voipDeviceToken,
            locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            platform: "ios",
            preferences: .init(categories: notificationPreferences.categories),
            subscriptions: .init(groupIds: notificationSubscriptions.groupIds, areaIds: notificationSubscriptions.areaIds),
            timezone: TimeZone.current.identifier
        )
    }

    private static var apnsEnvironment: String {
        CSMAPNSEnvironmentResolver.current
    }

    private static var appInstanceId: String {
        let key = "cz.zeleznalady.csm.app-instance-id"
        if let value = UserDefaults.standard.string(forKey: key), UUID(uuidString: value) != nil {
            return value.lowercased()
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func enforceSecurityUnlockIfRequired(by policy: MobileNativePolicy, subjectId: String) async throws {
        guard policy.requireBiometricUnlock else { return }

        await appendEvent(
            kind: .localUnlockRequired,
            summary: "Mobile policy vyzaduje lokalni biometricke odemknuti.",
            subjectIdOverride: subjectId,
            metadata: ["method": "biometric"]
        )

        do {
            try await securityUnlock.requireUnlock(
                reason: "CSM Messenger potrebuje potvrdit identitu pred zobrazenim krizovych dat."
            )
            await appendEvent(
                kind: .localUnlockSucceeded,
                summary: "Lokalni biometricke odemknuti potvrzeno.",
                subjectIdOverride: subjectId,
                metadata: ["method": "biometric"]
            )
        } catch {
            // A local biometric cancellation locks protected content; it is
            // not an OIDC logout and must never erase the refresh token.
            authState = .locked
            connectionMode = .offline
            await appendEvent(
                kind: .localUnlockFailed,
                summary: "Lokalni biometricke odemknuti selhalo.",
                subjectIdOverride: subjectId,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }
    }

    private func preparePushIfAllowed(by bootstrap: MobileBootstrap) async {
        if bootstrap.capabilities.pushNotifications || bootstrap.policy.pushNotifications != "not_configured" {
            pushSnapshot = await pushNotifications.prepareForRemoteNotifications()
        } else {
            pushSnapshot = pushNotifications.currentSnapshot
        }
        await appendEvent(
            kind: .pushRegistrationUpdated,
            summary: "APNS stav pripraven pro registraci zarizeni.",
            metadata: [
                "authorization": pushSnapshot.authorization.rawValue,
                "hasToken": pushSnapshot.deviceToken == nil ? "false" : "true"
            ]
        )
    }

    private func evaluateDevicePosture(policy: MobileNativePolicy?) async {
        managedAppPolicy = devicePostureProvider.currentManagedAppPolicy(policy: policy)
        devicePosture = devicePostureProvider.currentPosture(policy: policy)
        await appendEvent(
            kind: .devicePostureEvaluated,
            summary: "Bezpecnostni stav zarizeni vyhodnocen.",
            metadata: [
                "managed": devicePosture.managedAppConfigurationPresent ? "true" : "false",
                "managedRequired": managedAppPolicy.requiresManagedDevice(serverPolicy: policy) ? "true" : "false",
                "protectedData": devicePosture.protectedDataAvailable ? "true" : "false",
                "lowPowerMode": devicePosture.lowPowerModeEnabled ? "true" : "false",
                "remoteWipe": devicePosture.remoteWipeRequested ? "true" : "false",
                "relayDisabled": managedAppPolicy.relayDisabled ? "true" : "false",
                "localAIDisabled": managedAppPolicy.localAIDisabled ? "true" : "false",
                "offlineTileCachingDisabled": managedAppPolicy.offlineTileCachingDisabled ? "true" : "false"
            ]
        )
    }

    func refreshDeviceRegistrationFromSystem() async {
        pushSnapshot = pushNotifications.currentSnapshot
        await evaluateDevicePosture(policy: policy)
        await registerDeviceIfPossible()
        await registerMessagingDeviceIfPossible()
        await registerMatrixPusherIfPossible()
    }

    func setNotificationPreference(_ keyPath: WritableKeyPath<CSMNotificationPreferences, Bool>, enabled: Bool) async {
        notificationPreferences[keyPath: keyPath] = enabled
        if let actor {
            Self.writeNotificationPreferences(notificationPreferences, subjectId: actor.subjectId)
        }
        guard let messagingDeviceId, let messagingDeviceRegistration else { return }

        do {
            let response = try await messagingDeviceRegistration.updatePreferences(
                deviceId: messagingDeviceId,
                preferences: notificationPreferences,
                subscriptions: notificationSubscriptions
            )
            messagingDeviceRegistrationStatusText = response.device.status ?? "active"
            applyMessagingDeviceServerState(response.device)
            await appendEvent(
                kind: .notificationPreferencesUpdated,
                relatedId: messagingDeviceId,
                summary: "Notifikacni preference ulozeny v CSM Messaging.",
                metadata: ["categories": notificationPreferences.categories.joined(separator: ",")]
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setNotificationGroupSubscription(_ groupId: String, enabled: Bool) async {
        let updated = notificationSubscriptions.settingGroup(groupId, enabled: enabled)
        guard updated != notificationSubscriptions else { return }
        notificationSubscriptions = updated
        await persistAndPushNotificationSubscriptions(
            relatedId: CSMNotificationSubscriptions.normalizedIdentifier(groupId),
            metadata: [
                "subscriptionType": "group",
                "enabled": enabled ? "true" : "false",
                "groupIds": notificationSubscriptions.groupIds.joined(separator: ",")
            ]
        )
    }

    func setNotificationAreaSubscription(_ areaId: String, enabled: Bool) async {
        let updated = notificationSubscriptions.settingArea(areaId, enabled: enabled)
        guard updated != notificationSubscriptions else { return }
        notificationSubscriptions = updated
        await persistAndPushNotificationSubscriptions(
            relatedId: CSMNotificationSubscriptions.normalizedIdentifier(areaId),
            metadata: [
                "subscriptionType": "area",
                "enabled": enabled ? "true" : "false",
                "areaIds": notificationSubscriptions.areaIds.joined(separator: ",")
            ]
        )
    }

    private func persistAndPushNotificationSubscriptions(
        relatedId: String?,
        metadata: [String: String]
    ) async {
        if let actor {
            Self.writeNotificationSubscriptions(notificationSubscriptions, subjectId: actor.subjectId)
        }
        guard let messagingDeviceId, let messagingDeviceRegistration else { return }

        do {
            let response = try await messagingDeviceRegistration.updatePreferences(
                deviceId: messagingDeviceId,
                preferences: notificationPreferences,
                subscriptions: notificationSubscriptions
            )
            messagingDeviceRegistrationStatusText = response.device.status ?? "active"
            applyMessagingDeviceServerState(response.device)
            await appendEvent(
                kind: .notificationPreferencesUpdated,
                relatedId: relatedId ?? messagingDeviceId,
                summary: "Notifikacni odbery ulozeny v CSM Messaging.",
                metadata: metadata
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func applyMessagingDeviceServerState(_ device: CSMMessagingRegisteredDevice) {
        if let categories = device.preferences?.categories {
            notificationPreferences = CSMNotificationPreferences(categories: categories)
            if let actor {
                Self.writeNotificationPreferences(notificationPreferences, subjectId: actor.subjectId)
            }
        }
        if let subscriptions = device.subscriptions {
            notificationSubscriptions = CSMNotificationSubscriptions(
                groupIds: subscriptions.groupIds,
                areaIds: subscriptions.areaIds
            )
            if let actor {
                Self.writeNotificationSubscriptions(notificationSubscriptions, subjectId: actor.subjectId)
            }
        }
    }

    func refreshConversations() async {
        conversationListRefreshGeneration &+= 1
        let refreshGeneration = conversationListRefreshGeneration
        let previousPendingCount = pendingMessageCount
        if conversations.isEmpty {
            conversationListLoadState = .loading
        }
        do {
            let metadataConversations = await enrichedConversationList(try await loadConversationMetadataList())
            let presentations = await enrichedConversationPresentations(metadataConversations)
            guard refreshGeneration == conversationListRefreshGeneration else { return }
            conversations = presentations
            conversationListLoadState = .loaded
            conversationListErrorText = nil
            if let selectedConversationId = selectedConversation?.conversationId,
               let refreshedSelection = conversations.first(where: { $0.conversationId == selectedConversationId }) {
                selectedConversation = refreshedSelection
            } else if selectedConversation == nil {
                selectedConversation = visibleConversations.first ?? conversations.first
            }
            if let selectedConversation {
                try await loadMessages(for: selectedConversation)
                startLiveMessageStream(for: selectedConversation)
            }
            await refreshPendingMessageCount()
            await updateApplicationBadgeCount()
            if previousPendingCount > pendingMessageCount {
                await appendEvent(
                    kind: .messageOutboxSynced,
                    summary: "Lokalni fronta zprav byla castecne synchronizovana.",
                    metadata: [
                        "before": "\(previousPendingCount)",
                        "after": "\(pendingMessageCount)"
                    ]
                )
            }
        } catch is CancellationError {
            guard refreshGeneration == conversationListRefreshGeneration else { return }
            if conversations.isEmpty {
                conversationListLoadState = .notLoaded
            }
        } catch {
            guard refreshGeneration == conversationListRefreshGeneration else { return }
            conversationListLoadState = .failed
            conversationListErrorText = CSMLocalization.text(
                "conversation.list.unavailable",
                fallback: "Zprávy se teď nepodařilo načíst. Zkuste to znovu."
            )
            lastError = error.localizedDescription
        }
    }

    func selectConversation(_ conversation: Conversation) async {
        let isChangingConversation = selectedConversation?.conversationId != conversation.conversationId
        selectedConversation = conversation
        if isChangingConversation {
            timelineSynchronization.stop()
            messages = []
            voiceCallTimelineMessages = []
            loadingConversationId = conversation.conversationId
        }
        await ensureMessagingBootstrapFreshIfNeeded(force: shouldForceMessagingRefreshBeforeSend)
        await refreshMatrixEncryptionRecoveryStatus()
        if (try? await loadMessages(for: conversation)) != nil {
            markConversationReadLocally(conversation)
            await refreshChatNotificationSurfaces(syncWatch: true)
        }
        await refreshVoiceCallTimeline(for: conversation)
        if selectedConversation?.conversationId == conversation.conversationId {
            startLiveMessageStream(for: conversation)
        }
    }

    func loadEarlierMessagesForActiveConversation() async {
        guard let conversation = selectedConversation,
              let paging = messaging as? any MessagingHistoryPaging else {
            return
        }
        do {
            let page = try await paging.loadEarlierMessages(
                for: conversation,
                limit: TimelineWindowPolicy.mobile.initialMessageLimit
            )
            guard selectedConversation?.conversationId == conversation.conversationId else {
                return
            }
            timelineStore.send(
                .prependEarlier(
                    page.messages,
                    hasEarlier: page.hasEarlier
                )
            )
        } catch {
            messagingTransportErrorText = error.localizedDescription
        }
    }

    func returnToLatestMessagesForActiveConversation() async {
        guard let conversation = selectedConversation else { return }
        timelineStore.send(.returnToLatest)
        do {
            try await loadMessages(
                for: conversation,
                performAutomaticPendingSync: false
            )
        } catch {
            messagingTransportErrorText = error.localizedDescription
        }
    }

    func refreshMatrixEncryptionRecoveryStatus() async {
        guard let recovery = messaging as? any MatrixEncryptionRecoveryManaging else {
            matrixEncryptionRecoveryStatus = .unsupported("The active messaging client does not expose Matrix encryption recovery.")
            return
        }
        matrixEncryptionRecoveryStatus = await recovery.encryptionRecoveryStatus()
    }

    func createMatrixEncryptionRecovery(reset: Bool = false) async {
        guard let recovery = messaging as? any MatrixEncryptionRecoveryManaging else {
            matrixEncryptionRecoveryErrorText = CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu.")
            matrixEncryptionRecoveryErrorTechnicalDetail = nil
            return
        }

        matrixEncryptionRecoveryWorking = true
        matrixEncryptionRecoveryErrorText = nil
        matrixEncryptionRecoveryErrorTechnicalDetail = nil
        do {
            let recoveryKey = try await recovery.createEncryptionRecovery(reset: reset)
            matrixEncryptionRecoveryGeneratedKey = recoveryKey
            matrixEncryptionRecoveryStatus = await recovery.encryptionRecoveryStatus()
            await reloadSelectedConversationAfterEncryptionRecovery()
        } catch {
            let presentation = Self.matrixEncryptionRecoveryErrorPresentation(from: error)
            matrixEncryptionRecoveryErrorText = presentation.message
            matrixEncryptionRecoveryErrorTechnicalDetail = presentation.technicalDetail
            lastError = presentation.message
        }
        matrixEncryptionRecoveryWorking = false
    }

    func resetMatrixEncryptionRecovery(oldRecoveryKey: String) async {
        guard let recovery = messaging as? any MatrixEncryptionRecoveryManaging else {
            matrixEncryptionRecoveryErrorText = CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu.")
            matrixEncryptionRecoveryErrorTechnicalDetail = nil
            return
        }

        matrixEncryptionRecoveryWorking = true
        matrixEncryptionRecoveryErrorText = nil
        matrixEncryptionRecoveryErrorTechnicalDetail = nil
        do {
            let recoveryKey = try await recovery.resetEncryptionRecovery(oldRecoveryKey: oldRecoveryKey)
            matrixEncryptionRecoveryGeneratedKey = recoveryKey
            matrixEncryptionRecoveryStatus = await recovery.encryptionRecoveryStatus()
            await reloadSelectedConversationAfterEncryptionRecovery()
        } catch {
            let presentation = Self.matrixEncryptionRecoveryErrorPresentation(from: error)
            matrixEncryptionRecoveryErrorText = presentation.message
            matrixEncryptionRecoveryErrorTechnicalDetail = presentation.technicalDetail
            lastError = presentation.message
        }
        matrixEncryptionRecoveryWorking = false
    }

    func restoreMatrixEncryptionRecovery(recoveryKey: String) async {
        guard let recovery = messaging as? any MatrixEncryptionRecoveryManaging else {
            matrixEncryptionRecoveryErrorText = CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu.")
            matrixEncryptionRecoveryErrorTechnicalDetail = nil
            return
        }

        matrixEncryptionRecoveryWorking = true
        matrixEncryptionRecoveryErrorText = nil
        matrixEncryptionRecoveryErrorTechnicalDetail = nil
        do {
            try await recovery.restoreEncryptionRecovery(recoveryKey: recoveryKey)
            matrixEncryptionRecoveryGeneratedKey = nil
            matrixEncryptionRecoveryStatus = await recovery.encryptionRecoveryStatus()
            await reloadSelectedConversationAfterEncryptionRecovery()
        } catch {
            let presentation = Self.matrixEncryptionRecoveryErrorPresentation(from: error)
            matrixEncryptionRecoveryErrorText = presentation.message
            matrixEncryptionRecoveryErrorTechnicalDetail = presentation.technicalDetail
            lastError = presentation.message
        }
        matrixEncryptionRecoveryWorking = false
    }

    func clearMatrixEncryptionRecoveryGeneratedKey() {
        matrixEncryptionRecoveryGeneratedKey = nil
    }

    private func reloadSelectedConversationAfterEncryptionRecovery() async {
        guard let selectedConversation else { return }
        try? await loadMessages(for: selectedConversation, performAutomaticPendingSync: false)
        startLiveMessageStream(for: selectedConversation)
    }

    private static func matrixEncryptionRecoveryErrorPresentation(
        from error: any Error
    ) -> (message: String, technicalDetail: String?) {
        if let recoveryError = error as? MatrixEncryptionRecoveryUserFacingError {
            return (recoveryError.userMessage, recoveryError.technicalDetail)
        }

        if let serviceError = error as? CSMServiceError {
            return (serviceError.localizedDescription, nil)
        }

        return (
            CSMLocalization.text("matrix.recovery.restore_failed.user", fallback: "Obnovu E2EE se nepodařilo dokončit. Zkontrolujte obnovovací klíč a zkuste to znovu."),
            error.localizedDescription
        )
    }

    func handleDeepLinkURL(_ url: URL) async -> CSMNavigationDestination? {
        guard let deepLink = CSMDeepLink(url: url) else { return nil }
        await appendEvent(
            kind: .pushDeepLinkReceived,
            summary: "Prijat deep link pro CSM Messenger.",
            metadata: deepLink.auditMetadata
        )
        if case let .mobilePairing(code) = deepLink {
            await startMobilePairing(code: code)
            return nil
        }
        return await handleDeepLink(deepLink)
    }

    func handlePushUserInfo(_ userInfo: [AnyHashable: Any]) async -> CSMNavigationDestination? {
        await handlePushPayload(CSMRemoteNotificationPayload(userInfo: userInfo))
    }

    func handlePushPayload(_ payload: CSMRemoteNotificationPayload) async -> CSMNavigationDestination? {
        guard let deepLink = payload.targetDeepLink else { return nil }
        var metadata = payload.auditMetadata
        metadata["deliveryContext"] = payload.deliveryContext.rawValue
        await appendEvent(
            kind: .pushDeepLinkReceived,
            summary: "Prijat minimalni push odkaz pro CSM Messenger.",
            metadata: metadata
        )
        guard payload.deliveryContext.shouldNavigate else {
            await refreshForPassivePush(payload, deepLink: deepLink)
            return nil
        }
        if payload.action == .markRead {
            await markChatConversationReadFromPush(payload: payload, deepLink: deepLink)
            return nil
        }
        if payload.action == .reply {
            return await replyToChatFromPush(payload: payload, deepLink: deepLink)
        }
        return await handleDeepLink(deepLink)
    }

    private func refreshForPassivePush(
        _ payload: CSMRemoteNotificationPayload,
        deepLink: CSMDeepLink
    ) async {
        switch deepLink {
        case .mapAlert, .mapReport:
            // Map/report data belongs to the web COP host. A passive push does
            // not bootstrap those domains inside the native communication kit.
            break
        case .chatRoom, .message:
            await refreshConversations()
            guard let conversation = await conversationForChatPush(payload: payload, deepLink: deepLink) else {
                await updateApplicationBadgeCount()
                return
            }
            await markConversationUnreadFromPassiveChatPush(conversation)
            await refreshSelectedConversationForPassiveChatPush(conversation, payload: payload, deepLink: deepLink)
            await refreshChatNotificationSurfaces(syncWatch: true)
        case .mobilePairing:
            break
        }
    }

    private func markConversationUnreadFromPassiveChatPush(_ conversation: Conversation) async {
        chatPreferences = chatPreferences.settingManualUnread(conversation.conversationId, enabled: true)
        persistChatConversationPreferences()
        await appendEvent(
            kind: .messageReceived,
            relatedId: conversation.conversationId,
            summary: "Minimalni chat push oznacil konverzaci jako neprectenou bez cteni obsahu APNs payloadu.",
            metadata: [
                "conversationId": conversation.conversationId,
                "trigger": "passive_chat_push"
            ]
        )
    }

    private func refreshSelectedConversationForPassiveChatPush(
        _ conversation: Conversation,
        payload: CSMRemoteNotificationPayload,
        deepLink: CSMDeepLink
    ) async {
        guard selectedConversation?.conversationId == conversation.conversationId else { return }
        await refreshVisibleConversation(
            conversation,
            requiredMessageId: payload.messageId ?? deepLink.messageId,
            trigger: (payload.messageId ?? deepLink.messageId) == nil ? "chat_room_push" : "message_push"
        )
    }

    private func refreshVisibleConversation(
        _ conversation: Conversation,
        requiredMessageId: String? = nil,
        trigger: String
    ) async {
        do {
            let loadedMessages = try await messaging.messages(for: conversation)
            if let requiredMessageId,
               loadedMessages.contains(where: { $0.id == requiredMessageId }) == false {
                return
            }
            selectedConversation = conversation
            let hasEarlier = if let paging = messaging as? any MessagingHistoryPaging {
                await paging.hasEarlierMessages(for: conversation)
            } else {
                loadedMessages.count > TimelineWindowPolicy.mobile.retainedMessageLimit
            }
            timelineStore.send(
                .replaceRemote(
                    loadedMessages,
                    hasEarlier: hasEarlier
                )
            )
            await refreshPendingMessageCount()
            startLiveMessageStream(for: conversation)
            await appendEvent(
                kind: .messageReceived,
                relatedId: conversation.conversationId,
                summary: "Pasivni push obnovil otevreny chat bez obsahu v APNs payloadu.",
                metadata: [
                    "trigger": trigger,
                    "messageCount": "\(loadedMessages.count)"
                ]
            )
        } catch {
            lastError = error.localizedDescription
            messagingTransportErrorText = error.localizedDescription
        }
    }

    private func conversationForChatPush(
        payload: CSMRemoteNotificationPayload,
        deepLink: CSMDeepLink
    ) async -> Conversation? {
        if let roomReference = payload.roomId ?? deepLink.roomId {
            if let conversation = conversations.first(where: { Self.conversation($0, matchesRoomReference: roomReference) }) {
                return conversation
            }
            return await loadConversationIfPresent(id: roomReference)
        }

        guard let messageId = payload.messageId ?? deepLink.messageId else {
            return nil
        }

        if let selectedConversation,
           await conversation(selectedConversation, containsMessage: messageId) {
            return selectedConversation
        }

        for conversation in conversations where conversation.conversationId != selectedConversation?.conversationId {
            if await self.conversation(conversation, containsMessage: messageId) {
                return conversation
            }
        }

        return nil
    }

    private func conversation(_ conversation: Conversation, containsMessage messageId: String) async -> Bool {
        if selectedConversation?.conversationId == conversation.conversationId,
           messages.contains(where: { $0.id == messageId }) {
            return true
        }

        if let messageHistory,
           let cached = try? await messageHistory.messages(for: conversation.conversationId),
           cached.contains(where: { $0.id == messageId }) {
            return true
        }

        do {
            let loadedMessages = try await messaging.messages(for: conversation)
            return loadedMessages.contains(where: { $0.id == messageId })
        } catch {
            return false
        }
    }

    private func refreshChatNotificationSurfaces(syncWatch: Bool) async {
        _ = syncWatch
        await updateApplicationBadgeCount()
    }

    private func updateApplicationBadgeCount() async {
        await pushNotifications.updateApplicationBadgeCount(applicationBadgeUnreadCount)
    }

    private var applicationBadgeUnreadCount: Int {
        visibleConversations.reduce(0) { total, conversation in
            guard conversationHasVisibleUnread(conversation), !isConversationMuted(conversation) else {
                return total
            }
            return total + visibleUnreadCount(for: conversation)
        }
    }

    private func markChatConversationReadFromPush(
        payload: CSMRemoteNotificationPayload,
        deepLink: CSMDeepLink
    ) async {
        await refreshConversations()
        guard let conversation = await conversationForChatPush(payload: payload, deepLink: deepLink) else {
            return
        }
        markConversationReadLocally(conversation)
        await appendEvent(
            kind: .messageReceived,
            relatedId: conversation.conversationId,
            summary: "Uzivatel oznacil chatovou notifikaci jako prectenou bez cteni APNs obsahu.",
            metadata: [
                "conversationId": conversation.conversationId,
                "action": CSMRemoteNotificationAction.markRead.rawValue
            ]
        )
        await refreshChatNotificationSurfaces(syncWatch: true)
    }

    private func replyToChatFromPush(
        payload: CSMRemoteNotificationPayload,
        deepLink: CSMDeepLink
    ) async -> CSMNavigationDestination? {
        guard let responseText = payload.responseText else {
            return await handleDeepLink(deepLink)
        }
        await refreshConversations()
        guard let conversation = await conversationForChatPush(payload: payload, deepLink: deepLink) else {
            lastError = CSMLocalization.text("notification.reply.missing_conversation", fallback: "Konverzaci pro odpověď z notifikace se nepodařilo najít.")
            return .conversations
        }
        await selectConversation(conversation)
        await sendMessage(OutgoingMessageDraft(body: responseText))
        await refreshChatNotificationSurfaces(syncWatch: true)
        return .conversations
    }

    private func handleDeepLink(_ deepLink: CSMDeepLink) async -> CSMNavigationDestination {
        switch deepLink {
        case .mapAlert:
            // The native shell forwards this destination to WebHostView.
            return .map

        case .mapReport:
            return .reports

        case let .chatRoom(roomId):
            await refreshConversations()
            if let conversation = conversations.first(where: { Self.conversation($0, matchesRoomReference: roomId) }) {
                await selectConversation(conversation)
            } else if let conversation = await loadConversationIfPresent(id: roomId) {
                await selectConversation(conversation)
            }
            return .conversations

        case let .message(messageId):
            await refreshConversations()
            if let selectedConversation, await loadMessagesIfPresent(messageId: messageId, in: selectedConversation) {
                return .conversations
            }
            for conversation in conversations where conversation.conversationId != selectedConversation?.conversationId {
                if await loadMessagesIfPresent(messageId: messageId, in: conversation) {
                    return .conversations
                }
            }
            return .conversations

        case let .mobilePairing(code):
            await startMobilePairing(code: code)
            return .settings
        }
    }

    func dismissMobilePairingPresentation() {
        guard mobilePairingPresentation?.status != .claiming else { return }
        if mobilePairingPresentation?.status == .waitingForWebConfirmation {
            mobilePairingConfirmationTask?.cancel()
            mobilePairingConfirmationTask = nil
        }
        mobilePairingPresentation = nil
    }

    func startMobilePairing(code rawCode: String) async {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        mobilePairingConfirmationTask?.cancel()
        mobilePairingConfirmationTask = nil
        mobilePairingPresentation = MobilePairingPresentation(
            code: code,
            status: authState == .signedIn ? .claiming : .needsSignIn,
            expiresAt: nil,
            detail: nil
        )

        if authState != .signedIn {
            await signIn()
        }

        guard authState == .signedIn, let actor else {
            mobilePairingPresentation = MobilePairingPresentation(
                code: code,
                status: .needsSignIn,
                expiresAt: nil,
                detail: CSMLocalization.text(
                    "pairing.detail.same_account",
                    fallback: "Přihlaste se stejným účtem jako ve webové aplikaci."
                )
            )
            return
        }

        mobilePairingPresentation = MobilePairingPresentation(
            code: code,
            status: .claiming,
            expiresAt: nil,
            detail: nil
        )

        do {
            guard try await validateMobilePairingSessionBeforeClaim(code: code, actor: actor) else {
                return
            }
            let request = makeMobilePairingClaimRequest(actor: actor)
            let response = try await api.claimMobilePairingSession(code: code, request: request)
            guard validateMobilePairingSecurity(response) else {
                await failMobilePairing(
                    code: code,
                    status: .failed,
                    detail: CSMLocalization.text(
                        "pairing.error.security_contract",
                        fallback: "Párování nebylo dokončeno, protože odkaz neodpovídá bezpečnostnímu kontraktu COP."
                    )
                )
                return
            }

            switch response.pairing.status {
            case .confirmed:
                await completeMobilePairing(response)
            case .pending, .claimed:
                mobilePairingPresentation = MobilePairingPresentation(
                    code: code,
                    status: .waitingForWebConfirmation,
                    expiresAt: response.pairing.expiresAt,
                    detail: nil
                )
                await appendEvent(
                    kind: .mobilePairingClaimed,
                    summary: "Mobilni parovani claimnulo iOS zarizeni a ceka na potvrzeni ve webu.",
                    metadata: [
                        "contractVersion": response.contractVersion,
                        "containsAccessToken": "\(response.security.containsAccessToken)",
                        "containsRecoveryKey": "\(response.security.containsRecoveryKey)",
                        "containsRoomKeys": "\(response.security.containsRoomKeys)"
                    ]
                )
                beginMobilePairingConfirmationPolling(code: code, expiresAt: response.pairing.expiresAt)
            case .expired, .revoked:
                await failMobilePairing(
                    code: code,
                    status: .expired,
                    detail: CSMLocalization.text("pairing.error.expired", fallback: "Párovací odkaz vypršel.")
                )
            }
        } catch {
            let status = Self.mobilePairingFailureStatus(from: error)
            await failMobilePairing(
                code: code,
                status: status,
                detail: Self.mobilePairingFailureMessage(status: status, error: error)
            )
        }
    }

    private func validateMobilePairingSessionBeforeClaim(code: String, actor: AuthenticatedActor) async throws -> Bool {
        let session = try await api.mobilePairingSession(code: code)
        guard validateMobilePairingSecurity(session) else {
            await failMobilePairing(
                code: code,
                status: .failed,
                detail: CSMLocalization.text(
                    "pairing.error.security_contract",
                    fallback: "Párování nebylo dokončeno, protože odkaz neodpovídá bezpečnostnímu kontraktu COP."
                )
            )
            return false
        }
        if let createdBy = session.pairing.createdBy?.subjectId,
           createdBy != actor.subjectId {
            await failMobilePairing(
                code: code,
                status: .accountMismatch,
                detail: CSMLocalization.text(
                    "pairing.error.same_account",
                    fallback: "Přihlaste se stejným účtem jako ve webové aplikaci."
                )
            )
            return false
        }
        switch session.pairing.status {
        case .pending, .claimed:
            mobilePairingPresentation = MobilePairingPresentation(
                code: code,
                status: .claiming,
                expiresAt: session.pairing.expiresAt,
                detail: nil
            )
            return true
        case .confirmed, .expired, .revoked:
            await failMobilePairing(
                code: code,
                status: .expired,
                detail: CSMLocalization.text(
                    "pairing.error.invalid",
                    fallback: "Párování už není platné, vytvořte nové ve webové aplikaci."
                )
            )
            return false
        }
    }

    private func makeMobilePairingClaimRequest(actor: AuthenticatedActor) -> MobilePairingClaimRequest {
        let registration = deviceRegistration?.registration(
            push: nil,
            posture: devicePosture
        )
        let deviceId = registration?.deviceId ?? "ios-\(actor.subjectId)"
        return MobilePairingClaimRequest(
            deviceId: deviceId,
            platform: "ios",
            appVersion: appConfiguration.appVersion,
            buildNumber: appConfiguration.buildNumber,
            deviceModel: registration?.deviceModel ?? "iPhone",
            osVersion: registration?.osVersion ?? ProcessInfo.processInfo.operatingSystemVersionString,
            matrixDeviceId: Self.matrixDeviceId(
                actor: actor,
                deviceRegistration: deviceRegistration,
                posture: devicePosture
            ),
            capabilities: MobilePairingClaimRequest.Capabilities(
                matrixRustSdk: true,
                e2ee: true,
                push: true
            ),
            pushTokenRegistered: pushSnapshot.deviceToken != nil && pushSnapshot.environment != "unavailable"
        )
    }

    private func validateMobilePairingSecurity(_ response: MobilePairingSessionResponse) -> Bool {
        response.contractVersion == "cop-mobile-pairing-v1" && response.security.isMetadataOnly
    }

    private func beginMobilePairingConfirmationPolling(code: String, expiresAt: Date) {
        let api = api
        mobilePairingConfirmationTask?.cancel()
        mobilePairingConfirmationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if Date() >= expiresAt {
                    await self?.failMobilePairing(
                        code: code,
                        status: .expired,
                        detail: CSMLocalization.text("pairing.error.expired", fallback: "Párovací odkaz vypršel.")
                    )
                    return
                }

                do {
                    try await Task.sleep(for: .seconds(2))
                    let response = try await api.mobilePairingSession(code: code)
                    guard let self else { return }
                    guard self.validateMobilePairingSecurity(response) else {
                        await self.failMobilePairing(
                            code: code,
                            status: .failed,
                            detail: CSMLocalization.text(
                                "pairing.error.security_contract",
                                fallback: "Párování nebylo dokončeno, protože odkaz neodpovídá bezpečnostnímu kontraktu COP."
                            )
                        )
                        return
                    }

                    switch response.pairing.status {
                    case .confirmed:
                        await self.completeMobilePairing(response)
                        return
                    case .pending, .claimed:
                        self.mobilePairingPresentation = MobilePairingPresentation(
                            code: code,
                            status: .waitingForWebConfirmation,
                            expiresAt: response.pairing.expiresAt,
                            detail: nil
                        )
                    case .expired, .revoked:
                        await self.failMobilePairing(
                            code: code,
                            status: .expired,
                            detail: CSMLocalization.text("pairing.error.expired", fallback: "Párovací odkaz vypršel.")
                        )
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    guard let self else { return }
                    let status = Self.mobilePairingFailureStatus(from: error)
                    await self.failMobilePairing(
                        code: code,
                        status: status,
                        detail: Self.mobilePairingFailureMessage(status: status, error: error)
                    )
                    return
                }
            }
        }
    }

    private func completeMobilePairing(_ response: MobilePairingSessionResponse) async {
        mobilePairingConfirmationTask?.cancel()
        mobilePairingConfirmationTask = nil
        if let policy = response.policy {
            self.policy = policy
        }
        if let deviceSessionId = response.device?.deviceSessionId {
            self.deviceSessionId = deviceSessionId
        }
        if let actor {
            await clearCachedMessagingBootstrap(for: actor)
        }
        lastMessagingBootstrap = nil
        messagingBootstrapExpiresAt = nil
        messagingBootstrapIssuedAt = nil
        messagingBootstrapNetworkRetryNotBefore = nil
        mobilePairingPresentation = MobilePairingPresentation(
            code: response.pairing.code,
            status: .paired,
            expiresAt: response.pairing.expiresAt,
            detail: nil
        )
        await appendEvent(
            kind: .mobilePairingConfirmed,
            summary: "Mobilni parovani potvrzeno ve webove aplikaci COP.",
            metadata: [
                "contractVersion": response.contractVersion,
                "deviceId": response.device?.deviceId ?? response.pairing.claimedDevice?.deviceId ?? "unknown"
            ]
        )
        await refreshSession()
    }

    private func failMobilePairing(
        code: String,
        status: MobilePairingFlowStatus,
        detail: String
    ) async {
        mobilePairingConfirmationTask?.cancel()
        mobilePairingConfirmationTask = nil
        mobilePairingPresentation = MobilePairingPresentation(
            code: code,
            status: status,
            expiresAt: mobilePairingPresentation?.expiresAt,
            detail: detail
        )
        lastError = detail
        await appendEvent(
            kind: .mobilePairingFailed,
            summary: "Mobilni parovani se nepodarilo dokoncit.",
            metadata: ["status": status.rawValue]
        )
    }

    private static func mobilePairingFailureStatus(from error: any Error) -> MobilePairingFlowStatus {
        let description = error.localizedDescription.lowercased()
        if description.contains("409") || description.contains("404") || description.contains("expired") {
            return .expired
        }
        if description.contains("401") || description.contains("403") || description.contains("same account") || description.contains("account") {
            return .accountMismatch
        }
        return .failed
    }

    private static func mobilePairingFailureMessage(status: MobilePairingFlowStatus, error: any Error) -> String {
        switch status {
        case .expired:
            return CSMLocalization.text(
                "pairing.error.invalid",
                fallback: "Párování už není platné, vytvořte nové ve webové aplikaci."
            )
        case .accountMismatch:
            return CSMLocalization.text(
                "pairing.error.same_account",
                fallback: "Přihlaste se stejným účtem jako ve webové aplikaci."
            )
        case .failed:
            return CSMLocalization.text(
                "pairing.error.failed",
                fallback: "Párování se nepodařilo dokončit. Vytvořte nové ve webové aplikaci COP."
            )
        case .needsSignIn, .claiming, .waitingForWebConfirmation, .paired:
            return error.localizedDescription
        }
    }

    private func loadMessagesIfPresent(messageId: String, in conversation: Conversation) async -> Bool {
        do {
            let loadedMessages = try await messaging.messages(for: conversation)
            guard loadedMessages.contains(where: { $0.id == messageId }) else { return false }
            selectedConversation = conversation
            timelineStore.send(
                .replaceRemote(
                    loadedMessages,
                    hasEarlier: loadedMessages.count > TimelineWindowPolicy.mobile.retainedMessageLimit
                )
            )
            markConversationReadLocally(conversation)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func loadConversationIfPresent(id: String) async -> Conversation? {
        guard let conversationMetadata else { return nil }
        do {
            let conversation = try await conversationMetadata.conversation(id: id)
            upsertConversation(conversation)
            return conversation
        } catch {
            lastError = error.localizedDescription
            await appendEvent(
                kind: .conversationMetadataFallback,
                relatedId: id,
                summary: "Detail konverzace z autoritativnich COP metadata neni dostupny.",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func loadConversationMetadataList() async throws -> [Conversation] {
        guard let conversationMetadata else {
            throw CSMServiceError.unavailable("COP metadata klient konverzaci neni dostupny.")
        }
        let remoteConversations = try await conversationMetadata.conversations()
        conversationMetadataSourceText = "cop"
        return prioritizedConversations(remoteConversations)
    }

    private func refreshedConversationForSend(_ conversation: Conversation) async -> Conversation {
        guard let conversationMetadata else { return conversation }
        do {
            let refreshed = try await conversationMetadata.conversation(id: conversation.conversationId)
            let readyConversation = await ensureMatrixRoomIfNeeded(refreshed, trigger: "send")
            upsertConversation(readyConversation)
            if selectedConversation?.conversationId == readyConversation.conversationId {
                selectedConversation = readyConversation
            }
            return readyConversation
        } catch {
            await appendEvent(
                kind: .conversationMetadataFallback,
                relatedId: conversation.conversationId,
                summary: "Pred odeslanim se nepodarilo obnovit detail konverzace z COP.",
                metadata: ["error": error.localizedDescription]
            )
            return conversation
        }
    }

    private func ensureMatrixRoomIfNeeded(_ conversation: Conversation, trigger: String) async -> Conversation {
        guard conversation.matrix?.roomId?.isEmpty != false else { return conversation }
        guard let conversationMetadata else { return conversation }

        do {
            let boundConversation = try await conversationMetadata.ensureMatrixRoom(conversationId: conversation.conversationId)
            await appendEvent(
                kind: .conversationMatrixRoomBound,
                relatedId: boundConversation.conversationId,
                summary: "COP zajistil Matrix room pro konverzaci.",
                metadata: [
                    "trigger": trigger,
                    "matrixState": boundConversation.matrix?.state ?? "unknown",
                    "roomBound": boundConversation.matrix?.roomId?.isEmpty == false ? "true" : "false"
                ]
            )
            return boundConversation
        } catch {
            await appendEvent(
                kind: .conversationMetadataFallback,
                relatedId: conversation.conversationId,
                summary: "COP nedokazal zatim zajistit Matrix room pro konverzaci.",
                metadata: [
                    "trigger": trigger,
                    "error": error.localizedDescription
                ]
            )
            return conversation
        }
    }

    private func upsertConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.conversationId == conversation.conversationId }
        conversations.insert(conversation, at: 0)
        conversations = prioritizedConversations(conversations)
    }

    var visibleConversations: [Conversation] {
        conversations.filter(isConversationVisible)
    }

    var pinnedConversations: [Conversation] {
        visibleConversations.filter { isConversationPinned($0) }
    }

    var pinnedConversation: Conversation? {
        pinnedConversations.first
    }

    func isConversationPinned(_ conversation: Conversation) -> Bool {
        chatPreferences.isPinned(conversation.conversationId) || conversation.conversationId == pinnedConversationId
    }

    func isConversationVisible(_ conversation: Conversation) -> Bool {
        !chatPreferences.hiddenSnapshotMatches(
            conversationId: conversation.conversationId,
            snapshot: ChatConversationPreferences.snapshot(for: conversation)
        )
    }

    func isConversationMuted(_ conversation: Conversation, now: Date = .now) -> Bool {
        chatPreferences.isMuted(conversation.conversationId, now: now)
    }

    func isConversationManuallyUnread(_ conversation: Conversation) -> Bool {
        chatPreferences.isManuallyUnread(conversation.conversationId)
    }

    func conversationHasVisibleUnread(_ conversation: Conversation) -> Bool {
        let snapshot = ChatConversationPreferences.snapshot(for: conversation)
        if chatPreferences.readOverrideMatches(conversationId: conversation.conversationId, snapshot: snapshot) {
            return false
        }
        return conversation.hasUnreadMessages || isConversationManuallyUnread(conversation)
    }

    func visibleUnreadCount(for conversation: Conversation) -> Int {
        guard conversationHasVisibleUnread(conversation) else { return 0 }
        return max(conversation.unreadCount, 1)
    }

    func togglePinnedConversation(_ conversation: Conversation) {
        setConversationPinned(conversation, enabled: !isConversationPinned(conversation))
    }

    func movePinnedConversation(_ conversationId: String, toIndex targetIndex: Int) {
        let previousOrder = chatPreferences.normalized.pinnedConversationIds
        chatPreferences = chatPreferences.movingPinnedConversation(conversationId, toIndex: targetIndex)
        guard chatPreferences.pinnedConversationIds != previousOrder else { return }
        persistChatConversationPreferences()

        Task {
            await appendEvent(
                kind: .favoriteConversationUpdated,
                relatedId: conversationId,
                summary: "Poradi pripnutych konverzaci upraveno.",
                metadata: [
                    "conversationId": conversationId
                ]
            )
        }
    }

    private func setPinnedConversation(_ conversation: Conversation?) {
        if let conversation {
            setConversationPinned(conversation, enabled: true)
        } else {
            let previous = pinnedConversationId
            if let previous {
                chatPreferences = chatPreferences.settingPinned(previous, enabled: false)
            }
            persistChatConversationPreferences()
        }
    }

    private func setConversationPinned(_ conversation: Conversation, enabled: Bool) {
        let previous = pinnedConversationId
        chatPreferences = chatPreferences.settingPinned(conversation.conversationId, enabled: enabled)
        persistChatConversationPreferences()

        Task {
            await appendEvent(
                kind: .favoriteConversationUpdated,
                relatedId: enabled ? conversation.conversationId : previous,
                summary: enabled ? "Konverzace pripnuta." : "Konverzace odepnuta.",
                metadata: [
                    "conversationId": conversation.conversationId,
                    "previousConversationId": previous ?? ""
                ]
            )
        }
    }

    func toggleConversationMuted(_ conversation: Conversation) {
        let willMute = !isConversationMuted(conversation)
        chatPreferences = chatPreferences.settingMuted(
            conversation.conversationId,
            until: willMute ? ChatConversationPreferences.farFutureMuteDate : nil
        )
        persistChatConversationPreferences()

        Task {
            await appendEvent(
                kind: .favoriteConversationUpdated,
                relatedId: conversation.conversationId,
                summary: willMute ? "Konverzace ztlumena." : "Ztlumeni konverzace zruseno.",
                metadata: [
                    "conversationId": conversation.conversationId,
                    "presentationState": willMute ? "muted" : "unmuted"
                ]
            )
            await refreshChatNotificationSurfaces(syncWatch: true)
        }
    }

    func toggleConversationUnread(_ conversation: Conversation) {
        let snapshot = ChatConversationPreferences.snapshot(for: conversation)
        let hadVisibleUnread = conversationHasVisibleUnread(conversation)
        if hadVisibleUnread {
            markConversationReadLocally(conversation, snapshot: snapshot)
        } else {
            chatPreferences = chatPreferences.settingManualUnread(conversation.conversationId, enabled: true)
            persistChatConversationPreferences()
        }
        Task {
            await refreshChatNotificationSurfaces(syncWatch: true)
        }
    }

    private func markConversationReadLocally(_ conversation: Conversation, snapshot: String? = nil) {
        chatPreferences = chatPreferences.settingReadOverride(
            conversation.conversationId,
            snapshot: snapshot ?? ChatConversationPreferences.snapshot(for: conversation)
        )
        persistChatConversationPreferences()
    }

    func hideConversationFromList(_ conversation: Conversation) {
        chatPreferences = chatPreferences.settingHidden(
            conversation.conversationId,
            snapshot: ChatConversationPreferences.snapshot(for: conversation)
        )
        if selectedConversation?.conversationId == conversation.conversationId {
            selectedConversation = visibleConversations.first { $0.conversationId != conversation.conversationId }
            messages = []
            loadingConversationId = nil
            stopActiveConversationStreams()
        }
        persistChatConversationPreferences()
        Task {
            await clearLocalConversationTimelineCache(conversationId: conversation.conversationId)
            await refreshChatNotificationSurfaces(syncWatch: true)
        }
    }

    @discardableResult
    func leaveGroupConversation(_ conversation: Conversation) async -> Bool {
        guard conversation.type == .group else {
            lastError = CSMLocalization.text(
                "conversation.leave.error.not_group",
                fallback: "Opustit lze jen skupinovou konverzaci."
            )
            return false
        }
        guard conversation.activeMatrixRoomId != nil else {
            lastError = CSMLocalization.text(
                "conversation.leave.error.missing_room",
                fallback: "Skupina nemá aktivní Matrix room. Můžete ji jen skrýt ze seznamu."
            )
            return false
        }

        do {
            try await messaging.leaveConversation(conversation)
            chatPreferences = chatPreferences.removingConversationPresentation(conversation.conversationId)
            conversations.removeAll { $0.conversationId == conversation.conversationId }
            if selectedConversation?.conversationId == conversation.conversationId {
                selectedConversation = nil
                messages = []
                loadingConversationId = nil
                stopActiveConversationStreams()
            }
            persistChatConversationPreferences()
            await clearLocalConversationTimelineCache(conversationId: conversation.conversationId)
            _ = try? await messageOutbox?.discardPendingMessages(for: conversation.conversationId)
            await refreshPendingMessageCount()
            await refreshChatNotificationSurfaces(syncWatch: true)
            conversationActionStatusText = CSMLocalization.text(
                "conversation.leave.status.left",
                fallback: "Skupinu jste opustil/a."
            )
            await appendEvent(
                kind: .conversationMembersUpdated,
                relatedId: conversation.conversationId,
                summary: "Skupina opustena z iOS aplikace.",
                metadata: [
                    "conversationId": conversation.conversationId,
                    "matrixRoomId": conversation.activeMatrixRoomId ?? "",
                    "action": "matrix_leave"
                ]
            )
            return true
        } catch {
            lastError = error.localizedDescription
            messagingTransportErrorText = error.localizedDescription
            await appendEvent(
                kind: .conversationMetadataFallback,
                relatedId: conversation.conversationId,
                summary: "Opuštění skupiny přes Matrix selhalo.",
                metadata: [
                    "conversationId": conversation.conversationId,
                    "matrixRoomId": conversation.activeMatrixRoomId ?? "",
                    "error": error.localizedDescription
                ]
            )
            return false
        }
    }

    func clearConversationActionStatus() {
        conversationActionStatusText = nil
    }

    private func stopActiveConversationStreams() {
        timelineSynchronization.stop()
    }

    private func clearLocalConversationTimelineCache(conversationId: String) async {
        do {
            try await messageHistory?.removeMessages(for: conversationId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistChatConversationPreferences() {
        chatPreferences = chatPreferences.normalized
        pinnedConversationId = chatPreferences.pinnedConversationIds.first
        if let actor {
            Self.writeChatConversationPreferences(chatPreferences, subjectId: actor.subjectId)
            Self.writePinnedConversationId(pinnedConversationId, subjectId: actor.subjectId)
        }
        conversations = prioritizedConversations(conversations)
    }

    @discardableResult
    func createGroupConversation(title: String, members: [ConversationMemberDraft]) async -> Conversation? {
        let draft = ConversationDraft(
            type: .group,
            title: title,
            members: members,
            metadata: [
                "createdFrom": "ios",
                "clientCapability": "offline_first"
            ]
        )
        return await createConversation(draft)
    }

    @discardableResult
    func createDirectConversation(userId: String, displayName: String?) async -> Conversation? {
        if let existing = existingDirectConversation(userId: userId) {
            selectedConversation = existing
            return existing
        }
        let member = ConversationMemberDraft(userId: userId, displayName: displayName)
        let draft = ConversationDraft(
            type: .direct,
            title: member.displayName ?? member.userId,
            members: [member],
            metadata: [
                "createdFrom": "ios",
                "clientCapability": "offline_first",
                "externalId": userId,
                "source": "cop.direct"
            ]
        )
        return await createConversation(draft)
    }

    @discardableResult
    func openOrCreateAIAssistantConversation() async -> Conversation? {
        if let existing = prioritizedConversations(conversations).first(where: \.isAIAssistantConversation) {
            selectedConversation = existing
            return existing
        }

        let draft = ConversationDraft(
            type: .direct,
            conversationKind: .personalAI,
            title: Self.aiAssistantDisplayName,
            members: [
                ConversationMemberDraft(
                    userId: Self.aiAssistantUserId,
                    displayName: Self.aiAssistantDisplayName,
                    role: "bot"
                )
            ],
            metadata: [
                "createdFrom": "ios",
                "clientCapability": "offline_first",
                "externalId": Self.aiAssistantUserId,
                "source": "cop.ai.direct"
            ]
        )
        return await createConversation(draft)
    }

    private func existingDirectConversation(userId: String) -> Conversation? {
        let normalizedUserId = ConversationIdentity.canonicalKey(userId)
        guard !normalizedUserId.isEmpty else { return nil }
        return prioritizedConversations(conversations).first { conversation in
            guard conversation.type == .direct, !conversation.isAIAssistantConversation else { return false }
            if ConversationIdentity.canonicalKey(conversation.metadata["externalId"] ?? "") == normalizedUserId {
                return true
            }
            return conversation.members.contains { member in
                Self.identityVariants(member.userId).contains(normalizedUserId)
            }
        }
    }

    @discardableResult
    func addMembers(to conversation: Conversation, members: [ConversationMemberDraft]) async -> Conversation? {
        conversationOperationErrorText = nil
        guard conversation.type == .group else {
            conversationOperationErrorText = "Cleny lze spravovat jen u skupinove konverzace."
            lastError = conversationOperationErrorText
            return nil
        }
        guard let conversationMetadata else {
            conversationOperationErrorText = "COP metadata klient neni dostupny."
            lastError = conversationOperationErrorText
            return nil
        }

        let filteredMembers = newMemberDrafts(for: conversation, from: members)
        guard !filteredMembers.isEmpty else {
            conversationOperationErrorText = "Vybrani lide uz ve skupine jsou."
            lastError = conversationOperationErrorText
            return nil
        }

        do {
            let updatedConversation = try await conversationMetadata.addConversationMembers(
                conversationId: conversation.conversationId,
                members: filteredMembers
            )
            upsertConversation(updatedConversation)
            if selectedConversation?.conversationId == updatedConversation.conversationId {
                selectedConversation = updatedConversation
            }
            await appendEvent(
                kind: .conversationMembersUpdated,
                relatedId: updatedConversation.conversationId,
                summary: "Clenove skupiny aktualizovani.",
                metadata: [
                    "conversationId": updatedConversation.conversationId,
                    "addedMembers": "\(filteredMembers.count)",
                    "memberCount": "\(updatedConversation.memberCount)",
                    "matrixState": updatedConversation.matrix?.state ?? "unknown"
                ]
            )
            conversationOperationErrorText = nil
            return updatedConversation
        } catch {
            conversationOperationErrorText = error.localizedDescription
            lastError = error.localizedDescription
            await appendEvent(
                kind: .conversationMetadataFallback,
                relatedId: conversation.conversationId,
                summary: "Pridani clenu do skupiny pres COP selhalo.",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    @discardableResult
    func updateGroupConversationAvatar(
        _ avatarDataUrl: String?,
        for conversation: Conversation
    ) async throws -> Conversation {
        guard conversation.type == .group else {
            throw CSMServiceError.invalidState("Avatar lze nastavit jen skupinové konverzaci.")
        }
        guard let updater = messaging as? any MessagingConversationAvatarUpdating else {
            throw CSMServiceError.unavailable("Tento komunikační kanál nepodporuje změnu avataru skupiny.")
        }

        let updatedConversation: Conversation
        do {
            updatedConversation = try await updater.updateGroupConversationAvatar(avatarDataUrl, for: conversation)
        } catch {
            guard Self.isMessagingAuthenticationFailure(error), let actor else {
                throw error
            }
            await clearCachedMessagingBootstrap(for: actor)
            lastMessagingBootstrap = nil
            messagingBootstrapExpiresAt = nil
            messagingBootstrapIssuedAt = nil
            messagingBootstrapNetworkRetryNotBefore = nil
            await configureMessaging(for: actor)
            do {
                updatedConversation = try await updater.updateGroupConversationAvatar(avatarDataUrl, for: conversation)
            } catch {
                if Self.isMessagingAuthenticationFailure(error) {
                    throw CSMServiceError.authenticationRequired(CSMLocalization.text(
                        "conversation.group.avatar.auth_failed",
                        fallback: "Přihlášení k chatu se nepodařilo automaticky obnovit. Zavřete Zprávy, znovu je otevřete a akci opakujte."
                    ))
                }
                throw error
            }
        }
        upsertConversation(updatedConversation)
        if selectedConversation?.conversationId == updatedConversation.conversationId {
            selectedConversation = updatedConversation
        }
        return updatedConversation
    }

    nonisolated private static func isMessagingAuthenticationFailure(_ error: any Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.contains("m_unknown_token") ||
            description.contains("unknown token") ||
            description.contains("access token expired") ||
            description.contains("soft_logout") ||
            description.contains("unauthorized") ||
            description.contains("401")
    }

    private func createConversation(_ draft: ConversationDraft) async -> Conversation? {
        conversationOperationErrorText = nil
        guard draft.isValid else {
            conversationOperationErrorText = "Konverzace nema platny nazev nebo cleny."
            lastError = conversationOperationErrorText
            return nil
        }
        guard let conversationMetadata else {
            conversationOperationErrorText = "COP metadata klient neni dostupny."
            lastError = conversationOperationErrorText
            return nil
        }

        do {
            let createdConversation = try await conversationMetadata.createConversation(draft)
            let conversation = await ensureMatrixRoomIfNeeded(createdConversation, trigger: "create")
            upsertConversation(conversation)
            selectedConversation = conversation
            messages = []
            loadingConversationId = nil
            await appendEvent(
                kind: .conversationCreated,
                relatedId: conversation.conversationId,
                summary: conversation.type == .group ? "Skupinova konverzace vytvorena." : "Prima konverzace vytvorena.",
                metadata: [
                    "conversationId": conversation.conversationId,
                    "type": conversation.type.rawValue,
                    "members": "\(draft.members.count)",
                    "matrixState": conversation.matrix?.state ?? "unknown"
                ]
            )
            conversationOperationErrorText = nil
            return conversation
        } catch {
            conversationOperationErrorText = error.localizedDescription
            lastError = error.localizedDescription
            await appendEvent(
                kind: .conversationMetadataFallback,
                summary: "Vytvoreni konverzace pres COP selhalo.",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func newMemberDrafts(
        for conversation: Conversation,
        from members: [ConversationMemberDraft]
    ) -> [ConversationMemberDraft] {
        var seen = Set(conversation.members.map { ConversationIdentity.canonicalKey($0.userId) })
        let selfIdentifiers = Self.selfIdentifierSet(actor)

        return members.compactMap { draft in
            let normalizedId = ConversationIdentity.canonicalKey(draft.userId)
            guard !normalizedId.isEmpty else { return nil }
            guard !seen.contains(normalizedId), !selfIdentifiers.contains(normalizedId) else { return nil }
            seen.insert(normalizedId)
            return ConversationMemberDraft(userId: draft.userId, displayName: draft.displayName, role: draft.role)
        }
    }

    private func prioritizedConversations(_ values: [Conversation]) -> [Conversation] {
        let values = Self.normalizedConversationList(
            values,
            actor: actor,
            matrixUserId: lastMessagingBootstrap?.userId
        )
        var pinnedIds = chatPreferences.pinnedConversationIds
        if let pinnedConversationId, !pinnedIds.contains(pinnedConversationId) {
            pinnedIds.insert(pinnedConversationId, at: 0)
        }
        guard !pinnedIds.isEmpty else {
            return values.sorted(by: conversationPresentationSort)
        }
        let pinnedOrder = Dictionary(uniqueKeysWithValues: pinnedIds.enumerated().map { ($1, $0) })
        return values.sorted { left, right in
            let leftPinnedOrder = pinnedOrder[left.conversationId]
            let rightPinnedOrder = pinnedOrder[right.conversationId]
            if let leftPinnedOrder, let rightPinnedOrder, leftPinnedOrder != rightPinnedOrder {
                return leftPinnedOrder < rightPinnedOrder
            }
            if leftPinnedOrder != nil { return true }
            if rightPinnedOrder != nil { return false }
            return conversationPresentationSort(left, right)
        }
    }

    /// Produces the single presentation model used by COP Mobile. COP metadata
    /// and Matrix can temporarily describe the same chat twice; direct-chat
    /// metadata can also carry the current user's title/avatar before member
    /// details arrive. Normalize both cases before SwiftUI receives the list.
    nonisolated static func normalizedConversationList(
        _ values: [Conversation],
        actor: AuthenticatedActor?,
        matrixUserId: String? = nil
    ) -> [Conversation] {
        let selfIds = selfIdentifierSet(actor, matrixUserId: matrixUserId)
        var mergedByKey: [String: Conversation] = [:]

        for value in values {
            let presented = presentedConversation(value, selfIds: selfIds)
            let key = conversationDedupeKey(presented, selfIds: selfIds)
            if let existing = mergedByKey[key] {
                mergedByKey[key] = mergeConversation(existing, with: presented, selfIds: selfIds)
            } else {
                mergedByKey[key] = presented
            }
        }
        return Array(mergedByKey.values)
    }

    private func enrichedConversationList(_ values: [Conversation]) async -> [Conversation] {
        guard let messageHistory else { return prioritizedConversations(values) }
        var enriched = values
        for index in enriched.indices {
            let cached = (try? await messageHistory.messages(for: enriched[index].conversationId)) ?? []
            guard let latest = cached.filter({ !$0.isDeleted }).max(by: { $0.sentAt < $1.sentAt }) else { continue }
            if enriched[index].lastActivityAt == nil || latest.sentAt >= (enriched[index].lastActivityAt ?? .distantPast) {
                enriched[index].lastActivityAt = latest.sentAt
                enriched[index].lastActivityPreview = Self.messageListPreview(latest)
            }
        }
        return prioritizedConversations(enriched)
    }

    private func enrichedConversationPresentations(_ values: [Conversation]) async -> [Conversation] {
        guard let enricher = messaging as? any MessagingConversationPresentationEnriching else {
            return prioritizedConversations(values)
        }
        var enriched: [Conversation] = []
        enriched.reserveCapacity(values.count)
        for conversation in values {
            enriched.append(await enricher.enrichedConversationPresentation(conversation))
        }
        return prioritizedConversations(enriched)
    }

    private func requestAIAgentResponse(
        question: String,
        modelPreference: ChatAIModelPreference,
        conversation: Conversation
    ) async {
        aiAgentStatusConversationId = conversation.conversationId
        aiAgentStatusText = "COP AI vybírá relevantní data a připravuje odpověď…"
        defer {
            if aiAgentStatusConversationId == conversation.conversationId {
                aiAgentStatusConversationId = nil
                aiAgentStatusText = nil
            }
        }
        do {
            let currentLocation = await aiCurrentLocationProvider?()
            let response = try await api.queryAIChatAgent(
                CopAIChatAgentRequest(
                    question: question,
                    chatContext: Self.aiChatContext(
                        from: messages,
                        conversation: conversation
                    ),
                    conversationId: conversation.conversationId,
                    groupId: conversation.linkedCommunityGroupId,
                    modelPreference: modelPreference.rawValue,
                    currentLocation: currentLocation
                )
            )
            guard response.status == "COMPLETED",
                  let summary = response.summary else {
                throw CSMServiceError.unavailable("COP AI agent nevratil dokoncenou odpoved.")
            }
            let body = "COP AI agent\nDotaz: \(question)\n\n\(summary)"
            let answer = try await messaging.sendMessage(body, to: conversation)
            if !messages.contains(where: { $0.id == answer.id }) {
                timelineStore.send(.upsert(answer))
            }
            await appendEvent(
                kind: .messageSendConfirmed,
                relatedId: answer.id,
                summary: "Odpoved COP AI agenta byla vlozena do E2EE konverzace.",
                metadata: ["conversationId": conversation.conversationId]
            )
        } catch {
            lastError = error.localizedDescription
            await appendEvent(
                kind: .messageSendFailed,
                relatedId: conversation.conversationId,
                summary: "COP AI agent nedokoncil odpoved na nativni dotaz.",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    nonisolated private static func aiInvocation(
        for draft: OutgoingMessageDraft,
        conversation: Conversation
    ) -> ChatAIInvocation? {
        guard draft.attachments.isEmpty else { return nil }
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.hasPrefix("COP AI agent\n") else { return nil }
        return ChatInteractionRegistry.aiInvocation(
            for: body,
            directAIChat: conversation.isAIAssistantConversation,
            groupAIAssistantEnabled: conversation.linkedCommunityGroupId != nil
        )
    }

    nonisolated private static func aiChatContext(
        from visibleMessages: [ChatMessage],
        conversation: Conversation
    ) -> CopAIChatAgentContextSnapshot {
        let eligible = visibleMessages.filter { message in
            let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBody = body.folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "cs_CZ")
            )
            return !message.isDeleted &&
                !body.isEmpty &&
                !normalizedBody.contains("nepodarilo desifrovat") &&
                !normalizedBody.contains("unable to decrypt")
        }
        let included = Array(eligible.suffix(30)).map { message in
            CopAIChatAgentContextMessage(
                body: String(message.body.prefix(1_200)),
                eventId: message.id.hasPrefix("$") ? message.id : nil,
                kind: message.attachments.first?.kind.rawValue ?? "text",
                own: message.isOwnMessage,
                replyToEventId: message.replyTo?.messageId,
                sender: String(message.senderId.prefix(160)),
                senderDisplayName: String(message.senderDisplayName.prefix(160)),
                timestamp: message.sentAt
            )
        }
        return CopAIChatAgentContextSnapshot(
            roomId: conversation.activeMatrixRoomId,
            encrypted: conversation.encrypted || conversation.e2eeRequired,
            visibleMessageCount: min(5_000, eligible.count),
            includedMessageCount: included.count,
            messages: included
        )
    }

    nonisolated private static func messageListPreview(_ message: ChatMessage) -> String {
        let body = message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty { return body }
        return message.attachments.first?.title ?? CSMLocalization.text("message.preview.default", fallback: "Zpráva")
    }

    nonisolated private static func conversationDedupeKey(
        _ conversation: Conversation,
        selfIds: Set<String>
    ) -> String {
        if let canonicalKey = nonEmptyValue(conversation.canonicalKey) {
            return "canonical:\(canonicalKey)"
        }
        if conversation.type == .direct,
           let peer = directPeer(in: conversation, selfIds: selfIds) {
            return "direct:\(normalizedMatrixIdentity(peer.userId))"
        }
        if conversation.type == .direct {
            return "direct-title:\(normalizedIdentity(conversation.title))"
        }
        return "conversation:\(conversation.conversationId)"
    }

    nonisolated private static func presentedConversation(
        _ conversation: Conversation,
        selfIds: Set<String>
    ) -> Conversation {
        var result = conversation
        result.members = deduplicatedMembers(conversation.members)
        if result.type == .direct && !result.members.isEmpty {
            result.memberCount = result.members.count
        }

        guard result.type == .direct,
              let peer = directPeer(in: result, selfIds: selfIds) else {
            return result
        }
        if let displayName = nonEmptyValue(peer.displayName) {
            result.title = displayName
        } else if !peer.userId.isEmpty {
            result.title = peer.userId
        }
        result.conversationAvatarDataUrl = nonEmptyValue(peer.avatarDataUrl)
        result.conversationAvatarUrl = nonEmptyValue(peer.avatarUrl)
        return result
    }

    nonisolated private static func deduplicatedMembers(
        _ members: [ConversationMember]
    ) -> [ConversationMember] {
        var membersById: [String: ConversationMember] = [:]
        for member in members {
            let key = ConversationIdentity.canonicalKey(member.userId)
            guard !key.isEmpty else { continue }
            if let existing = membersById[key] {
                membersById[key] = ConversationMember(
                    userId: ConversationIdentity.preferredPersistentId(existing.userId, member.userId),
                    displayName: nonEmptyValue(existing.displayName) ?? nonEmptyValue(member.displayName),
                    role: nonEmptyValue(existing.role) ?? nonEmptyValue(member.role),
                    avatarDataUrl: nonEmptyValue(existing.avatarDataUrl) ?? nonEmptyValue(member.avatarDataUrl),
                    avatarUrl: nonEmptyValue(existing.avatarUrl) ?? nonEmptyValue(member.avatarUrl)
                )
            } else {
                membersById[key] = member
            }
        }
        return Array(membersById.values)
    }

    nonisolated private static func directPeer(
        in conversation: Conversation,
        selfIds: Set<String>
    ) -> ConversationMember? {
        let candidates = conversation.members.filter { member in
            let memberIds = identityVariants(member.userId)
                .union(member.displayName.map(identityVariants) ?? [])
            return memberIds.isDisjoint(with: selfIds)
        }
        let normalizedTitle = normalizedIdentity(conversation.title)
        if let titledPeer = candidates.first(where: { member in
            normalizedIdentity(member.displayName ?? member.userId) == normalizedTitle
        }) {
            return titledPeer
        }
        return candidates.first
    }

    nonisolated private static func mergeConversation(
        _ left: Conversation,
        with right: Conversation,
        selfIds: Set<String>
    ) -> Conversation {
        let leftScore = conversationRichness(left)
        let rightScore = conversationRichness(right)
        var result = leftScore >= rightScore ? left : right
        let other = leftScore >= rightScore ? right : left

        var membersById: [String: ConversationMember] = [:]
        for member in other.members + result.members {
            let key = ConversationIdentity.canonicalKey(member.userId)
            guard !key.isEmpty else { continue }
            if let existing = membersById[key] {
                membersById[key] = ConversationMember(
                    userId: ConversationIdentity.preferredPersistentId(existing.userId, member.userId),
                    displayName: nonEmptyValue(existing.displayName) ?? nonEmptyValue(member.displayName),
                    role: nonEmptyValue(existing.role) ?? nonEmptyValue(member.role),
                    avatarDataUrl: nonEmptyValue(existing.avatarDataUrl) ?? nonEmptyValue(member.avatarDataUrl),
                    avatarUrl: nonEmptyValue(existing.avatarUrl) ?? nonEmptyValue(member.avatarUrl)
                )
            } else {
                membersById[key] = member
            }
        }
        result.members = Array(membersById.values)
        result.memberCount = result.type == .direct && !result.members.isEmpty
            ? result.members.count
            : max(max(left.memberCount, right.memberCount), result.members.count)
        result.unreadCount = max(left.unreadCount, right.unreadCount)
        result.matrix = result.matrix ?? other.matrix
        result.lastActivityPreview = nonEmptyValue(result.lastActivityPreview) ?? nonEmptyValue(other.lastActivityPreview)
        result.lastActivityAt = maxOptionalDate(left.lastActivityAt, right.lastActivityAt)
        result.updatedAt = maxOptionalDate(left.updatedAt, right.updatedAt)
        result.conversationAvatarDataUrl = nonEmptyValue(result.conversationAvatarDataUrl) ?? nonEmptyValue(other.conversationAvatarDataUrl)
        result.conversationAvatarUrl = nonEmptyValue(result.conversationAvatarUrl) ?? nonEmptyValue(other.conversationAvatarUrl)
        result.metadata = other.metadata.merging(result.metadata) { _, preferred in preferred }
        return presentedConversation(result, selfIds: selfIds)
    }

    nonisolated private static func conversationRichness(_ conversation: Conversation) -> Int {
        (conversation.activeMatrixRoomId == nil ? 0 : 100) +
            (nonEmptyValue(conversation.lastActivityPreview) == nil ? 0 : 20) +
            (conversation.avatarDataUrl == nil && conversation.avatarUrl == nil ? 0 : 10) +
            min(conversation.members.count, 9)
    }

    nonisolated private static func maxOptionalDate(_ left: Date?, _ right: Date?) -> Date? {
        switch (left, right) {
        case let (left?, right?): max(left, right)
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
    }

    private func conversationPresentationSort(_ left: Conversation, _ right: Conversation) -> Bool {
        let leftUnread = conversationHasVisibleUnread(left)
        let rightUnread = conversationHasVisibleUnread(right)
        if leftUnread != rightUnread {
            return leftUnread
        }
        let leftDate = left.lastActivityAt ?? left.updatedAt ?? .distantPast
        let rightDate = right.lastActivityAt ?? right.updatedAt ?? .distantPast
        if leftDate != rightDate {
            return leftDate > rightDate
        }
        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    nonisolated static func knownRecipients(
        actor: AuthenticatedActor?,
        conversations: [Conversation]
    ) -> [ConversationRecipient] {
        var recipientsById: [String: ConversationRecipient] = [:]
        let selfIdentifiers = selfIdentifierSet(actor)

        for conversation in conversations {
            for member in conversation.members {
                let userId = member.userId.trimmingCharacters(in: .whitespacesAndNewlines)
                let identityKey = ConversationIdentity.canonicalKey(userId)
                guard !userId.isEmpty else { continue }
                guard !selfIdentifiers.contains(identityKey) else { continue }
                if let displayName = member.displayName,
                   selfIdentifiers.contains(Self.normalizedIdentity(displayName)) {
                    continue
                }

                let displayName = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let recipient = ConversationRecipient(
                    userId: userId,
                    displayName: displayName?.isEmpty == false ? displayName : nil,
                    role: member.role,
                    avatarDataUrl: nonEmptyValue(member.avatarDataUrl),
                    avatarUrl: nonEmptyValue(member.avatarUrl),
                    sourceConversationTitle: conversation.title
                )

                if let existing = recipientsById[identityKey] {
                    recipientsById[identityKey] = mergedRecipient(existing, with: recipient)
                } else {
                    recipientsById[identityKey] = recipient
                }
            }
        }

        return recipientsById.values.sorted { left, right in
            let leftHasDisplayName = left.displayName?.isEmpty == false
            let rightHasDisplayName = right.displayName?.isEmpty == false
            if leftHasDisplayName != rightHasDisplayName {
                return leftHasDisplayName
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    nonisolated static func mergedRecipients(_ recipients: [ConversationRecipient]) -> [ConversationRecipient] {
        var recipientsById: [String: ConversationRecipient] = [:]
        for recipient in recipients {
            let userId = recipient.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            let identityKey = ConversationIdentity.canonicalKey(userId)
            guard !userId.isEmpty else { continue }
            if let existing = recipientsById[identityKey] {
                recipientsById[identityKey] = mergedRecipient(existing, with: recipient)
            } else {
                recipientsById[identityKey] = recipient
            }
        }
        return recipientsById.values.sorted { left, right in
            let leftHasDisplayName = left.displayName?.isEmpty == false
            let rightHasDisplayName = right.displayName?.isEmpty == false
            if leftHasDisplayName != rightHasDisplayName {
                return leftHasDisplayName
            }
            return left.title.localizedStandardCompare(right.title) == .orderedAscending
        }
    }

    nonisolated private static func mergedRecipient(
        _ existing: ConversationRecipient,
        with candidate: ConversationRecipient
    ) -> ConversationRecipient {
        ConversationRecipient(
            userId: existing.userId,
            displayName: existing.displayName?.isEmpty == false ? existing.displayName : candidate.displayName,
            role: existing.role ?? candidate.role,
            handle: existing.handle ?? candidate.handle,
            avatarDataUrl: existing.avatarDataUrl ?? candidate.avatarDataUrl,
            avatarUrl: existing.avatarUrl ?? candidate.avatarUrl,
            sourceConversationTitle: existing.sourceConversationTitle ?? candidate.sourceConversationTitle
        )
    }

    nonisolated private static func nonEmptyValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    nonisolated private static func selfIdentifierSet(
        _ actor: AuthenticatedActor?,
        matrixUserId: String? = nil
    ) -> Set<String> {
        let values = [actor?.subjectId, actor?.username, actor?.displayName, matrixUserId].compactMap { $0 }
        return values.reduce(into: Set<String>()) { result, value in
            result.formUnion(identityVariants(value))
        }
    }

    nonisolated private static func identityVariants(_ value: String) -> Set<String> {
        ConversationIdentity.variants(value)
    }

    nonisolated private static func normalizedMatrixIdentity(_ value: String) -> String {
        ConversationIdentity.canonicalKey(value)
    }

    nonisolated private static func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func readPinnedConversationId(subjectId: String) -> String? {
        let value = UserDefaults.standard.string(forKey: pinnedConversationStorageKey(subjectId: subjectId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    private static func writePinnedConversationId(_ conversationId: String?, subjectId: String) {
        let key = pinnedConversationStorageKey(subjectId: subjectId)
        if let conversationId, !conversationId.isEmpty {
            UserDefaults.standard.set(conversationId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func pinnedConversationStorageKey(subjectId: String) -> String {
        "cz.zeleznalady.csm.favoriteConversation.\(subjectId)"
    }

    private static func readChatConversationPreferences(subjectId: String) -> ChatConversationPreferences? {
        guard let data = UserDefaults.standard.data(
            forKey: chatConversationPreferencesStorageKey(subjectId: subjectId)
        ) else {
            return nil
        }
        return (try? CSMJSONCoding.decoder.decode(ChatConversationPreferences.self, from: data))?.normalized
    }

    private static func writeChatConversationPreferences(
        _ preferences: ChatConversationPreferences,
        subjectId: String
    ) {
        guard let data = try? CSMJSONCoding.encoder.encode(preferences.normalized) else { return }
        UserDefaults.standard.set(data, forKey: chatConversationPreferencesStorageKey(subjectId: subjectId))
    }

    private static func clearChatConversationPreferences(subjectId: String) {
        UserDefaults.standard.removeObject(forKey: chatConversationPreferencesStorageKey(subjectId: subjectId))
        UserDefaults.standard.removeObject(forKey: pinnedConversationStorageKey(subjectId: subjectId))
    }

    private static func chatConversationPreferencesStorageKey(subjectId: String) -> String {
        "cz.zeleznalady.csm.chatConversationPreferences.\(subjectId)"
    }

    private static func readNotificationPreferences(subjectId: String) -> CSMNotificationPreferences? {
        guard let data = UserDefaults.standard.data(forKey: notificationPreferencesStorageKey(subjectId: subjectId)) else {
            return nil
        }
        return try? CSMJSONCoding.decoder.decode(CSMNotificationPreferences.self, from: data)
    }

    private static func writeNotificationPreferences(_ preferences: CSMNotificationPreferences, subjectId: String) {
        guard let data = try? CSMJSONCoding.encoder.encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: notificationPreferencesStorageKey(subjectId: subjectId))
    }

    private static func clearNotificationPreferences(subjectId: String) {
        UserDefaults.standard.removeObject(forKey: notificationPreferencesStorageKey(subjectId: subjectId))
    }

    private static func notificationPreferencesStorageKey(subjectId: String) -> String {
        "cz.zeleznalady.csm.notificationPreferences.\(subjectId)"
    }

    private static func readNotificationSubscriptions(subjectId: String) -> CSMNotificationSubscriptions? {
        guard let data = UserDefaults.standard.data(forKey: notificationSubscriptionsStorageKey(subjectId: subjectId)) else {
            return nil
        }
        return try? CSMJSONCoding.decoder.decode(CSMNotificationSubscriptions.self, from: data)
    }

    private static func writeNotificationSubscriptions(_ subscriptions: CSMNotificationSubscriptions, subjectId: String) {
        guard let data = try? CSMJSONCoding.encoder.encode(subscriptions) else { return }
        UserDefaults.standard.set(data, forKey: notificationSubscriptionsStorageKey(subjectId: subjectId))
    }

    private static func clearNotificationSubscriptions(subjectId: String) {
        UserDefaults.standard.removeObject(forKey: notificationSubscriptionsStorageKey(subjectId: subjectId))
    }

    private static func notificationSubscriptionsStorageKey(subjectId: String) -> String {
        "cz.zeleznalady.csm.notificationSubscriptions.\(subjectId)"
    }

    private func reconcileMatrixDeviceGeneration(for subjectId: String) async {
        let key = Self.matrixDeviceGenerationStorageKey(subjectId: subjectId)
        let storedGeneration = UserDefaults.standard.string(forKey: key)
        guard storedGeneration != Self.matrixDeviceGeneration else { return }

        do {
            if let messageOutbox {
                try await messageOutbox.clear()
            }
            if let messageHistory {
                try await messageHistory.clear()
            }
            pendingMessageCount = 0
            messages = []
            loadingConversationId = nil
            messagingTransportErrorText = nil
            messageOutboxSyncStatusText = "idle"
            pendingAutoSyncAttemptedConversationIds = []
            pendingAutoSyncInFlightConversationIds = []
            UserDefaults.standard.set(Self.matrixDeviceGeneration, forKey: key)
            await appendEvent(
                kind: .messageOutboxDiscarded,
                summary: "Lokalni Matrix E2EE store byl prepnut na novou generaci a stara odesilaci fronta byla vycistena.",
                subjectIdOverride: subjectId,
                metadata: [
                    "previousGeneration": storedGeneration ?? "unset",
                    "currentGeneration": Self.matrixDeviceGeneration
                ]
            )
        } catch {
            lastError = error.localizedDescription
            await appendEvent(
                kind: .messageOutboxSyncFailed,
                summary: "Vycisteni stare Matrix E2EE fronty pri migraci selhalo.",
                subjectIdOverride: subjectId,
                metadata: [
                    "error": error.localizedDescription,
                    "currentGeneration": Self.matrixDeviceGeneration
                ]
            )
        }
    }

    private static func matrixDeviceGenerationStorageKey(subjectId: String) -> String {
        "cz.zeleznalady.csm.matrixDeviceGeneration.\(subjectId)"
    }

    private static func conversation(_ conversation: Conversation, matchesRoomReference roomReference: String) -> Bool {
        conversation.conversationId == roomReference ||
            conversation.matrix?.roomId == roomReference ||
            conversation.mapLinks.contains { $0.targetId == roomReference }
    }

    private static func tokenFingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func sendMessage(_ body: String) async -> Bool {
        await sendMessage(OutgoingMessageDraft(body: body))
    }

    func startLiveLocationShare(
        durationSeconds: TimeInterval,
        in conversation: Conversation,
        locationProvider:
            @escaping @MainActor @Sendable () async throws -> CSMCommunicationLocation
    ) async throws {
        guard let liveLocationClient = messaging as? any MessagingLiveLocationSharing else {
            throw CSMServiceError.unavailable("Živá poloha teď není dostupná.")
        }

        if activeLiveLocationShare != nil {
            try? await stopLiveLocationShare()
        }

        let boundedDuration = min(max(durationSeconds, 15 * 60), 8 * 60 * 60)
        let firstSample = try await locationProvider()
        let point = Self.geoPoint(from: firstSample)

        try await liveLocationClient.startLiveLocationShare(
            durationSeconds: boundedDuration,
            in: conversation
        )
        do {
            try await liveLocationClient.updateLiveLocation(point, in: conversation)
        } catch {
            try? await liveLocationClient.stopLiveLocationShare(in: conversation)
            throw error
        }

        let startedAt = Date()
        let share = ActiveLiveLocationShare(
            conversationId: conversation.conversationId,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(boundedDuration)
        )
        activeLiveLocationConversation = conversation
        activeLiveLocationShare = share

        liveLocationShareTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(15))
                } catch {
                    return
                }
                guard let self, self.activeLiveLocationShare == share else { return }
                guard Date() < share.expiresAt else {
                    await self.expireLiveLocationShare(share)
                    return
                }

                do {
                    let sample = try await locationProvider()
                    let update = Self.geoPoint(from: sample)
                    try await liveLocationClient.updateLiveLocation(update, in: conversation)
                } catch {
                    Self.diagnostics.warning(
                        "Live location update failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    func stopLiveLocationShare() async throws {
        liveLocationShareTask?.cancel()
        liveLocationShareTask = nil
        let conversation = activeLiveLocationConversation
        activeLiveLocationConversation = nil
        activeLiveLocationShare = nil

        guard let conversation,
              let liveLocationClient = messaging as? any MessagingLiveLocationSharing else {
            return
        }
        try await liveLocationClient.stopLiveLocationShare(in: conversation)
    }

    private func expireLiveLocationShare(_ share: ActiveLiveLocationShare) async {
        guard activeLiveLocationShare == share else { return }
        let conversation = activeLiveLocationConversation
        liveLocationShareTask = nil
        activeLiveLocationConversation = nil
        activeLiveLocationShare = nil
        guard let conversation,
              let liveLocationClient = messaging as? any MessagingLiveLocationSharing else {
            return
        }
        try? await liveLocationClient.stopLiveLocationShare(in: conversation)
    }

    private static func geoPoint(from location: CSMCommunicationLocation) -> GeoPoint {
        GeoPoint(
            lat: location.latitude,
            lon: location.longitude,
            accuracyM: location.accuracyMeters,
            source: "cop.mobile.live"
        )
    }

    @discardableResult
    func sendMessage(_ draft: OutgoingMessageDraft) async -> Bool {
        guard !draft.isEmpty, let selectedConversation else { return false }
        await ensureMessagingBootstrapFreshIfNeeded(force: shouldForceMessagingRefreshBeforeSend)
        if let blockedMessage = messagingSendBlockedMessage {
            lastError = blockedMessage
            messagingTransportErrorText = blockedMessage
            messageOutboxSyncStatusText = "blocked_e2ee"
            await appendEvent(
                kind: .messageSendFailed,
                relatedId: selectedConversation.conversationId,
                summary: "Odeslani zpravy je blokovane, protoze zabezpeceni E2EE vyzaduje akci uzivatele.",
                metadata: [
                    "reason": matrixEncryptionRecoveryStatus.blocksSending ? "matrix_encryption_recovery_required" : "e2ee_adapter_unavailable",
                    "conversationId": selectedConversation.conversationId
                ]
            )
            return false
        }
        let sendConversation = await refreshedConversationForSend(selectedConversation)
        if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
            lastError = validationError
            messagingTransportErrorText = validationError
            await appendEvent(
                kind: .messageSendFailed,
                relatedId: sendConversation.conversationId,
                summary: "Zprava nebyla zarazena kvuli lokalni policy priloh.",
                metadata: ["error": validationError]
            )
            return false
        }
        let aiInvocation = Self.aiInvocation(for: draft, conversation: sendConversation)
        if let aiInvocation,
           aiInvocation.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastError = "Za příkaz AI doplňte otázku nebo zadání."
            return false
        }
        await appendEvent(
            kind: .messageSendRequested,
            relatedId: sendConversation.conversationId,
            summary: "Zprava pripravena k odeslani.",
            metadata: [
                "conversationId": sendConversation.conversationId,
                "attachments": "\(draft.attachments.count)",
                "reply": draft.replyTo == nil ? "false" : "true"
            ]
        )
        do {
            let message = try await messaging.sendMessage(draft, to: sendConversation)
            ChatPerformance.measure(
                "chat.local-echo",
                budgetMilliseconds: ChatPerformanceBudget.localEchoMilliseconds
            ) {
                timelineStore.send(.upsert(message))
            }
            await refreshPendingMessageCount()
            if message.deliveryState == .pending {
                messagingTransportErrorText = await latestMessagingTransportError(for: sendConversation)
                markMessagingQueued()
                await appendEvent(
                    kind: .messageQueuedOffline,
                    relatedId: message.id,
                    summary: "Zprava ulozena do lokalni odesilaci fronty.",
                    metadata: [
                        "conversationId": sendConversation.conversationId,
                        "attachments": "\(message.attachments.count)",
                        "transportError": messagingTransportErrorText ?? ""
                    ]
                )
            } else {
                messagingTransportErrorText = nil
                await appendEvent(
                    kind: .messageSendConfirmed,
                    relatedId: message.id,
                    summary: "Zprava predana messaging klientovi.",
                    metadata: [
                        "conversationId": sendConversation.conversationId,
                        "attachments": "\(message.attachments.count)"
                    ]
                )
            }
            if let aiInvocation,
               message.deliveryState != .pending,
               draft.attachments.isEmpty,
               !aiInvocation.question.isEmpty {
                await requestAIAgentResponse(
                    question: aiInvocation.question,
                    modelPreference: aiInvocation.modelPreference,
                    conversation: sendConversation
                )
            }
            return true
        } catch {
            lastError = error.localizedDescription
            messagingTransportErrorText = error.localizedDescription
            await refreshPendingMessageCount()
            await appendEvent(
                kind: .messageSendFailed,
                relatedId: sendConversation.conversationId,
                summary: "Odeslani zpravy selhalo.",
                metadata: ["error": error.localizedDescription]
            )
            return false
        }
    }

    func synchronizePendingMessagesForActiveConversation() async {
        guard let selectedConversation else { return }
        await synchronizePendingMessages(for: selectedConversation, trigger: .manual)
    }

    func discardPendingMessagesForActiveConversation() async {
        guard let selectedConversation else { return }
        await discardPendingMessages(for: selectedConversation)
    }

    private func discardPendingMessages(for conversation: Conversation) async {
        let before = await pendingMessageCount(for: conversation)
        guard before > 0 else {
            messageOutboxSyncStatusText = "idle"
            return
        }

        do {
            let removed: Int
            if let messageOutbox {
                removed = try await messageOutbox.discardPendingMessages(for: conversation.conversationId)
            } else {
                let originalCount = messages.count
                timelineStore.send(.removeWhere { message in
                    message.roomId == conversation.conversationId &&
                        message.isOwnMessage &&
                        message.deliveryState == .pending
                })
                removed = originalCount - timelineStore.state.messages.count
            }

            if selectedConversation?.conversationId == conversation.conversationId {
                timelineStore.send(.removeWhere { message in
                    message.roomId == conversation.conversationId &&
                        message.isOwnMessage &&
                        message.deliveryState == .pending
                })
                try? await loadMessages(for: conversation, performAutomaticPendingSync: false)
            }

            await refreshPendingMessageCount()
            let after = await pendingMessageCount(for: conversation)
            messageOutboxSyncStatusText = removed > 0 ? "discarded" : (pendingMessageCount > 0 ? "waiting" : "idle")
            if after == 0 {
                messagingTransportErrorText = nil
                pendingAutoSyncAttemptedConversationIds.remove(conversation.conversationId)
                pendingAutoSyncInFlightConversationIds.remove(conversation.conversationId)
            }
            await appendEvent(
                kind: .messageOutboxDiscarded,
                relatedId: conversation.conversationId,
                summary: "Uzivatel odstranil lokalne cekajici zpravy z aktivni konverzace.",
                metadata: [
                    "before": "\(before)",
                    "after": "\(after)",
                    "removed": "\(removed)",
                    "conversationId": conversation.conversationId
                ]
            )
        } catch {
            messageOutboxSyncStatusText = "failed"
            lastError = error.localizedDescription
            await refreshPendingMessageCount()
            await appendEvent(
                kind: .messageOutboxSyncFailed,
                relatedId: conversation.conversationId,
                summary: "Odstraneni lokalne cekajicich zprav selhalo.",
                metadata: [
                    "error": error.localizedDescription,
                    "conversationId": conversation.conversationId
                ]
            )
        }
    }

    private enum PendingMessageSyncTrigger {
        case automatic
        case manual

        var forceBootstrapRefresh: Bool {
            switch self {
            case .automatic:
                return false
            case .manual:
                return true
            }
        }

        var successSummary: String {
            switch self {
            case .automatic:
                return "Lokalni fronta zprav byla synchronizovana automaticky po obnoveni zabezpeceneho chatu."
            case .manual:
                return "Lokalni fronta zprav byla synchronizovana uzivatelskou akci."
            }
        }

        var blockedSummary: String {
            switch self {
            case .automatic:
                return "Automaticka synchronizace fronty ceka na dostupny produkcni Matrix E2EE adapter."
            case .manual:
                return "Synchronizace fronty je blokovana do integrace produkcniho Matrix E2EE adapteru."
            }
        }
    }

    private func synchronizePendingMessages(
        for conversation: Conversation,
        trigger: PendingMessageSyncTrigger
    ) async {
        await ensureMessagingBootstrapFreshIfNeeded(force: trigger.forceBootstrapRefresh)
        await refreshMatrixEncryptionRecoveryStatus()
        let syncConversation = await refreshedConversationForSend(conversation)

        if (syncConversation.e2eeRequired || syncConversation.encrypted),
           matrixEncryptionRecoveryStatus.blocksSending {
            let reason = matrixEncryptionRecoveryStatus.userMessage
            messageOutboxSyncStatusText = "blocked_e2ee"
            lastError = reason
            await appendEvent(
                kind: .messageOutboxSyncFailed,
                relatedId: syncConversation.conversationId,
                summary: CSMLocalization.text("event.message_outbox_waiting_e2ee", fallback: "Synchronizace fronty čeká na E2EE obnovu zařízení."),
                metadata: [
                    "reason": "matrix_encryption_recovery_required",
                    "conversationId": syncConversation.conversationId,
                    "trigger": "\(trigger)"
                ]
            )
            return
        }
        let trust = messagingTrustPresentation
        guard trust.allowsManualSync else {
            let reason = trust.userMessage ?? "E2EE adapter neni dostupny."
            messageOutboxSyncStatusText = "blocked_e2ee"
            lastError = reason
            await appendEvent(
                kind: .messageOutboxSyncFailed,
                relatedId: syncConversation.conversationId,
                summary: trigger.blockedSummary,
                metadata: [
                    "reason": "e2ee_adapter_unavailable",
                    "conversationId": syncConversation.conversationId,
                    "trigger": "\(trigger)"
                ]
            )
            return
        }
        let before = await pendingMessageCount(for: conversation)
        guard before > 0 else {
            messageOutboxSyncStatusText = "idle"
            return
        }

        messageOutboxSyncStatusText = "syncing"

        do {
            let aiQuestionsBeforeSync: [ChatMessage]
            if let messageOutbox {
                aiQuestionsBeforeSync = (try? await messageOutbox.pendingMessages(
                    for: syncConversation.conversationId
                )) ?? []
            } else {
                aiQuestionsBeforeSync = []
            }
            let result = try await messaging.synchronizePendingMessages(for: syncConversation)
            await refreshPendingMessageCount()
            let after = await pendingMessageCount(for: conversation)

            if result.delivered > 0 {
                if selectedConversation?.conversationId == syncConversation.conversationId {
                    try? await loadMessages(for: syncConversation, performAutomaticPendingSync: false)
                }
                if !aiQuestionsBeforeSync.isEmpty, let messageOutbox {
                    let pendingIds = Set(
                        ((try? await messageOutbox.pendingMessages(
                            for: syncConversation.conversationId
                        )) ?? []).map(\.id)
                    )
                    for question in aiQuestionsBeforeSync where
                        !pendingIds.contains(question.id) &&
                        question.attachments.isEmpty &&
                        !question.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let draft = OutgoingMessageDraft(body: question.body)
                        if let invocation = Self.aiInvocation(for: draft, conversation: syncConversation),
                           !invocation.question.isEmpty {
                            await requestAIAgentResponse(
                                question: invocation.question,
                                modelPreference: invocation.modelPreference,
                                conversation: syncConversation
                            )
                        }
                    }
                }
                messageOutboxSyncStatusText = pendingMessageCount == 0 ? "synced" : "partial"
                await appendEvent(
                    kind: .messageOutboxSynced,
                    relatedId: syncConversation.conversationId,
                    summary: trigger.successSummary,
                    metadata: [
                        "before": "\(before)",
                        "after": "\(after)",
                        "attempted": "\(result.attempted)",
                        "delivered": "\(result.delivered)",
                        "failed": "\(result.failed)",
                        "trigger": "\(trigger)"
                    ]
                )
            } else if result.failed > 0 {
                messageOutboxSyncStatusText = "failed"
                await appendEvent(
                    kind: .messageOutboxSyncFailed,
                    relatedId: syncConversation.conversationId,
                    summary: "Synchronizace lokalni fronty zprav selhala.",
                    metadata: [
                        "before": "\(before)",
                        "after": "\(after)",
                        "attempted": "\(result.attempted)",
                        "delivered": "\(result.delivered)",
                        "failed": "\(result.failed)",
                        "trigger": "\(trigger)"
                    ]
                )
            } else {
                messageOutboxSyncStatusText = pendingMessageCount > 0 ? "waiting" : "idle"
            }
        } catch {
            messageOutboxSyncStatusText = "failed"
            lastError = error.localizedDescription
            await refreshPendingMessageCount()
            await appendEvent(
                kind: .messageOutboxSyncFailed,
                relatedId: syncConversation.conversationId,
                summary: "Synchronizace lokalni fronty zprav vyvolala chybu.",
                metadata: [
                    "error": error.localizedDescription,
                    "trigger": "\(trigger)"
                ]
            )
        }
    }

    func toggleReaction(_ emoji: String, on message: ChatMessage) async {
        guard let selectedConversation else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

        do {
            let updated = try await messaging.toggleReaction(emoji, on: messages[index], in: selectedConversation)
            timelineStore.send(.upsert(updated))
            try await messageHistory?.saveMessages(messages, conversationId: selectedConversation.conversationId)
            await appendEvent(
                kind: .messageReactionUpdated,
                relatedId: message.id,
                summary: "Reakce na zpravu synchronizovana pres messaging klienta.",
                metadata: [
                    "conversationId": selectedConversation.conversationId,
                    "emoji": emoji,
                    "sync": "messaging"
                ]
            )
        } catch {
            let updated = messages[index].applyingReactionToggle(emoji)
            timelineStore.send(.upsert(updated))
            do {
                try await messageHistory?.saveMessages(messages, conversationId: selectedConversation.conversationId)
                await appendEvent(
                    kind: .messageReactionUpdated,
                    relatedId: message.id,
                    summary: "Reakce na zpravu ulozena lokalne pro offline historii.",
                    metadata: [
                        "conversationId": selectedConversation.conversationId,
                        "emoji": emoji,
                        "sync": "local",
                        "error": error.localizedDescription
                    ]
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func togglePinnedMessage(_ message: ChatMessage) async {
        guard let selectedConversation else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

        do {
            let updated = try await messaging.setMessagePinned(!messages[index].isPinned, message: messages[index], in: selectedConversation)
            timelineStore.send(.upsert(updated))
            try await messageHistory?.saveMessages(messages, conversationId: selectedConversation.conversationId)
            await appendEvent(
                kind: .messagePinned,
                relatedId: message.id,
                summary: updated.isPinned ? "Zprava pripnuta v Matrix mistnosti." : "Zprava odepnuta v Matrix mistnosti.",
                metadata: [
                    "conversationId": selectedConversation.conversationId,
                    "pinned": updated.isPinned ? "true" : "false"
                ]
            )
        } catch {
            lastError = error.localizedDescription
            messagingTransportErrorText = error.localizedDescription
        }
    }

    func deleteMessageLocally(_ message: ChatMessage) async {
        guard let selectedConversation else { return }

        chatPreferences = chatPreferences.settingMessageHidden(
            conversationId: selectedConversation.conversationId,
            messageId: message.id,
            enabled: true
        )
        persistChatConversationPreferences()

        if message.deliveryState == .pending {
            try? await messageOutbox?.removeMessage(id: message.id, conversationId: selectedConversation.conversationId)
        }
        timelineStore.send(.remove(messageID: message.id))
        try? await messageHistory?.saveMessages(messages, conversationId: selectedConversation.conversationId)
        await refreshPendingMessageCount()
        await appendEvent(
            kind: .messageDeleted,
            relatedId: message.id,
            summary: "Zprava skryta pouze na tomto zarizeni.",
            metadata: [
                "conversationId": selectedConversation.conversationId,
                "scope": "local"
            ]
        )
    }

    func redactMessageForEveryone(_ message: ChatMessage) async {
        guard let selectedConversation else { return }
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }

        do {
            let updated = try await messaging.redactMessage(messages[index], in: selectedConversation)
            timelineStore.send(.upsert(updated))
            try await messageHistory?.saveMessages(messages, conversationId: selectedConversation.conversationId)
            await refreshPendingMessageCount()
            await appendEvent(
                kind: .messageDeleted,
                relatedId: message.id,
                summary: "Zprava smazana v Matrix mistnosti.",
                metadata: [
                    "conversationId": selectedConversation.conversationId,
                    "scope": "room"
                ]
            )
        } catch {
            lastError = error.localizedDescription
            messagingTransportErrorText = error.localizedDescription
        }
    }

    func forwardMessage(_ message: ChatMessage, to targetConversations: [Conversation]) async {
        guard !targetConversations.isEmpty else { return }
        guard let draft = ChatMessagePresentationFactory.forwardingDraft(from: message) else {
            lastError = "Tuto zpravu ted nejde bezpecne preposlat."
            return
        }

        var delivered = 0
        var failed = 0
        for target in targetConversations {
            do {
                let sendConversation = await refreshedConversationForSend(target)
                let sentMessage = try await messaging.sendMessage(draft, to: sendConversation)
                delivered += 1
                if selectedConversation?.conversationId == sendConversation.conversationId {
                    timelineStore.send(.upsert(sentMessage))
                    try? await messageHistory?.saveMessages(messages, conversationId: sendConversation.conversationId)
                }
            } catch {
                failed += 1
                lastError = error.localizedDescription
            }
        }

        await refreshPendingMessageCount()
        await appendEvent(
            kind: .messageForwarded,
            relatedId: message.id,
            summary: "Zprava preposlana do vybranych konverzaci.",
            metadata: [
                "targetCount": "\(targetConversations.count)",
                "delivered": "\(delivered)",
                "failed": "\(failed)"
            ]
        )
    }

    func forwardMessages(_ sourceMessages: [ChatMessage], to targetConversations: [Conversation]) async {
        guard !sourceMessages.isEmpty, !targetConversations.isEmpty else { return }
        for message in sourceMessages where !message.isDeleted {
            await forwardMessage(message, to: targetConversations)
        }
    }

    func deleteMessagesLocally(_ sourceMessages: [ChatMessage]) async {
        guard !sourceMessages.isEmpty else { return }
        for message in sourceMessages {
            await deleteMessageLocally(message)
        }
    }

    func redactMessagesForEveryone(_ sourceMessages: [ChatMessage]) async {
        guard !sourceMessages.isEmpty else { return }
        for message in sourceMessages where message.isOwnMessage && !message.isDeleted && message.deliveryState != .pending {
            await redactMessageForEveryone(message)
        }
    }

    func summarizeActiveConversation() async -> LocalAIConversationSummary? {
        guard !managedAppPolicy.localAIDisabled else {
            localAIAvailability = .disabledByPolicy
            lastError = "Lokalni AI je vypnuta organizacni policy."
            return nil
        }

        do {
            let summary = try await localAI.summarize(messages: messages)
            localAIAvailability = await localAI.availability
            await appendEvent(
                kind: .localAISummaryCreated,
                relatedId: selectedConversation?.conversationId,
                summary: "Lokalni AI pripravila souhrn konverzace.",
                metadata: ["messageCount": "\(messages.count)"]
            )
            return summary
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func translateMessage(_ message: ChatMessage) async -> LocalAIMessageTranslation? {
        guard !managedAppPolicy.localAIDisabled else {
            localAIAvailability = .disabledByPolicy
            lastError = CSMLocalization.text("localai.disabled", fallback: "Lokální AI je vypnutá organizační policy.")
            return nil
        }
        let body = message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            lastError = CSMLocalization.text("localai.translation.empty", fallback: "Zpráva neobsahuje text k překladu.")
            return nil
        }

        do {
            let translation = try await localAI.translateMessage(
                body,
                preferredLanguageCode: Self.preferredTranslationLanguageCode
            )
            localAIAvailability = await localAI.availability
            await appendEvent(
                kind: .localAISuggestionCreated,
                relatedId: message.id,
                summary: "Lokalni AI pripravila preklad zpravy.",
                metadata: [
                    "source": translation.sourceLanguageCode,
                    "target": translation.targetLanguageCode,
                    "confidence": String(format: "%.2f", translation.confidence)
                ]
            )
            return translation
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private static var preferredTranslationLanguageCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "cs"
        return preferred.hasPrefix("cs") || preferred.hasPrefix("sk") ? "cs" : "en"
    }

    private func clearCachedMessagingBootstrap(for actor: AuthenticatedActor) async {
        let deviceId = Self.matrixDeviceId(
            actor: actor,
            deviceRegistration: deviceRegistration,
            posture: devicePosture
        )
        try? await messagingBootstrapStore?.clear(subjectId: actor.subjectId, deviceId: deviceId)
    }

    private func loadMessages(
        for conversation: Conversation,
        performAutomaticPendingSync: Bool = true
    ) async throws {
        let conversationId = conversation.conversationId
        if selectedConversation?.conversationId == conversationId {
            loadingConversationId = conversationId
        }
        do {
            if let cachedLoader = messaging as? any MessagingCachedSnapshotLoading,
               let cachedPage = try? await cachedLoader.cachedMessagePage(
                   for: conversation,
                   limit: TimelineWindowPolicy.mobile.initialMessageLimit
               ),
               !cachedPage.messages.isEmpty,
               selectedConversation?.conversationId == conversationId {
                let cachedMessages = visibleMessages(cachedPage.messages, for: conversation)
                ChatPerformance.measure(
                    "cached-conversation-open",
                    budgetMilliseconds: ChatPerformanceBudget.cachedConversationOpenMilliseconds
                ) {
                    timelineStore.send(
                        .replaceRemote(
                            cachedMessages,
                            hasEarlier: cachedPage.hasEarlier
                        )
                    )
                }
                loadingConversationId = nil
            }

            let loadedMessages = visibleMessages(try await messaging.messages(for: conversation), for: conversation)
            guard selectedConversation?.conversationId == conversationId else { return }
            let hasEarlier = if let paging = messaging as? any MessagingHistoryPaging {
                await paging.hasEarlierMessages(for: conversation)
            } else {
                loadedMessages.count > TimelineWindowPolicy.mobile.retainedMessageLimit
            }
            timelineStore.send(
                .replaceRemote(
                    loadedMessages,
                    hasEarlier: hasEarlier
                )
            )
            loadingConversationId = nil
            await refreshPendingMessageCount()
            if performAutomaticPendingSync {
                await automaticallySynchronizePendingMessagesIfPossible(for: conversation)
            }
        } catch {
            if selectedConversation?.conversationId == conversationId {
                loadingConversationId = nil
            }
            throw error
        }
    }

    private func startLiveMessageStream(for conversation: Conversation) {
        let conversationId = conversation.conversationId
        timelineSynchronization.start(
            conversation: conversation,
            messaging: messaging,
            prepareFallbackRefresh: { [weak self] in
                guard let self,
                      self.selectedConversation?.conversationId == conversationId else {
                    return
                }
                await self.ensureMessagingBootstrapFreshIfNeeded(
                    force: self.shouldForceMessagingRefreshBeforeSend
                )
            },
            consume: { [weak self] snapshot in
                guard let self,
                      self.selectedConversation?.conversationId == conversationId else {
                    return
                }
                let visibleSnapshot = self.visibleMessages(snapshot, for: conversation)
                self.timelineStore.send(
                    .replaceRemote(
                        visibleSnapshot,
                        hasEarlier: self.timelineStore.state.hasEarlierMessages
                    )
                )
                await self.refreshPendingMessageCount()
            },
            reportError: { [weak self] error in
                guard let self,
                      self.selectedConversation?.conversationId == conversationId else {
                    return
                }
                self.messagingTransportErrorText = error.localizedDescription
            }
        )
    }

    private func visibleMessages(_ values: [ChatMessage], for conversation: Conversation) -> [ChatMessage] {
        let visible = values.filter {
            !chatPreferences.isMessageHidden(
                conversationId: conversation.conversationId,
                messageId: $0.id
            )
        }
        return ChatMessage.removingSupersededLocalEchoes(from: visible)
    }

    private func automaticallySynchronizePendingMessagesIfPossible(
        for conversation: Conversation,
        force: Bool = false
    ) async {
        guard await pendingMessageCount(for: conversation) > 0 else { return }
        guard selectedConversation?.conversationId == conversation.conversationId else { return }
        guard messagingTrustPresentation.allowsManualSync else { return }
        guard force || !pendingAutoSyncAttemptedConversationIds.contains(conversation.conversationId) else { return }
        guard !pendingAutoSyncInFlightConversationIds.contains(conversation.conversationId) else { return }

        if !force {
            pendingAutoSyncAttemptedConversationIds.insert(conversation.conversationId)
        }
        pendingAutoSyncInFlightConversationIds.insert(conversation.conversationId)
        defer {
            pendingAutoSyncInFlightConversationIds.remove(conversation.conversationId)
        }

        await synchronizePendingMessages(for: conversation, trigger: .automatic)
    }

    private func pendingMessageCount(for conversation: Conversation) async -> Int {
        guard let messageOutbox else {
            return messages.filter {
                $0.roomId == conversation.conversationId && $0.isOwnMessage && $0.deliveryState == .pending
            }.count
        }
        do {
            return try await messageOutbox.pendingRecords(for: conversation.conversationId).count
        } catch {
            lastError = error.localizedDescription
            return 0
        }
    }

    private func refreshPendingMessageCount() async {
        guard let messageOutbox else {
            pendingMessageCount = messages.filter { $0.isOwnMessage && $0.deliveryState == .pending }.count
            return
        }
        do {
            pendingMessageCount = try await messageOutbox.pendingMessageCount()
            if let selectedConversation {
                messagingTransportErrorText = await latestMessagingTransportError(for: selectedConversation)
            }
            if pendingMessageCount == 0, messagingStatusText == "offline_queue" {
                messagingStatusText = "online"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func markMessagingQueued() {
        if messagingStatusText == "online" || messagingStatusText == "ready" {
            messagingStatusText = "offline_queue"
        }
    }

    private var shouldForceMessagingRefreshBeforeSend: Bool {
        messagingStatusText == "e2ee_queue" ||
            messagingStatusText == "degraded" ||
            messagingStatusText == "offline_queue"
    }

    private func latestMessagingTransportError(for conversation: Conversation?) async -> String? {
        guard let diagnostics = messaging as? any MessagingClientDiagnostics else { return nil }
        return await diagnostics.latestTransportError(for: conversation)
    }

    /// Records only an event category in the unified log.
    ///
    /// The former application model persisted a cross-feature crisis event log.
    /// The communication runtime intentionally does not own map/report state and
    /// never logs message bodies, identities, room identifiers, or metadata.
    private func appendEvent(
        kind: CrisisEventKind,
        relatedId: String? = nil,
        summary: String,
        subjectIdOverride: String? = nil,
        relayEnvelopeId: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        _ = (relatedId, summary, subjectIdOverride, relayEnvelopeId, metadata)
        Self.diagnostics.debug("event=\(kind.rawValue, privacy: .public)")
    }

    private static func recordDeviceRegistrationDiagnostic(_ status: String) {
        UserDefaults.standard.set(status, forKey: deviceRegistrationDiagnosticStatusKey)
        UserDefaults.standard.set(
            ISO8601DateFormatter().string(from: .now),
            forKey: deviceRegistrationDiagnosticUpdatedAtKey
        )
    }

}
