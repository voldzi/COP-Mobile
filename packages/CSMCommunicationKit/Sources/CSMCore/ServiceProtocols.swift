import Foundation

protocol CopAPIClientProtocol: Sendable {
    func bootstrap(seconds: Int) async throws -> MobileBootstrap
    func offlineSnapshot(seconds: Int) async throws -> MobileOfflineSnapshot
    func mapCatalog(locale: String, includeDiagnostics: Bool, includePartner: Bool) async throws -> MapLayerCatalog
    func mapFeatures(_ request: MapFeatureQueryRequest) async throws -> MapFeatureQueryResponse
    func transitVehicleDetail(featureId: String, sourceId: String?) async throws -> TransitVehicleDetail
    func mapRasterOverlayImage(url: String) async throws -> Data
    func weatherWebcamResource(url: String) async throws -> Data
    func weatherRadarFrames(product: String, hours: Int, limit: Int) async throws -> WeatherRadarFrameCatalog
    func sketchPalettes() async throws -> SketchPaletteCatalog
    func sketchDrawings(bbox: MapFeatureBoundingBox?, limit: Int) async throws -> SketchDrawingCollection
    func sketchDrawing(drawingId: String) async throws -> SketchDrawing
    func createSketchDrawing(_ request: SketchDrawingCreateRequest) async throws -> SketchDrawing
    func updateSketchDrawing(drawingId: String, request: SketchDrawingUpdateRequest) async throws -> SketchDrawing
    func deleteSketchDrawing(drawingId: String) async throws
    func userPreferenceProfile() async throws -> UserPreferenceProfile
    func updateUserPreferences(_ update: UserPreferenceUpdate) async throws -> UserPreferenceProfile
    func alerts(includeAcknowledged: Bool) async throws -> [CopAlert]
    func acknowledgeAlert(alertId: String, note: String?) async throws -> CopAlert
    func messagingStatus() async throws -> MessagingStatus
    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap
    func startVoiceCall(_ request: CSMVoiceCallStartRequest) async throws -> CSMVoiceCallSession
    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int) async throws -> [CSMVoiceCall]
    func voiceCall(callId: String) async throws -> CSMVoiceCallSession
    func transitionVoiceCall(
        callId: String,
        request: CSMVoiceCallActionRequest
    ) async throws -> CSMVoiceCallSession
    func mobilePairingSession(code: String) async throws -> MobilePairingSessionResponse
    func claimMobilePairingSession(code: String, request: MobilePairingClaimRequest) async throws -> MobilePairingSessionResponse
    func conversations() async throws -> [Conversation]
    func queryAIChatAgent(_ request: CopAIChatAgentRequest) async throws -> CopAIChatAgentResponse
    func registerDevice(_ registration: MobileDeviceRegistration) async throws -> MobileDeviceRegistrationResponse
    func deviceRegistrationTicket(
        appInstanceId: String,
        bundleId: String
    ) async throws -> MobileDeviceRegistrationTicketResponse
    func submitCommunityReport(_ draft: CommunityReportDraft) async throws -> CommunityReportSubmission
    func communityReports() async throws -> [CommunityReport]
}

extension CopAPIClientProtocol {
    func queryAIChatAgent(_ request: CopAIChatAgentRequest) async throws -> CopAIChatAgentResponse {
        throw CSMServiceError.unavailable("COP AI agent neni v tomto prostredi dostupny.")
    }

    func deviceRegistrationTicket(
        appInstanceId: String,
        bundleId: String
    ) async throws -> MobileDeviceRegistrationTicketResponse {
        throw CSMServiceError.unavailable("Registrace oznámení není v tomto prostředí dostupná.")
    }
}

protocol MessagingClientProtocol: Sendable {
    func configure(with bootstrap: MessagingBootstrap) async throws
    func messages(for conversation: Conversation) async throws -> [ChatMessage]
    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage
    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage
    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage
    func redactMessage(_ message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage
    func setMessagePinned(_ pinned: Bool, message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage
    func leaveConversation(_ conversation: Conversation) async throws
    func synchronizePendingMessages(for conversation: Conversation) async throws -> MessageOutboxSyncResult
    func registerPusher(pushKey: String, pushGatewayURL: URL) async
}

protocol MessagingClientDiagnostics: Sendable {
    func latestTransportError(for conversation: Conversation?) async -> String?
}

protocol MessagingLiveMessageStreaming: Sendable {
    func messageSnapshots(for conversation: Conversation) async throws -> AsyncStream<[ChatMessage]>
}

protocol MessagingLiveLocationSharing: Sendable {
    func startLiveLocationShare(
        durationSeconds: TimeInterval,
        in conversation: Conversation
    ) async throws
    func updateLiveLocation(
        _ location: GeoPoint,
        in conversation: Conversation
    ) async throws
    func stopLiveLocationShare(in conversation: Conversation) async throws
}

protocol MessagingHistoryPaging: Sendable {
    func hasEarlierMessages(for conversation: Conversation) async -> Bool
    func loadEarlierMessages(
        for conversation: Conversation,
        limit: Int
    ) async throws -> MessageHistoryPage
}

/// Fast path used by native screens before any Matrix/network refresh.
///
/// The returned snapshot is bounded and may contain persisted outbox echoes.
/// It never waits for the live transport.
protocol MessagingCachedSnapshotLoading: Sendable {
    func cachedMessagePage(
        for conversation: Conversation,
        limit: Int
    ) async throws -> MessageHistoryPage
}

protocol MessagingConversationPresentationEnriching: Sendable {
    func enrichedConversationPresentation(_ conversation: Conversation) async -> Conversation
}

protocol MessagingConversationAvatarUpdating: Sendable {
    func updateGroupConversationAvatar(
        _ avatarDataUrl: String?,
        for conversation: Conversation
    ) async throws -> Conversation
}

protocol MessagingBootstrapStoring: Sendable {
    func load(subjectId: String, deviceId: String) async throws -> MessagingBootstrap?
    func save(_ bootstrap: MessagingBootstrap, subjectId: String, deviceId: String) async throws
    func clear(subjectId: String, deviceId: String?) async throws
}

protocol MessageOutboxStoring: Sendable {
    func enqueue(_ message: ChatMessage, conversation: Conversation) async throws
    func pendingMessages(for conversationId: String) async throws -> [ChatMessage]
    func pendingRecords(for conversationId: String) async throws -> [PendingMessageRecord]
    func pendingMessageCount() async throws -> Int
    func recordAttempt(messageId: String, conversationId: String, error: String, retryAfter: TimeInterval) async throws
    func removeMessage(id: String, conversationId: String) async throws
    @discardableResult
    func discardPendingMessages(for conversationId: String) async throws -> Int
    func clear() async throws
}

protocol MessageHistoryStoring: Sendable {
    func messages(for conversationId: String) async throws -> [ChatMessage]
    func messagePage(
        for conversationId: String,
        before: Date?,
        limit: Int
    ) async throws -> MessageHistoryPage
    func saveMessages(_ messages: [ChatMessage], conversationId: String) async throws
    func appendMessage(_ message: ChatMessage, conversationId: String) async throws
    func removeMessages(for conversationId: String) async throws
    func clear() async throws
}

struct MessageHistoryPage: Equatable, Sendable {
    var messages: [ChatMessage]
    var hasEarlier: Bool
}

extension MessageHistoryStoring {
    func messagePage(
        for conversationId: String,
        before: Date?,
        limit: Int
    ) async throws -> MessageHistoryPage {
        let all = try await messages(for: conversationId)
            .filter { before == nil || $0.sentAt < before! }
            .sorted { $0.sentAt < $1.sentAt }
        let boundedLimit = max(1, limit)
        let page = Array(all.suffix(boundedLimit))
        return MessageHistoryPage(messages: page, hasEarlier: all.count > page.count)
    }
}

extension MessagingClientProtocol {
    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        var message = try await sendMessage(draft.body, to: conversation)
        if !draft.attachments.isEmpty {
            message.attachments = draft.attachments
        }
        if let replyTo = draft.replyTo {
            message.replyTo = replyTo
        }
        return message
    }

    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        message.applyingReactionToggle(emoji)
    }

    func redactMessage(_ message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        message.markedDeleted()
    }

    func setMessagePinned(_ pinned: Bool, message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        message.settingPinned(pinned)
    }

    func leaveConversation(_ conversation: Conversation) async throws {
        throw CSMServiceError.unavailable("Opuštění skupiny vyžaduje dostupný Matrix kanál.")
    }

    func synchronizePendingMessages(for conversation: Conversation) async throws -> MessageOutboxSyncResult {
        MessageOutboxSyncResult.empty
    }

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {}
}

extension MessagingClientDiagnostics {
    func latestTransportError(for conversation: Conversation?) async -> String? { nil }
}

struct MessageOutboxSyncResult: Codable, Equatable, Sendable {
    var attempted: Int
    var delivered: Int
    var failed: Int

    static let empty = MessageOutboxSyncResult(attempted: 0, delivered: 0, failed: 0)
}

protocol SecureSnapshotStoring: Sendable {
    func loadSnapshot(for subjectId: String) async throws -> MobileOfflineSnapshot?
    func saveSnapshot(_ snapshot: MobileOfflineSnapshot, subjectId: String) async throws
    func clear(for subjectId: String) async throws
}

protocol OfflineMapPackStoring: Sendable {
    func loadPacks(for subjectId: String) async throws -> [OfflineMapPack]
    func savePacks(_ packs: [OfflineMapPack], subjectId: String) async throws
    func clear(for subjectId: String) async throws
}

protocol OfflineMapTileProviding: Sendable {
    func loadTile(coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws -> Data?
}

protocol OfflineMapTileStoring: OfflineMapTileProviding {
    func saveTile(_ data: Data, coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws
    func saveSummary(_ summary: OfflineMapTileCacheSummary, subjectId: String) async throws
    func loadSummary(packId: String, subjectId: String) async throws -> OfflineMapTileCacheSummary?
    func clear(for subjectId: String) async throws
}

protocol OfflineMapTileFetching: Sendable {
    func data(for url: URL) async throws -> Data
}

protocol CommunityOutboxStoring: Sendable {
    func enqueue(_ draft: CommunityReportDraft) async throws
    func pendingDrafts() async throws -> [CommunityReportDraft]
    func removeDraft(id: String) async throws
    func clear() async throws
}

protocol CrisisEventLogging: Sendable {
    func append(_ entry: CrisisEventLogEntry) async throws
    func entries(for subjectId: String, limit: Int) async throws -> [CrisisEventLogEntry]
    func clear(for subjectId: String) async throws
}

extension CrisisEventLogging {
    func securityDiagnosticExport(
        for subjectId: String,
        context: SecurityDiagnosticExportContext,
        limit: Int = 200
    ) async throws -> SecurityDiagnosticExport {
        let entries = try await entries(for: subjectId, limit: Int.max)
        return SecurityDiagnosticExporter.makeExport(
            entries: entries,
            subjectId: subjectId,
            context: context,
            limit: limit
        )
    }
}

protocol DeviceRegistrationProviding: Sendable {
    @MainActor
    func registration(push: MobilePushRegistration?, posture: MobileDevicePosture?) -> MobileDeviceRegistration
}

protocol CSMMessagingDeviceRegistering: Sendable {
    func registerDevice(
        _ request: CSMMessagingDeviceRegistrationRequest,
        authorizationTicket: String?
    ) async throws -> CSMMessagingDeviceRegistrationResponse
    func updatePreferences(deviceId: String, preferences: CSMNotificationPreferences, subscriptions: CSMNotificationSubscriptions) async throws -> CSMMessagingDeviceRegistrationResponse
    func deleteDevice(deviceId: String) async throws
}

extension CSMMessagingDeviceRegistering {
    func registerDevice(
        _ request: CSMMessagingDeviceRegistrationRequest
    ) async throws -> CSMMessagingDeviceRegistrationResponse {
        try await registerDevice(request, authorizationTicket: nil)
    }
}

protocol ConversationMetadataProviding: Sendable {
    func conversations() async throws -> [Conversation]
    func conversation(id: String) async throws -> Conversation
    func searchUserDirectory(query: String, limit: Int) async throws -> [ConversationRecipient]
    func createConversation(_ draft: ConversationDraft) async throws -> Conversation
    func addConversationMembers(conversationId: String, members: [ConversationMemberDraft]) async throws -> Conversation
    func ensureMatrixRoom(conversationId: String) async throws -> Conversation
}

extension ConversationMetadataProviding {
    func searchUserDirectory(query: String, limit: Int) async throws -> [ConversationRecipient] {
        []
    }
}

struct StaticDeviceRegistrationProvider: DeviceRegistrationProviding {
    var value: MobileDeviceRegistration

    @MainActor
    func registration(push: MobilePushRegistration?, posture: MobileDevicePosture?) -> MobileDeviceRegistration {
        var registration = value
        registration.push = push
        registration.posture = posture
        return registration
    }
}

@MainActor
protocol AuthSessionManaging {
    func canUseExistingSession() async -> Bool
    func signIn() async throws
    func signIn(forceAuthentication: Bool) async throws
    func signOut() async throws
}

extension AuthSessionManaging {
    func signIn(forceAuthentication: Bool) async throws {
        try await signIn()
    }
}

@MainActor
protocol SecurityUnlockManaging {
    func requireUnlock(reason: String) async throws
}

enum CSMServiceError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case disabled(String)
    case invalidState(String)
    case authenticationRequired(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message),
             let .disabled(message),
             let .invalidState(message),
             let .authenticationRequired(message):
            message
        }
    }
}
