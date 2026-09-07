import Foundation

#if canImport(MatrixRustSDK) && !os(watchOS)
import CryptoKit
@preconcurrency import MatrixRustSDK
import OSLog
import Security

#if os(iOS)
import UIKit
#endif

/// Production Matrix adapter backed by the official Matrix Rust SDK Swift bindings.
///
/// The adapter restores the Matrix session provisioned by CSM Messaging and lets
/// the SDK handle Megolm encryption, room key sharing, media encryption and
/// local crypto state. It deliberately checks encrypted-room state before
/// sending whenever COP/CSM policy marks the conversation as E2EE-required.
actor MatrixRustE2EEMessagingClient: MessagingClientProtocol, MessagingLiveMessageStreaming, MessagingLiveLocationSharing, MessagingHistoryPaging, MessagingConversationPresentationEnriching, MessagingConversationAvatarUpdating, MatrixEncryptionRecoveryManaging {
    private static let userAgent = "COP Mobile iOS/0.1.2 MatrixRustSDK/26.06.23"
    private static let preflightUserAgent = "COP Mobile iOS/0.1.2 Matrix preflight"
    private static let historyPageSize: UInt16 = 100
    private static let liveLocationCompatibilityBody = "\u{2063}cop-live-location-compatibility"
    static let csmStickerFallbackFilenamePrefix = "csm-sticker-"

    private struct LiveLocationCompatibilitySession: Sendable {
        let shareId: String
        let startedAt: Date
        let expiresAt: Date
        let durationSeconds: Int
        var latestLocation: GeoPoint?
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm.messenger",
        category: "matrix-rust"
    )
    private let keychain: KeychainCredentialStore
    private let fileManager: FileManager
    private let fixedStorePassphrase: String?
    private var client: Client?
    private var sessionContext: MatrixRustSessionContext?
    private var lastBootstrap: MessagingBootstrap?
    private var syncHandle: TaskHandle?
    private var syncListener: MatrixRustSyncListener?
    private var timelineSubscriptions: [String: MatrixRustTimelineSubscription] = [:]
    private var timelineHasEarlierMessages: [String: Bool] = [:]
    private var avatarDataURLCache: [String: String] = [:]
    private var unavailableAvatarURLs: Set<String> = []
    private var liveLocationCompatibilitySessions: [String: LiveLocationCompatibilitySession] = [:]

    init(
        keychain: KeychainCredentialStore,
        fileManager: FileManager = .default,
        fixedStorePassphrase: String? = nil
    ) {
        self.keychain = keychain
        self.fileManager = fileManager
        self.fixedStorePassphrase = fixedStorePassphrase
    }

    deinit {
        syncHandle?.cancel()
        timelineSubscriptions.values.forEach { $0.handle.cancel() }
    }

    // MARK: - MessagingClientProtocol

    func configure(with bootstrap: MessagingBootstrap) async throws {
        try await configure(with: bootstrap, resetLocalStore: false)
    }

    private func configure(with bootstrap: MessagingBootstrap, resetLocalStore: Bool) async throws {
        lastBootstrap = bootstrap
        let context = try Self.makeSessionContext(from: bootstrap)
        if !resetLocalStore, sessionContext?.isEquivalent(to: context) == true, let client {
            try await refreshExistingSession(client, reason: "equivalent-bootstrap")
            return
        }

        cancelTimelineSubscriptions()
        await stopSyncService()
        avatarDataURLCache.removeAll(keepingCapacity: true)
        unavailableAvatarURLs.removeAll(keepingCapacity: true)
        liveLocationCompatibilitySessions.removeAll(keepingCapacity: true)

        let passphrase = try await matrixStorePassphrase(for: context.storeSubject)
        if resetLocalStore {
            try Self.removeMatrixLocalStore(subject: context.storeSubject, fileManager: fileManager)
        }
        let storePaths = try Self.matrixStorePaths(
            subject: context.storeSubject,
            fileManager: fileManager
        )
        try await Self.verifyHomeserverReachable(context.homeserverURL)

        let matrixClient = try await ClientBuilder()
            .homeserverUrl(url: context.homeserverURL.absoluteString)
            .requestConfig(
                config: RequestConfig(
                    retryLimit: 1,
                    timeout: 15_000,
                    maxConcurrentRequests: nil,
                    maxRetryTime: 2_000
                )
            )
            .sqliteStore(
                config: SqliteStoreBuilder(dataPath: storePaths.dataPath, cachePath: storePaths.cachePath)
                    .passphrase(passphrase: passphrase)
            )
            // Cross-signing and backup activation are SDK-owned session duties.
            // The recovery key remains user-held, but an already recovered
            // account must sign this device before other clients share keys.
            .autoEnableBackups(autoEnableBackups: true)
            .autoEnableCrossSigning(autoEnableCrossSigning: true)
            .backupDownloadStrategy(backupDownloadStrategy: .oneShot)
            .slidingSyncVersionBuilder(versionBuilder: .none)
            .userAgent(userAgent: Self.userAgent)
            .build()

        let sdkSession = MatrixRustSDK.Session(
            accessToken: context.accessToken,
            refreshToken: context.refreshToken,
            userId: context.userId,
            deviceId: context.deviceId,
            homeserverUrl: context.homeserverURL.absoluteString,
            oauthData: nil,
            slidingSyncVersion: .none
        )
        try await matrixClient.restoreSessionWith(session: sdkSession, roomLoadSettings: .all)
        try await matrixClient.resume()
        await matrixClient.enableAllSendQueues(enable: true)
        // Do not await `waitForE2eeInitializationTasks()` here. In the current
        // pilot Synapse deployment, Matrix Rust probes secret storage
        // (`m.secret_storage.default_key`) while enabling recovery.
        // Awaiting that recovery-oriented task can wedge the first sync before
        // any fresh encrypted event is sent. Fresh Megolm sends remain guarded by
        // the encrypted-room check below and by the SDK send queue.
        await syncOnceBestEffort(using: matrixClient, timeoutMs: 10_000, fullState: true, reason: "initial")
        await joinKnownInvitedRooms(using: matrixClient)

        let listener = MatrixRustSyncListener()
        let handle = matrixClient.syncV2(
            settings: SyncSettingsV2(timeoutMs: 30_000, fullState: false),
            listener: listener
        )

        client = matrixClient
        sessionContext = context
        syncListener = listener
        syncHandle = handle
        logger.info("Matrix Rust session configured for user \(context.safeUserId, privacy: .public) device \(context.deviceId, privacy: .public).")
    }

    func messages(for conversation: Conversation) async throws -> [ChatMessage] {
        let context = try requireSessionContext()
        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)

        await loadInitialHistoryPage(subscription, roomID: room.id())
        let items = subscription.listener.snapshot()

        return await mappedMessages(
            from: items,
            roomId: room.id(),
            ownUserId: context.userId,
            pinnedEventIds: await pinnedEventIds(in: room)
        )
    }

    func messageSnapshots(for conversation: Conversation) async throws -> AsyncStream<[ChatMessage]> {
        let context = try requireSessionContext()
        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)

        await loadInitialHistoryPage(subscription, roomID: room.id())

        let roomId = room.id()
        let initialPinnedEventIds = await pinnedEventIds(in: room)
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observerId = subscription.listener.addObserver { items in
                Task {
                    let pinnedEventIds = await self.pinnedEventIds(in: room, fallback: initialPinnedEventIds)
                    let messages = await self.mappedMessages(
                        from: items,
                        roomId: roomId,
                        ownUserId: context.userId,
                        pinnedEventIds: pinnedEventIds
                    )
                    continuation.yield(messages)
                }
            }

            continuation.onTermination = { _ in
                subscription.listener.removeObserver(id: observerId)
            }
        }
    }

    func hasEarlierMessages(for conversation: Conversation) async -> Bool {
        guard let roomID = conversation.activeMatrixRoomId else { return false }
        return timelineHasEarlierMessages[roomID] ?? false
    }

    func loadEarlierMessages(
        for conversation: Conversation,
        limit: Int
    ) async throws -> MessageHistoryPage {
        let context = try requireSessionContext()
        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)
        let pinned = await pinnedEventIds(in: room)
        let existing = await mappedMessages(
            from: subscription.listener.snapshot(),
            roomId: room.id(),
            ownUserId: context.userId,
            pinnedEventIds: pinned
        )
        let existingIDs = Set(existing.map(\.id))
        let previousCount = subscription.listener.snapshot().count
        let hasEarlier = try await subscription.timeline.paginateBackwards(
            numEvents: UInt16(min(max(1, limit), Int(UInt16.max)))
        )
        timelineHasEarlierMessages[room.id()] = hasEarlier
        await waitForTimelineChange(subscription, previousCount: previousCount)
        let current = await mappedMessages(
            from: subscription.listener.snapshot(),
            roomId: room.id(),
            ownUserId: context.userId,
            pinnedEventIds: await pinnedEventIds(in: room, fallback: pinned)
        )
        return MessageHistoryPage(
            messages: current.filter { !existingIDs.contains($0.id) },
            hasEarlier: hasEarlier
        )
    }

    func enrichedConversationPresentation(_ conversation: Conversation) async -> Conversation {
        guard let context = sessionContext,
              let room = try? await joinedRoom(for: conversation) else {
            return conversation
        }

        var result = conversation
        var matrixMembers: [RoomMember] = []
        if let iterator = try? await room.members() {
            while let chunk = iterator.nextChunk(chunkSize: 64), !chunk.isEmpty {
                matrixMembers.append(contentsOf: chunk)
                if matrixMembers.count >= 512 { break }
            }
        }

        var membersById: [String: ConversationMember] = [:]
        for member in result.members {
            let key = ConversationIdentity.canonicalKey(member.userId)
            guard !key.isEmpty else { continue }
            membersById[key] = member
        }
        for member in matrixMembers {
            let key = ConversationIdentity.canonicalKey(member.userId)
            guard !key.isEmpty else { continue }
            let existing = membersById[key]
            membersById[key] = ConversationMember(
                userId: existing.map { ConversationIdentity.preferredPersistentId($0.userId, member.userId) } ?? member.userId,
                displayName: existing?.displayName ?? Self.nonEmpty(member.displayName),
                role: existing?.role ?? (member.isServiceMember ? "bot" : nil),
                avatarDataUrl: await avatarDataURL(for: member.avatarUrl) ?? existing?.avatarDataUrl,
                avatarUrl: Self.nonEmpty(member.avatarUrl) ?? existing?.avatarUrl
            )
        }
        result.members = Array(membersById.values)
        result.memberCount = result.type == .direct && !result.members.isEmpty
            ? result.members.count
            : max(result.memberCount, result.members.count)

        if result.type == .direct,
           let peer = result.members.first(where: { !ConversationIdentity.matches($0.userId, context.userId) }) {
            result.title = Self.nonEmpty(peer.displayName) ?? result.title
            result.conversationAvatarDataUrl = peer.avatarDataUrl
            result.conversationAvatarUrl = peer.avatarUrl
        } else if let roomAvatarURL = try? await room.roomInfo().avatarUrl {
            result.conversationAvatarDataUrl = await avatarDataURL(for: roomAvatarURL) ?? result.conversationAvatarDataUrl
            result.conversationAvatarUrl = Self.nonEmpty(roomAvatarURL) ?? result.conversationAvatarUrl
        }
        return result
    }

    func updateGroupConversationAvatar(
        _ avatarDataUrl: String?,
        for conversation: Conversation
    ) async throws -> Conversation {
        guard conversation.type == .group else {
            throw CSMServiceError.invalidState("Avatar lze nastavit jen skupinové konverzaci.")
        }
        let room = try await joinedRoom(for: conversation)
        var updated = conversation

        guard let avatarDataUrl else {
            _ = try await room.sendStateEventRaw(
                eventType: "m.room.avatar",
                stateKey: "",
                content: "{}"
            )
            updated.conversationAvatarDataUrl = nil
            updated.conversationAvatarUrl = nil
            return updated
        }

        let payload = try Self.avatarUploadPayload(from: avatarDataUrl)
        let matrixClient = try requireClient()
        let matrixContentURL = try await matrixClient.uploadMedia(
            mimeType: payload.mimeType,
            data: payload.data,
            progressWatcher: nil
        )
        let contentData = try JSONSerialization.data(withJSONObject: ["url": matrixContentURL])
        guard let content = String(data: contentData, encoding: .utf8) else {
            throw CSMServiceError.invalidState("Avatar skupiny se nepodařilo připravit.")
        }
        _ = try await room.sendStateEventRaw(
            eventType: "m.room.avatar",
            stateKey: "",
            content: content
        )
        avatarDataURLCache[matrixContentURL] = avatarDataUrl
        unavailableAvatarURLs.remove(matrixContentURL)
        updated.conversationAvatarDataUrl = avatarDataUrl
        updated.conversationAvatarUrl = matrixContentURL
        return updated
    }

    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage {
        try await sendMessage(OutgoingMessageDraft(body: body), to: conversation)
    }

    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        try await sendMessageOnce(draft, to: conversation)
    }

    func startLiveLocationShare(
        durationSeconds: TimeInterval,
        in conversation: Conversation
    ) async throws {
        let room = try await joinedRoom(for: conversation)
        let boundedSeconds = min(max(durationSeconds, 60), 8 * 60 * 60)
        let startedAt = Date()
        liveLocationCompatibilitySessions[room.id()] = LiveLocationCompatibilitySession(
            shareId: UUID().uuidString.lowercased(),
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(boundedSeconds),
            durationSeconds: Int(boundedSeconds.rounded()),
            latestLocation: nil
        )
    }

    func updateLiveLocation(
        _ location: GeoPoint,
        in conversation: Conversation
    ) async throws {
        let room = try await joinedRoom(for: conversation)
        if var session = liveLocationCompatibilitySessions[room.id()] {
            session.latestLocation = location
            liveLocationCompatibilitySessions[room.id()] = session
            try await sendWebCompatibleLiveLocation(
                location,
                session: session,
                status: "live",
                room: room
            )
        }
    }

    func stopLiveLocationShare(in conversation: Conversation) async throws {
        let room = try await joinedRoom(for: conversation)
        if let session = liveLocationCompatibilitySessions.removeValue(forKey: room.id()),
           let latestLocation = session.latestLocation {
            try await sendWebCompatibleLiveLocation(
                latestLocation,
                session: session,
                status: "ended",
                room: room
            )
        }
    }

    /// COP publishes live location as ordinary `m.room.message` events.
    ///
    /// Matrix's experimental MSC3489 start event is a room state event. Rooms
    /// commonly require moderator power level 50 for state events, so regular
    /// members cannot start a share. COP's established message envelope is
    /// accepted at the normal message power level and is already consumed by
    /// the web client. Numeric coordinates deliberately stay in `geo_uri`:
    /// Matrix canonical JSON rejects floating-point values.
    private func sendWebCompatibleLiveLocation(
        _ location: GeoPoint,
        session: LiveLocationCompatibilitySession,
        status: String,
        room: Room
    ) async throws {
        var geoURI = "geo:\(location.lat),\(location.lon)"
        let roundedAccuracy: Int?
        if let accuracy = location.accuracyM, accuracy.isFinite, accuracy >= 0 {
            roundedAccuracy = Int(accuracy.rounded())
            geoURI += ";u=\(roundedAccuracy!)"
        } else {
            roundedAccuracy = nil
        }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        var copLocation: [String: Any] = [
            "live": [
                "durationSeconds": session.durationSeconds,
                "expiresAt": formatter.string(from: session.expiresAt),
                "shareId": session.shareId,
                "startedAt": formatter.string(from: session.startedAt),
                "status": status,
                "updatedAt": formatter.string(from: now)
            ],
            "source": "device",
            "updatedAt": formatter.string(from: now)
        ]
        if let roundedAccuracy {
            copLocation["accuracyM"] = roundedAccuracy
        }

        let description = status == "ended" ? "Sdílení polohy ukončeno" : "Živá poloha"
        let content: [String: Any] = [
            "body": Self.liveLocationCompatibilityBody,
            "geo_uri": geoURI,
            "msgtype": "m.location",
            "m.asset": ["type": "m.self"],
            "m.location": [
                "description": description,
                "uri": geoURI
            ],
            "m.text": description,
            "m.ts": Int64((now.timeIntervalSince1970 * 1_000).rounded()),
            "cz.cop.location": copLocation
        ]
        let data = try JSONSerialization.data(withJSONObject: content)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CSMServiceError.invalidState("Aktualizaci polohy se nepodařilo připravit.")
        }
        try await room.sendRaw(eventType: "m.room.message", content: json)
    }

    private func sendMessageOnce(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        let context = try requireSessionContext()
        guard !draft.isEmpty else {
            throw CSMServiceError.invalidState("Zprava je prazdna.")
        }
        if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
            throw CSMServiceError.invalidState(validationError)
        }

        let room = try await joinedRoom(for: conversation)
        try await ensureEncryptedRoomIfRequired(room, conversation: conversation, context: context)
        await enableAllSendQueuesBestEffort(reason: "pre-send")
        let subscription = try await timelineSubscription(for: room)

        var confirmedEventId: String?
        if draft.attachments.isEmpty {
            confirmedEventId = try await sendText(
                draft.body,
                replyTo: draft.replyTo,
                room: room,
                subscription: subscription
            )
        } else {
            try await sendStructuredDraft(draft, room: room, subscription: subscription)
        }

        return ChatMessage(
            id: confirmedEventId ?? "matrix-local-\(UUID().uuidString)",
            roomId: room.id(),
            senderId: context.userId,
            senderDisplayName: Self.matrixDisplayName(context.userId),
            body: draft.body,
            attachments: draft.attachments.map { attachment in
                var sentAttachment = attachment
                sentAttachment.localOnly = false
                return sentAttachment
            },
            replyTo: draft.replyTo,
            sentAt: .now,
            deliveryState: .sent,
            isOwnMessage: true
        )
    }

    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        let key = String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        guard !key.isEmpty else { return message }
        guard message.deliveryState != .pending else {
            throw CSMServiceError.invalidState("Reakci na lokalne cekajici zpravu nelze synchronizovat s Matrix.")
        }

        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)

        _ = try await subscription.timeline.toggleReaction(itemId: Self.eventOrTransactionId(for: message.id), key: key)
        return message.applyingReactionToggle(key)
    }

    func redactMessage(_ message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        guard !message.isDeleted else { return message }

        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)
        try await subscription.timeline.redactEvent(
            eventOrTransactionId: Self.eventOrTransactionId(for: message.id),
            reason: "CSM message deleted"
        )
        return message.markedDeleted()
    }

    func setMessagePinned(_ pinned: Bool, message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        guard !message.isDeleted else {
            throw CSMServiceError.invalidState("Smazanou zpravu nelze pripnout.")
        }
        guard message.id.hasPrefix("$") else {
            throw CSMServiceError.invalidState("Zpravu lze pripnout az po potvrzeni serverem.")
        }

        let room = try await joinedRoom(for: conversation)
        let subscription = try await timelineSubscription(for: room)
        if pinned {
            _ = try await subscription.timeline.pinEvent(eventId: message.id)
        } else {
            _ = try await subscription.timeline.unpinEvent(eventId: message.id)
        }
        return message.settingPinned(pinned)
    }

    func leaveConversation(_ conversation: Conversation) async throws {
        guard conversation.type == .group else {
            throw CSMServiceError.invalidState("Matrix leave je dostupný jen pro skupinové konverzace.")
        }
        guard let roomId = conversation.activeMatrixRoomId else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }

        let room = try await roomForLeave(roomId: roomId, conversationId: conversation.conversationId)
        try await room.leave()
        if let subscription = timelineSubscriptions.removeValue(forKey: roomId) {
            subscription.handle.cancel()
        }
    }

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {
        guard let client else { return }
        #if os(iOS)
        let deviceName = await MainActor.run { UIDevice.current.name }
        #else
        let deviceName = "CSM Messenger"
        #endif

        let identifiers = PusherIdentifiers(
            pushkey: pushKey,
            appId: Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm.messenger"
        )
        let kind = PusherKind.http(
            data: HttpPusherData(
                url: pushGatewayURL.absoluteString,
                format: .eventIdOnly,
                defaultPayload: nil
            )
        )
        try? await client.setPusher(
            identifiers: identifiers,
            kind: kind,
            appDisplayName: "CSM Messenger",
            deviceDisplayName: deviceName,
            profileTag: nil,
            lang: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            append: false
        )
    }

    // MARK: - MatrixEncryptionRecoveryManaging

    func encryptionRecoveryStatus() async -> MatrixEncryptionRecoveryStatus {
        guard let client else {
            return .unavailable("Matrix session is not configured on this device.")
        }

        let encryption = client.encryption()
        let backupState = encryption.backupState()
        let recoveryState = encryption.recoveryState()
        let backupExistsResult: Result<Bool, any Error>
        do {
            backupExistsResult = .success(try await encryption.backupExistsOnServer())
        } catch {
            backupExistsResult = .failure(error)
        }

        return Self.matrixEncryptionRecoveryStatus(
            backupState: backupState,
            recoveryState: recoveryState,
            backupExistsResult: backupExistsResult
        )
    }

    func createEncryptionRecovery(reset: Bool) async throws -> String {
        let encryption = try requireClient().encryption()
        let statusBeforeCreate = await encryptionRecoveryStatus()
        do {
            return try await createEncryptionRecovery(
                using: encryption,
                resetExistingRecovery: reset,
                reason: reset ? "encryption-recovery-reset-created" : "encryption-recovery-created"
            )
        } catch {
            if Self.shouldDeleteServerBackupBeforeCleanRecovery(reset: reset, status: statusBeforeCreate),
               Self.isBackupExistsOnServerError(error) {
                let initialError = error
                logger.warning(
                    "Matrix recovery clean reset hit an existing server key backup. Deleting the server backup version before creating a new recovery cycle: \(initialError.localizedDescription, privacy: .public)"
                )
                do {
                    let deletedVersion = try await deleteServerKeyBackupForCleanRecovery()
                    logger.warning(
                        "Matrix server key backup deletion completed version=\(deletedVersion ?? "none", privacy: .public). Retrying clean recovery creation."
                    )
                    return try await createEncryptionRecovery(
                        using: encryption,
                        resetExistingRecovery: true,
                        reason: "encryption-recovery-reset-created-after-server-backup-delete"
                    )
                } catch {
                    throw Self.recoveryCreationUserFacingError(
                        technicalDetail: [
                            "initialStatus=\(statusBeforeCreate.technicalSummary)",
                            "initialError=\(initialError.localizedDescription)",
                            "serverBackupResetError=\(error.localizedDescription)"
                        ].joined(separator: "\n")
                    )
                }
            }
            if Self.shouldRetryCleanRecoveryCreation(reset: reset, status: statusBeforeCreate) {
                let initialError = error
                logger.warning(
                    "Matrix recovery create failed while no key backup exists and recovery state is \(statusBeforeCreate.recoveryState, privacy: .public). Retrying after recovery cleanup: \(initialError.localizedDescription, privacy: .public)"
                )
                do {
                    return try await createEncryptionRecovery(
                        using: encryption,
                        resetExistingRecovery: true,
                        reason: "encryption-recovery-created-after-clean-retry"
                    )
                } catch {
                    throw Self.recoveryCreationUserFacingError(
                        technicalDetail: [
                            "initialStatus=\(statusBeforeCreate.technicalSummary)",
                            "initialError=\(initialError.localizedDescription)",
                            "retryError=\(error.localizedDescription)"
                        ].joined(separator: "\n")
                    )
                }
            }
            throw MatrixEncryptionRecoveryUserFacingError(
                reason: .generic,
                userMessage: CSMLocalization.text(
                    "matrix.recovery.create_failed.actionable",
                    fallback: "Nový E2EE obnovovací klíč se nepodařilo vytvořit. Zkuste to znovu po synchronizaci, případně použijte přihlášení a párování z webové aplikace COP."
                ),
                technicalDetail: error.localizedDescription
            )
        }
    }

    private func createEncryptionRecovery(
        using encryption: Encryption,
        resetExistingRecovery: Bool,
        reason: String
    ) async throws -> String {
        if resetExistingRecovery {
            do {
                try await encryption.disableRecovery()
            } catch {
                logger.warning(
                    "Matrix recovery cleanup before creation did not complete cleanly; continuing with enableRecovery: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        let recoveryKey = try await encryption.enableRecovery(
            waitForBackupsToUpload: false,
            passphrase: nil,
            progressListener: MatrixRustEnableRecoveryProgressListener()
        )
        try? await encryption.enableBackups()
        await enableAllSendQueuesBestEffort(reason: reason)
        return recoveryKey
    }

    /// Explicit clean-start recovery may destroy only the Matrix key-backup
    /// version. It never deletes Matrix rooms, COP conversations, user tokens or
    /// local message history; those remain under their own lifecycle controls.
    private func deleteServerKeyBackupForCleanRecovery() async throws -> String? {
        let context = try requireSessionContext()
        guard let version = try await currentServerKeyBackupVersion(context: context) else {
            return nil
        }
        try await deleteServerKeyBackupVersion(version, context: context)
        return version
    }

    private func currentServerKeyBackupVersion(context: MatrixRustSessionContext) async throws -> String? {
        let url = try Self.matrixClientURL(
            homeserver: context.homeserverURL,
            path: "/_matrix/client/v3/room_keys/version"
        )
        var request = Self.authorizedMatrixRequest(url: url, method: "GET", context: context)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CSMServiceError.unavailable("Matrix key-backup version lookup did not return HTTP.")
        }
        switch http.statusCode {
        case 200..<300:
            let payload = try JSONDecoder().decode(MatrixKeyBackupVersionResponse.self, from: data)
            let version = payload.version?.trimmingCharacters(in: .whitespacesAndNewlines)
            return version?.isEmpty == true ? nil : version
        case 404:
            return nil
        default:
            throw Self.matrixKeyBackupHTTPError(data: data, response: http, operation: "version lookup")
        }
    }

    private func deleteServerKeyBackupVersion(
        _ version: String,
        context: MatrixRustSessionContext
    ) async throws {
        let encodedVersion = Self.percentEncodedMatrixPathSegment(version)
        let url = try Self.matrixClientURL(
            homeserver: context.homeserverURL,
            path: "/_matrix/client/v3/room_keys/version/\(encodedVersion)"
        )
        var request = Self.authorizedMatrixRequest(url: url, method: "DELETE", context: context)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CSMServiceError.unavailable("Matrix key-backup deletion did not return HTTP.")
        }
        switch http.statusCode {
        case 200..<300, 404:
            return
        default:
            throw Self.matrixKeyBackupHTTPError(data: data, response: http, operation: "deletion")
        }
    }

    func resetEncryptionRecovery(oldRecoveryKey: String) async throws -> String {
        let recoveryKeyCandidates = Self.recoveryKeyCandidates(from: oldRecoveryKey)
        guard !recoveryKeyCandidates.isEmpty else {
            return try await createEncryptionRecovery(reset: true)
        }

        let matrixClient = try requireClient()
        let encryption = matrixClient.encryption()
        var firstError: (any Error)?
        var lastError: (any Error)?

        logger.warning(
            "Matrix recovery reset started with an old user-held key. Server recovery will be rotated and a new key will be generated."
        )

        for (index, recoveryKey) in recoveryKeyCandidates.enumerated() {
            do {
                let newRecoveryKey = try await encryption.recoverAndReset(oldRecoveryKey: recoveryKey)
                try? await encryption.enableBackups()
                await enableAllSendQueuesBestEffort(reason: "encryption-recovery-reset")
                await syncOnceBestEffort(using: matrixClient, timeoutMs: 10_000, fullState: true, reason: "encryption-recovery-reset")
                logger.info(
                    "Matrix recovery reset completed attempt=\(index + 1, privacy: .public) backupState=\(encryption.backupState().csmName, privacy: .public) recoveryState=\(encryption.recoveryState().csmName, privacy: .public)."
                )
                return newRecoveryKey
            } catch {
                firstError = firstError ?? error
                lastError = error
                logger.warning(
                    "Matrix recovery recoverAndReset attempt \(index + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw Self.preferredRecoveryError(firstError: firstError, lastError: lastError)
    }

    func restoreEncryptionRecovery(recoveryKey: String) async throws {
        let recoveryKeyCandidates = Self.recoveryKeyCandidates(from: recoveryKey)
        guard !recoveryKeyCandidates.isEmpty else {
            throw CSMServiceError.invalidState(CSMLocalization.text("matrix.recovery.key_required", fallback: "Zadejte obnovovací klíč."))
        }

        let matrixClient = try requireClient()
        let encryption = matrixClient.encryption()
        do {
            try await restoreEncryptionRecovery(
                using: matrixClient,
                encryption: encryption,
                recoveryKeyCandidates: recoveryKeyCandidates,
                syncReason: "encryption-recovery"
            )
        } catch {
            if Self.isWebSecretStorageRetryCandidate(error) {
                do {
                    try await retryEncryptionRecoveryAfterLocalStoreReset(
                        recoveryKeyCandidates: recoveryKeyCandidates,
                        originalError: error
                    )
                    return
                } catch {
                    throw Self.userFacingRecoveryError(from: error)
                }
            }
            if let userFacingError = error as? MatrixEncryptionRecoveryUserFacingError {
                throw userFacingError
            }
            throw MatrixEncryptionRecoveryUserFacingError(
                reason: .generic,
                userMessage: CSMLocalization.text(
                    "matrix.recovery.restore_failed.actionable",
                    fallback: "Obnovu E2EE se nepodařilo dokončit. Pokud stejný klíč funguje ve webu, připravte obnovu pro iPhone/iPad ve webové aplikaci COP nebo začněte novým čistým E2EE stavem bez staré historie."
                ),
                technicalDetail: error.localizedDescription
            )
        }
    }

    private func restoreEncryptionRecovery(
        using matrixClient: Client,
        encryption: Encryption,
        recoveryKeyCandidates: [String],
        syncReason: String
    ) async throws {
        logger.info(
            "Matrix recovery restore started candidates=\(recoveryKeyCandidates.count, privacy: .public) backupState=\(encryption.backupState().csmName, privacy: .public) recoveryState=\(encryption.recoveryState().csmName, privacy: .public)."
        )
        try await recoverEncryption(encryption, recoveryKeyCandidates: recoveryKeyCandidates)
        try? await encryption.enableBackups()
        await enableAllSendQueuesBestEffort(reason: "encryption-recovery-restored")
        await syncOnceBestEffort(using: matrixClient, timeoutMs: 10_000, fullState: true, reason: syncReason)
        // Recreate room timelines after the one-shot backup download. Existing
        // timeline subscriptions can otherwise keep their pre-recovery
        // UnableToDecrypt items even though the SDK has imported matching keys.
        cancelTimelineSubscriptions()
        logger.info(
            "Matrix recovery restore completed backupState=\(encryption.backupState().csmName, privacy: .public) recoveryState=\(encryption.recoveryState().csmName, privacy: .public)."
        )
    }

    private func recoverEncryption(
        _ encryption: Encryption,
        recoveryKeyCandidates: [String]
    ) async throws {
        var firstError: (any Error)?
        var lastError: (any Error)?

        for (index, recoveryKey) in recoveryKeyCandidates.enumerated() {
            do {
                try await encryption.recover(recoveryKey: recoveryKey)
                return
            } catch {
                firstError = firstError ?? error
                lastError = error
                logger.warning(
                    "Matrix recovery recover attempt \(index + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if await enableBackupsAfterPartialRecoveryIfPossible(encryption) {
                    return
                }
            }

            do {
                try await encryption.recoverAndFixBackup(recoveryKey: recoveryKey)
                return
            } catch {
                lastError = error
                logger.warning(
                    "Matrix recovery recoverAndFixBackup attempt \(index + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
                if await enableBackupsAfterPartialRecoveryIfPossible(encryption) {
                    return
                }
            }
        }

        throw Self.preferredRecoveryError(firstError: firstError, lastError: lastError)
    }

    private func retryEncryptionRecoveryAfterLocalStoreReset(
        recoveryKeyCandidates: [String],
        originalError: any Error
    ) async throws {
        guard let bootstrap = lastBootstrap else {
            throw originalError
        }

        logger.warning(
            "Matrix recovery hit web secret-storage compatibility failure. Resetting local Matrix store and retrying once without changing server recovery: \(originalError.localizedDescription, privacy: .public)"
        )
        do {
            try await configure(with: bootstrap, resetLocalStore: true)
            let retryClient = try requireClient()
            try await restoreEncryptionRecovery(
                using: retryClient,
                encryption: retryClient.encryption(),
                recoveryKeyCandidates: recoveryKeyCandidates,
                syncReason: "encryption-recovery-local-store-retry"
            )
        } catch {
            logger.error(
                "Matrix recovery local-store retry failed: \(error.localizedDescription, privacy: .public)"
            )
            throw Self.preferredRecoveryError(firstError: originalError, lastError: error)
        }
    }

    private func enableBackupsAfterPartialRecoveryIfPossible(_ encryption: Encryption) async -> Bool {
        do {
            try await encryption.enableBackups()
            return encryption.backupState().isEnabledForRecovery
        } catch {
            return encryption.backupState().isEnabledForRecovery
        }
    }

    // MARK: - Room and timeline

    private func joinedRoom(for conversation: Conversation) async throws -> Room {
        let matrixClient = try requireClient()
        guard let roomId = conversation.activeMatrixRoomId else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }

        if let room = try matrixClient.getRoom(roomId: roomId) {
            return try await prepareJoinedRoom(room)
        }

        let viaServers = conversation.matrix?.serverName.map { [$0] } ?? [sessionContext?.serverName].compactMap { $0 }
        do {
            let room = try await matrixClient.joinRoomByIdOrAlias(roomIdOrAlias: roomId, serverNames: viaServers)
            return try await prepareJoinedRoom(room)
        } catch {
            logger.warning("Matrix direct join failed for room \(roomId, privacy: .public), retrying after sync: \(error.localizedDescription, privacy: .public)")
        }

        await syncOnceBestEffort(using: matrixClient, timeoutMs: 10_000, fullState: true, reason: "room-lookup")
        await joinKnownInvitedRooms(using: matrixClient)
        if let room = try matrixClient.getRoom(roomId: roomId) {
            return try await prepareJoinedRoom(room)
        }

        let room = try await matrixClient.joinRoomByIdOrAlias(roomIdOrAlias: roomId, serverNames: viaServers)
        return try await prepareJoinedRoom(room)
    }

    private func roomForLeave(roomId: String, conversationId: String) async throws -> Room {
        let matrixClient = try requireClient()
        if let room = try matrixClient.getRoom(roomId: roomId) {
            return room
        }

        await syncOnceBestEffort(using: matrixClient, timeoutMs: 10_000, fullState: true, reason: "room-leave-lookup")
        if let room = try matrixClient.getRoom(roomId: roomId) {
            return room
        }

        throw MatrixAPIError.missingRoomBinding(conversationId)
    }

    private func pinnedEventIds(in room: Room, fallback: Set<String> = []) async -> Set<String> {
        do {
            return Set(try await room.roomInfo().pinnedEventIds)
        } catch {
            return fallback
        }
    }

    private func prepareJoinedRoom(_ room: Room) async throws -> Room {
        let membership = try await room.roomInfo().membership
        switch membership {
        case .invited, .left:
            try await room.join()
        case .joined:
            break
        case .knocked:
            throw CSMServiceError.disabled("Matrix room ceka na schvaleni vstupu.")
        case .banned:
            throw CSMServiceError.disabled("Matrix room je pro uzivatele zablokovana.")
        }
        return room
    }

    private func joinKnownInvitedRooms(using matrixClient: Client) async {
        var joinedRoom = false
        for room in matrixClient.rooms() {
            guard (try? await room.roomInfo().membership) == .invited else { continue }
            do {
                try await room.join()
                joinedRoom = true
            } catch {
                logger.warning("Matrix invite auto-join failed for room \(room.id(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if joinedRoom {
            await matrixClient.enableAllSendQueues(enable: true)
        }
    }

    private func syncOnceBestEffort(
        using matrixClient: Client,
        timeoutMs: UInt64,
        fullState: Bool,
        reason: String
    ) async {
        do {
            _ = try await matrixClient.syncOnceV2(settings: SyncSettingsV2(timeoutMs: timeoutMs, fullState: fullState))
        } catch {
            logger.warning("Matrix best-effort sync failed during \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func timelineSubscription(for room: Room) async throws -> MatrixRustTimelineSubscription {
        let roomId = room.id()
        if let subscription = timelineSubscriptions[roomId] {
            return subscription
        }

        let timeline = try await room.timeline()
        let listener = MatrixRustTimelineCache()
        let handle = await timeline.addListener(listener: listener)
        let subscription = MatrixRustTimelineSubscription(
            timeline: timeline,
            listener: listener,
            handle: handle
        )
        timelineSubscriptions[roomId] = subscription
        return subscription
    }

    private func loadInitialHistoryPage(
        _ subscription: MatrixRustTimelineSubscription,
        roomID: String
    ) async {
        guard subscription.listener.snapshot().isEmpty else { return }
        let previousCount = subscription.listener.snapshot().count
        do {
            timelineHasEarlierMessages[roomID] = try await subscription.timeline.paginateBackwards(
                numEvents: Self.historyPageSize
            )
            await waitForTimelineChange(subscription, previousCount: previousCount)
        } catch {
            logger.warning(
                "Matrix initial history page failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func waitForTimelineChange(
        _ subscription: MatrixRustTimelineSubscription,
        previousCount: Int
    ) async {
        for _ in 0..<10 where subscription.listener.snapshot().count <= previousCount {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func ensureEncryptedRoomIfRequired(
        _ room: Room,
        conversation: Conversation,
        context: MatrixRustSessionContext
    ) async throws {
        guard context.e2eeRequired || conversation.e2eeRequired || conversation.encrypted else {
            return
        }
        if (try? await room.latestEncryptionState()) == .encrypted {
            return
        }
        guard await room.isEncrypted() else {
            throw CSMServiceError.disabled("Matrix room neni sifrovana; odeslani plaintext obsahu je blokovane.")
        }
    }

    // MARK: - Send helpers

    private func sendStructuredDraft(
        _ draft: OutgoingMessageDraft,
        room: Room,
        subscription: MatrixRustTimelineSubscription
    ) async throws {
        if !draft.attachments.isEmpty, draft.attachments.allSatisfy({ $0.kind == .safetyStatus }) {
            let body = draft.body.isEmpty
                ? draft.attachments.map(\.title).joined(separator: "\n")
                : draft.body
            _ = try await sendText(body, replyTo: draft.replyTo, room: room, subscription: subscription)
            return
        }

        for (index, attachment) in draft.attachments.enumerated() {
            let caption = index == 0 ? draft.body : nil
            let replyTo = index == 0 ? draft.replyTo : nil
            try await sendAttachment(
                attachment,
                caption: caption,
                replyTo: replyTo,
                room: room,
                subscription: subscription
            )
        }
    }

    private func sendText(
        _ body: String,
        replyTo: MessageReplyReference?,
        room: Room,
        subscription: MatrixRustTimelineSubscription
    ) async throws -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let content = messageEventContentFromMarkdown(md: trimmed)
        if let replyTo {
            _ = try await subscription.timeline.sendReply(msg: content, eventId: replyTo.messageId)
            return nil
        } else {
            let queueTracker = MatrixRustSendQueueTracker(roomId: room.id())
            let roomQueueHandle = try? await room.subscribeToSendQueueUpdates(listener: queueTracker)
            let matrixClient = try? requireClient()
            let clientQueueHandle = try? await matrixClient?.subscribeToSendQueueUpdates(listener: queueTracker)
            if roomQueueHandle == nil, clientQueueHandle == nil {
                logger.warning("Matrix send queue tracker unavailable for room \(room.id(), privacy: .public); falling back to timeline echo only.")
            }
            defer {
                roomQueueHandle?.cancel()
                clientQueueHandle?.cancel()
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            let baselineTimelineItems = subscription.listener.snapshot()
            let baselineTransactionIds = queueTracker.snapshotTransactionIds()
            let baselineRemoteEventIds = Self.remoteEventIds(in: baselineTimelineItems)
            let startedAtMs = Self.currentUnixMilliseconds()
            let sendHandle = try await subscription.timeline.send(msg: content)
            return try await waitForSendQueueConfirmation(
                room: room,
                subscription: subscription,
                body: trimmed,
                startedAtMs: startedAtMs,
                queueTracker: roomQueueHandle == nil && clientQueueHandle == nil ? nil : queueTracker,
                queueErrorTracker: nil,
                baselineTransactionIds: baselineTransactionIds,
                baselineRemoteEventIds: baselineRemoteEventIds,
                sendHandle: sendHandle
            )
        }
    }

    private func waitForSendQueueConfirmation(
        room: Room,
        subscription: MatrixRustTimelineSubscription,
        body: String,
        startedAtMs: UInt64,
        queueTracker: MatrixRustSendQueueTracker?,
        queueErrorTracker: MatrixRustSendQueueErrorTracker?,
        baselineTransactionIds: Set<String>,
        baselineRemoteEventIds: Set<String>,
        sendHandle: SendHandle
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(20)
        var attemptedAutomaticRecovery = false
        var lastFailureDescription: String?
        var trackedTransactionId: String?
        var latestMatchingEvent: EventTimelineItem?

        repeat {
            if let eventId = Self.latestConfirmedOwnEventId(
                in: subscription.listener.snapshot(),
                body: body,
                startedAtMs: startedAtMs,
                baselineRemoteEventIds: baselineRemoteEventIds
            ) {
                return eventId
            }

            if let event = Self.latestOwnLocalEcho(
                in: subscription.listener.snapshot(),
                body: body,
                startedAtMs: startedAtMs
            ) {
                latestMatchingEvent = event
                trackedTransactionId = trackedTransactionId ?? Self.transactionId(from: event)
                switch event.localSendState {
                case .sent(let eventId):
                    return eventId
                case .sendingFailed(let error, let isRecoverable):
                    lastFailureDescription = Self.queueWedgeDescription(error, recoverable: isRecoverable)
                    if let eventId = await latestConfirmedOwnEventId(
                        room: room,
                        subscription: subscription,
                        body: body,
                        startedAtMs: startedAtMs,
                        baselineRemoteEventIds: baselineRemoteEventIds
                    ) {
                        return eventId
                    }
                    if !attemptedAutomaticRecovery,
                       try await attemptAutomaticSendQueueRecovery(
                        error: error,
                        event: event,
                        fallbackSendHandle: sendHandle,
                        room: room
                       ) {
                        attemptedAutomaticRecovery = true
                        lastFailureDescription = nil
                        await enableAllSendQueuesBestEffort(reason: "trust-recovery")
                        try await Task.sleep(nanoseconds: 350_000_000)
                        continue
                    }
                    throw CSMServiceError.unavailable(
                        "Matrix E2EE send queue selhala: \(lastFailureDescription ?? "unknown failure")."
                    )
                case .notSentYet:
                    break
                case nil:
                    if let eventId = Self.confirmedEventId(from: event) {
                        return eventId
                    }
                }
            }

            if trackedTransactionId == nil,
               let candidate = queueTracker?.singleNewTransactionId(excluding: baselineTransactionIds) {
                trackedTransactionId = candidate
            }

            if let trackedTransactionId,
               let eventId = queueTracker?.sentEventId(for: trackedTransactionId) {
                return eventId
            }

            if trackedTransactionId == nil,
               let eventId = queueTracker?.singleNewSentEventId(excluding: baselineTransactionIds) {
                return eventId
            }

            if let trackedTransactionId,
               let failure = queueTracker?.failure(for: trackedTransactionId) {
                lastFailureDescription = Self.queueWedgeDescription(failure.error, recoverable: failure.isRecoverable)
                if let eventId = await latestConfirmedOwnEventId(
                    room: room,
                    subscription: subscription,
                    body: body,
                    startedAtMs: startedAtMs,
                    baselineRemoteEventIds: baselineRemoteEventIds
                ) {
                    return eventId
                }
                if !attemptedAutomaticRecovery,
                   try await attemptAutomaticSendQueueRecovery(
                    error: failure.error,
                    event: latestMatchingEvent,
                    fallbackSendHandle: sendHandle,
                    room: room
                   ) {
                    attemptedAutomaticRecovery = true
                    lastFailureDescription = nil
                    await enableAllSendQueuesBestEffort(reason: "trust-recovery")
                    try await Task.sleep(nanoseconds: 350_000_000)
                    continue
                }
                throw CSMServiceError.unavailable(
                    "Matrix E2EE send queue selhala: \(lastFailureDescription ?? "unknown failure")."
                )
            }

            if let queueError = queueErrorTracker?.latestErrorDescription() {
                lastFailureDescription = queueError
            }

            try await Task.sleep(nanoseconds: 350_000_000)
        } while Date() < deadline

        if let lastFailureDescription {
            throw CSMServiceError.unavailable("Matrix E2EE send queue zustala zablokovana: \(lastFailureDescription).")
        }

        if let eventId = await latestConfirmedOwnEventId(
            room: room,
            subscription: subscription,
            body: body,
            startedAtMs: startedAtMs,
            baselineRemoteEventIds: baselineRemoteEventIds
        ) {
            return eventId
        }

        if let eventId = try await attemptTimeoutSendQueueRecovery(
            room: room,
            subscription: subscription,
            body: body,
            startedAtMs: startedAtMs,
            queueTracker: queueTracker,
            queueErrorTracker: queueErrorTracker,
            baselineTransactionIds: baselineTransactionIds,
            baselineRemoteEventIds: baselineRemoteEventIds,
            sendHandle: sendHandle,
            trackedTransactionId: trackedTransactionId
        ) {
            return eventId
        }

        let aborted = (try? await sendHandle.abort()) ?? false
        if !aborted {
            let fallbackEventId = Self.unconfirmedEventId(transactionId: trackedTransactionId)
            logger.warning(
                "Matrix send queue confirmation timed out for room \(room.id(), privacy: .public), but the local echo could not be aborted. Treating message as sent with fallback id \(fallbackEventId, privacy: .public)."
            )
            return fallbackEventId
        }

        throw CSMServiceError.unavailable(
            "Matrix E2EE send queue nepotvrdila odeslani v limitu; lokalni Matrix echo bylo zruseno a zprava zustane v aplikacni sifrovane fronte."
        )
    }

    private func attemptTimeoutSendQueueRecovery(
        room: Room,
        subscription: MatrixRustTimelineSubscription,
        body: String,
        startedAtMs: UInt64,
        queueTracker: MatrixRustSendQueueTracker?,
        queueErrorTracker: MatrixRustSendQueueErrorTracker?,
        baselineTransactionIds: Set<String>,
        baselineRemoteEventIds: Set<String>,
        sendHandle: SendHandle,
        trackedTransactionId: String?
    ) async throws -> String? {
        do {
            try await sendHandle.tryResend()
            await enableAllSendQueuesBestEffort(reason: "timeout-resend")
        } catch {
            logger.warning("Matrix send queue timeout resend skipped for room \(room.id(), privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }

        logger.warning("Matrix send queue timeout reached for room \(room.id(), privacy: .public); forced SDK resend before falling back to local outbox.")
        var trackedTransactionId = trackedTransactionId
        let deadline = Date().addingTimeInterval(8)

        repeat {
            if let eventId = await latestConfirmedOwnEventId(
                room: room,
                subscription: subscription,
                body: body,
                startedAtMs: startedAtMs,
                baselineRemoteEventIds: baselineRemoteEventIds
            ) {
                return eventId
            }

            if trackedTransactionId == nil,
               let candidate = queueTracker?.singleNewTransactionId(excluding: baselineTransactionIds) {
                trackedTransactionId = candidate
            }

            if let trackedTransactionId,
               let eventId = queueTracker?.sentEventId(for: trackedTransactionId) {
                return eventId
            }

            if trackedTransactionId == nil,
               let eventId = queueTracker?.singleNewSentEventId(excluding: baselineTransactionIds) {
                return eventId
            }

            if let trackedTransactionId,
               let failure = queueTracker?.failure(for: trackedTransactionId) {
                throw CSMServiceError.unavailable(
                    "Matrix E2EE send queue selhala po obnoveni: \(Self.queueWedgeDescription(failure.error, recoverable: failure.isRecoverable))."
                )
            }

            if let queueError = queueErrorTracker?.latestErrorDescription() {
                throw CSMServiceError.unavailable(
                    "Matrix E2EE send queue zustala zablokovana po obnoveni: \(queueError)."
                )
            }

            try await Task.sleep(nanoseconds: 350_000_000)
        } while Date() < deadline

        return nil
    }

    private func latestConfirmedOwnEventId(
        room: Room,
        subscription: MatrixRustTimelineSubscription,
        body: String,
        startedAtMs: UInt64,
        baselineRemoteEventIds: Set<String>
    ) async -> String? {
        if let eventId = Self.latestOwnRemoteEventId(
            in: subscription.listener.snapshot(),
            body: body,
            startedAtMs: startedAtMs,
            baselineRemoteEventIds: baselineRemoteEventIds
        ) {
            return eventId
        }

        if let matrixClient = try? requireClient() {
            await syncOnceBestEffort(using: matrixClient, timeoutMs: 3_000, fullState: false, reason: "send-confirmation")
        }
        try? await Task.sleep(nanoseconds: 300_000_000)

        if let eventId = Self.latestOwnRemoteEventId(
            in: subscription.listener.snapshot(),
            body: body,
            startedAtMs: startedAtMs,
            baselineRemoteEventIds: baselineRemoteEventIds
        ) {
            return eventId
        }

        guard let latestEventId = await subscription.timeline.latestEventId(),
              let event = try? await subscription.timeline.getEventTimelineItemByEventId(eventId: latestEventId),
              let confirmedEventId = Self.confirmedOwnEventIdAfterSend(
                from: event,
                body: body,
                startedAtMs: startedAtMs,
                baselineRemoteEventIds: baselineRemoteEventIds
              ) else {
            logger.warning("Matrix send confirmation fallback could not resolve a remote event id for room \(room.id(), privacy: .public).")
            return nil
        }
        if confirmedEventId != latestEventId {
            logger.warning("Matrix send confirmation resolved event id \(confirmedEventId, privacy: .public) while timeline latest id was \(latestEventId, privacy: .public).")
        }
        return confirmedEventId
    }

    private func attemptAutomaticSendQueueRecovery(
        error: QueueWedgeError,
        event: EventTimelineItem?,
        fallbackSendHandle: SendHandle,
        room: Room
    ) async throws -> Bool {
        let sendHandle = event?.lazyProvider.getSendHandle() ?? fallbackSendHandle

        switch error {
        case .insecureDevices(let userDeviceMap):
            guard !userDeviceMap.isEmpty else { return false }
            try await room.ignoreDeviceTrustAndResend(devices: userDeviceMap, sendHandle: sendHandle)
            logger.warning(
                "Matrix send queue auto-recovered insecure device trust wedge in room \(room.id(), privacy: .public), affected users \(userDeviceMap.count, privacy: .public)."
            )
            return true

        case .identityViolations(let users):
            guard !users.isEmpty else { return false }
            try await room.withdrawVerificationAndResend(userIds: users, sendHandle: sendHandle)
            logger.warning(
                "Matrix send queue auto-recovered identity trust wedge in room \(room.id(), privacy: .public), affected users \(users.count, privacy: .public)."
            )
            return true

        case .crossVerificationRequired, .missingMediaContent, .invalidMimeType, .genericApiError:
            return false
        }
    }

    private func enableAllSendQueuesBestEffort(reason: String) async {
        do {
            let matrixClient = try requireClient()
            await matrixClient.enableAllSendQueues(enable: true)
        } catch {
            logger.warning("Matrix send queue enable skipped during \(reason, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendAttachment(
        _ attachment: MessageAttachment,
        caption: String?,
        replyTo: MessageReplyReference?,
        room: Room,
        subscription: MatrixRustTimelineSubscription
    ) async throws {
        let timeline = subscription.timeline
        switch attachment.kind {
        case .location:
            guard let location = attachment.location else {
                throw CSMServiceError.invalidState("Poloha nema souradnice.")
            }
            try await timeline.sendLocation(
                body: caption?.isEmpty == false ? caption! : attachment.title,
                geoUri: "geo:\(location.lat),\(location.lon)",
                description: attachment.title,
                zoomLevel: nil,
                assetType: .pin,
                repliedToEventId: replyTo?.messageId
            )
        case .safetyStatus:
            let body = [caption, Optional(attachment.title)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            _ = try await sendText(body, replyTo: replyTo, room: room, subscription: subscription)
        case .image, .video, .document, .voiceNote, .sticker:
            let fileURL = try await MediaPipelineActor.shared.materializedFile(for: attachment)
            try await sendFileAttachment(
                attachment,
                fileURL: fileURL,
                caption: caption,
                replyTo: replyTo,
                timeline: timeline
            )
        }
    }

    private func sendFileAttachment(
        _ attachment: MessageAttachment,
        fileURL: URL,
        caption: String?,
        replyTo: MessageReplyReference?,
        timeline: Timeline
    ) async throws {
        let params = UploadParameters(
            source: .file(filename: fileURL.path),
            caption: caption,
            formattedCaption: nil,
            mentions: nil,
            inReplyTo: replyTo?.messageId
        )
        let size = UInt64(attachment.byteCount ?? attachment.payloadData?.count ?? 0)

        switch attachment.kind {
        case .image, .sticker:
            let handle = try timeline.sendImage(
                params: params,
                thumbnailSource: nil,
                imageInfo: ImageInfo(
                    height: nil,
                    width: nil,
                    mimetype: attachment.mimeType,
                    size: size,
                    thumbnailInfo: nil,
                    thumbnailSource: nil,
                    blurhash: nil,
                    isAnimated: nil
                )
            )
            try await handle.join()
        case .video:
            let handle = try timeline.sendVideo(
                params: params,
                thumbnailSource: nil,
                videoInfo: VideoInfo(
                    duration: attachment.durationSeconds,
                    height: nil,
                    width: nil,
                    mimetype: attachment.mimeType,
                    size: size,
                    thumbnailInfo: nil,
                    thumbnailSource: nil,
                    blurhash: nil
                )
            )
            try await handle.join()
        case .voiceNote:
            let handle = try timeline.sendVoiceMessage(
                params: params,
                audioInfo: AudioInfo(
                    duration: attachment.durationSeconds,
                    size: size,
                    mimetype: attachment.mimeType
                ),
                waveform: []
            )
            try await handle.join()
        case .document:
            let handle = try timeline.sendFile(
                params: params,
                fileInfo: FileInfo(
                    mimetype: attachment.mimeType,
                    size: size,
                    thumbnailInfo: nil,
                    thumbnailSource: nil
                )
            )
            try await handle.join()
        case .location, .safetyStatus:
            break
        }
    }

    // MARK: - Session and storage

    private func requireClient() throws -> Client {
        guard let client else { throw MatrixAPIError.missingBootstrap }
        return client
    }

    private func requireSessionContext() throws -> MatrixRustSessionContext {
        guard let sessionContext else { throw MatrixAPIError.missingBootstrap }
        return sessionContext
    }

    private func stopSyncService() async {
        syncHandle?.cancel()
        syncHandle = nil
        syncListener = nil
        client = nil
        sessionContext = nil
    }

    private func refreshExistingSession(_ matrixClient: Client, reason: String) async throws {
        try await matrixClient.resume()
        await matrixClient.enableAllSendQueues(enable: true)
        await syncOnceBestEffort(using: matrixClient, timeoutMs: 5_000, fullState: true, reason: reason)
        await joinKnownInvitedRooms(using: matrixClient)
        logger.info("Matrix Rust session refreshed via \(reason, privacy: .public).")
    }

    private func cancelTimelineSubscriptions() {
        timelineSubscriptions.values.forEach { $0.handle.cancel() }
        timelineSubscriptions.removeAll()
    }

    private func matrixStorePassphrase(for subject: String) async throws -> String {
        if let fixedStorePassphrase {
            return fixedStorePassphrase
        }

        let account = "matrix-rust-store.\(Self.sha256Hex(subject))"
        if let existing = try await keychain.loadSymmetricKey(account: account),
           let passphrase = String(data: existing, encoding: .utf8),
           !passphrase.isEmpty {
            return passphrase
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CSMServiceError.unavailable("Nelze vytvorit Matrix store passphrase: \(status).")
        }

        let passphrase = Data(bytes).base64EncodedString()
        try await keychain.saveSymmetricKey(Data(passphrase.utf8), account: account)
        return passphrase
    }

    private static func makeSessionContext(from bootstrap: MessagingBootstrap) throws -> MatrixRustSessionContext {
        guard bootstrap.enabled, bootstrap.chatAvailable, bootstrap.tokenAvailable else {
            throw CSMServiceError.disabled("Matrix bootstrap neni dostupny.")
        }
        guard
            let homeserverURL = bootstrap.homeserverBaseUrl,
            let accessToken = bootstrap.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty,
            let userId = bootstrap.userId?.trimmingCharacters(in: .whitespacesAndNewlines),
            !userId.isEmpty,
            let deviceId = bootstrap.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines),
            !deviceId.isEmpty
        else {
            throw CSMServiceError.invalidState("Matrix bootstrap neobsahuje homeserverBaseUrl, accessToken, userId nebo deviceId.")
        }
        let serverName = bootstrap.serverName
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.serverName(from: userId)
        guard !serverName.isEmpty else {
            throw CSMServiceError.invalidState("Matrix bootstrap neobsahuje serverName.")
        }
        let trimmedRefreshToken = bootstrap.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = trimmedRefreshToken?.isEmpty == true ? nil : trimmedRefreshToken

        return MatrixRustSessionContext(
            homeserverURL: homeserverURL,
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            deviceId: deviceId,
            serverName: serverName,
            e2eeRequired: bootstrap.e2eeRequired
        )
    }

    private static func verifyHomeserverReachable(_ homeserverURL: URL) async throws {
        guard var components = URLComponents(url: homeserverURL, resolvingAgainstBaseURL: false) else {
            throw CSMServiceError.invalidState("Matrix homeserver URL neni platne.")
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, "_matrix/client/versions"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else {
            throw CSMServiceError.invalidState("Matrix homeserver health URL neni platne.")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue(preflightUserAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw CSMServiceError.unavailable("Matrix homeserver neni dostupny pro iOS klienta (HTTP \(status)).")
        }
    }

    private static func matrixStorePaths(
        subject: String,
        fileManager: FileManager
    ) throws -> MatrixRustStorePaths {
        let root = try matrixStoreRoot(subject: subject, fileManager: fileManager)
        let data = root.appendingPathComponent("data", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cache, withIntermediateDirectories: true)

        return MatrixRustStorePaths(dataPath: data.path, cachePath: cache.path)
    }

    private static func matrixStoreRoot(
        subject: String,
        fileManager: FileManager
    ) throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CSMServiceError.unavailable("Application Support adresar neni dostupny.")
        }

        return appSupport
            .appendingPathComponent("CSMMatrixRust", isDirectory: true)
            .appendingPathComponent(sha256Hex(subject), isDirectory: true)
    }

    private static func removeMatrixLocalStore(
        subject: String,
        fileManager: FileManager
    ) throws {
        let root = try matrixStoreRoot(subject: subject, fileManager: fileManager)
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    private static func safeAttachmentFilename(for attachment: MessageAttachment) -> String {
        let rawName = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = rawName.isEmpty ? "attachment" : rawName
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "._- "))
        let sanitized = String(baseName.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("-") })
            .replacingOccurrences(of: " ", with: "_")
        let prefixedName = attachment.kind == .sticker
            ? csmStickerFallbackFilenamePrefix + sanitized
            : sanitized
        if sanitized.contains(".") {
            return prefixedName
        }
        return prefixedName + preferredExtension(for: attachment)
    }

    private static func preferredExtension(for attachment: MessageAttachment) -> String {
        switch attachment.mimeType?.lowercased() {
        case "image/jpeg": return ".jpg"
        case "image/png": return ".png"
        case "image/heic": return ".heic"
        case "video/mp4": return ".mp4"
        case "audio/m4a", "audio/mp4": return ".m4a"
        case "application/pdf": return ".pdf"
        default:
            switch attachment.kind {
            case .image: return ".jpg"
            case .sticker: return ".png"
            case .video: return ".mp4"
            case .voiceNote: return ".m4a"
            case .document: return ".bin"
            case .location, .safetyStatus: return ".txt"
            }
        }
    }

    // MARK: - Mapping

    private static func messages(
        from items: [TimelineItem],
        roomId: String,
        ownUserId: String,
        pinnedEventIds: Set<String>
    ) -> [ChatMessage] {
        let messages = items
            .compactMap { Self.chatMessage(from: $0, roomId: roomId, ownUserId: ownUserId, pinnedEventIds: pinnedEventIds) }
            .sorted {
                $0.sentAt == $1.sentAt ? $0.id < $1.id : $0.sentAt < $1.sentAt
            }
        return ChatMessage.removingSupersededLocalEchoes(from: messages)
    }

    private func mappedMessages(
        from items: [TimelineItem],
        roomId: String,
        ownUserId: String,
        pinnedEventIds: Set<String>
    ) async -> [ChatMessage] {
        var mapped = Self.messages(
            from: items,
            roomId: roomId,
            ownUserId: ownUserId,
            pinnedEventIds: pinnedEventIds
        )
        var avatarURLsBySender: [String: String] = [:]
        for item in items {
            guard let event = item.asEvent(),
                  let avatarURL = Self.avatarURL(from: event.senderProfile) else { continue }
            avatarURLsBySender[event.sender] = avatarURL
        }

        var resolvedBySender: [String: String] = [:]
        for (sender, avatarURL) in avatarURLsBySender {
            if let dataURL = await avatarDataURL(for: avatarURL) {
                resolvedBySender[sender] = dataURL
            }
        }
        for index in mapped.indices {
            mapped[index].senderAvatarUrl = avatarURLsBySender[mapped[index].senderId]
            mapped[index].senderAvatarDataUrl = resolvedBySender[mapped[index].senderId]
        }
        return mapped
    }

    private func avatarDataURL(for rawURL: String?) async -> String? {
        guard let rawURL = Self.nonEmpty(rawURL) else { return nil }
        if let cached = avatarDataURLCache[rawURL] { return cached }
        if unavailableAvatarURLs.contains(rawURL) { return nil }

        do {
            let matrixClient = try requireClient()
            let source = try MediaSource.fromUrl(url: rawURL)
            var data = try await matrixClient.getMediaThumbnail(mediaSource: source, width: 128, height: 128)
            if data.isEmpty {
                data = try await matrixClient.getMediaContent(mediaSource: source)
            }
            guard !data.isEmpty else { throw CSMServiceError.unavailable("Matrix avatar je prazdny.") }
            let mimeType = Self.imageMimeType(for: data)
            let value = "data:\(mimeType);base64,\(data.base64EncodedString())"
            guard value.count <= OperatorProfilePreferences.maxAvatarDataURLLength else {
                throw CSMServiceError.invalidState("Matrix avatar je prilis velky.")
            }
            avatarDataURLCache[rawURL] = value
            return value
        } catch {
            unavailableAvatarURLs.insert(rawURL)
            return nil
        }
    }

    private static func avatarURL(from profile: ProfileDetails) -> String? {
        guard case .ready(_, _, let avatarURL, _, _) = profile else { return nil }
        return nonEmpty(avatarURL)
    }

    private static func imageMimeType(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.count >= 12,
           Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46],
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
            return "image/webp"
        }
        return "image/png"
    }

    private static func avatarUploadPayload(from dataURL: String) throws -> (mimeType: String, data: Data) {
        let trimmed = dataURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= OperatorProfilePreferences.maxAvatarDataURLLength,
              let commaIndex = trimmed.firstIndex(of: ","),
              let data = Data(base64Encoded: String(trimmed[trimmed.index(after: commaIndex)...])),
              !data.isEmpty
        else {
            throw CSMServiceError.invalidState("Avatar skupiny nemá platný obrazový formát.")
        }
        let prefix = String(trimmed[..<commaIndex]).lowercased()
        let mimeType: String
        switch prefix {
        case "data:image/png;base64":
            mimeType = "image/png"
        case "data:image/jpeg;base64":
            mimeType = "image/jpeg"
        case "data:image/webp;base64":
            mimeType = "image/webp"
        default:
            throw CSMServiceError.invalidState("Avatar skupiny musí být PNG, JPEG nebo WebP.")
        }
        return (mimeType, data)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func removingSupersededLocalEchoes(_ messages: [ChatMessage]) -> [ChatMessage] {
        ChatMessage.removingSupersededLocalEchoes(from: messages)
    }

    private static func chatMessage(
        from item: TimelineItem,
        roomId: String,
        ownUserId: String,
        pinnedEventIds: Set<String>
    ) -> ChatMessage? {
        guard let event = item.asEvent() else { return nil }
        let sentAt = Date(timeIntervalSince1970: TimeInterval(event.timestamp) / 1_000.0)
        let id = eventIdString(from: event.eventOrTransactionId, fallback: String(describing: item.uniqueId()))
        let senderId = event.sender
        let senderDisplayName = displayName(from: event.senderProfile, fallback: senderId)
        let isPinned = pinnedEventIds.contains(id)

        guard case .msgLike(let content) = event.content else { return nil }
        let reactions = reactions(from: content.reactions, ownUserId: ownUserId)

        switch content.kind {
        case .message(let message):
            if message.body == liveLocationCompatibilityBody {
                return nil
            }
            return ChatMessage(
                id: id,
                roomId: roomId,
                senderId: senderId,
                senderDisplayName: senderDisplayName,
                body: message.body,
                attachments: attachments(from: message.msgType, body: message.body),
                replyTo: replyReference(from: content.inReplyTo),
                reactions: reactions,
                isPinned: isPinned,
                sentAt: sentAt,
                deliveryState: deliveryState(from: event),
                isOwnMessage: event.isOwn
            )
        case .sticker(let body, let info, _):
            return ChatMessage(
                id: id,
                roomId: roomId,
                senderId: senderId,
                senderDisplayName: senderDisplayName,
                body: body,
                attachments: [
                    MessageAttachment(
                        kind: .sticker,
                        title: body,
                        mimeType: info.mimetype,
                        byteCount: intByteCount(info.size),
                        localOnly: false
                    )
                ],
                reactions: reactions,
                isPinned: isPinned,
                sentAt: sentAt,
                deliveryState: deliveryState(from: event),
                isOwnMessage: event.isOwn
            )
        case .unableToDecrypt:
            return ChatMessage(
                id: id,
                roomId: roomId,
                senderId: senderId,
                senderDisplayName: senderDisplayName,
                body: "Zpravu se nepodarilo desifrovat na tomto zarizeni.",
                reactions: reactions,
                isPinned: isPinned,
                sentAt: sentAt,
                deliveryState: event.isOwn ? .sent : .failed,
                isOwnMessage: event.isOwn
            )
        case .redacted:
            return ChatMessage(
                id: id,
                roomId: roomId,
                senderId: senderId,
                senderDisplayName: senderDisplayName,
                body: "",
                isDeleted: true,
                sentAt: sentAt,
                deliveryState: event.isOwn ? .sent : .read,
                isOwnMessage: event.isOwn
            )
        case .liveLocation(let content):
            let latestLocation = content.locations.last
            let startedAt = Date(timeIntervalSince1970: TimeInterval(content.ts) / 1_000)
            let expiresAt = startedAt.addingTimeInterval(TimeInterval(content.timeoutMs) / 1_000)
            return ChatMessage(
                id: id,
                roomId: roomId,
                senderId: senderId,
                senderDisplayName: senderDisplayName,
                body: content.description ?? "Živá poloha",
                attachments: [
                    MessageAttachment(
                        kind: .location,
                        title: content.description ?? "Živá poloha",
                        durationSeconds: TimeInterval(content.timeoutMs) / 1_000,
                        location: latestLocation.flatMap { geoPoint(from: $0.geoUri) },
                        liveLocationShare: LiveLocationShareMetadata(
                            isLive: content.isLive && expiresAt > .now,
                            startedAt: startedAt,
                            expiresAt: expiresAt,
                            updatedAt: latestLocation.map {
                                Date(timeIntervalSince1970: TimeInterval($0.ts) / 1_000)
                            }
                        ),
                        localOnly: false
                    )
                ],
                reactions: reactions,
                isPinned: isPinned,
                sentAt: sentAt,
                deliveryState: deliveryState(from: event),
                isOwnMessage: event.isOwn
            )
        case .poll, .other:
            return nil
        }
    }

    private static func latestOwnLocalEcho(
        in items: [TimelineItem],
        body: String,
        startedAtMs: UInt64
    ) -> EventTimelineItem? {
        items
            .compactMap { $0.asEvent() }
            .filter { event in
                guard event.isOwn else { return false }
                guard bodyPreview(from: event.content) == body else { return false }

                if let localCreatedAt = event.localCreatedAt {
                    return localCreatedAt + 1_500 >= startedAtMs
                }
                return event.timestamp + 1_500 >= startedAtMs
            }
            .sorted { lhs, rhs in
                (lhs.localCreatedAt ?? lhs.timestamp) < (rhs.localCreatedAt ?? rhs.timestamp)
            }
            .last
    }

    private static func latestOwnRemoteEventId(
        in items: [TimelineItem],
        body: String,
        startedAtMs: UInt64,
        baselineRemoteEventIds: Set<String>
    ) -> String? {
        latestConfirmedOwnEventId(
            in: items,
            body: body,
            startedAtMs: startedAtMs,
            baselineRemoteEventIds: baselineRemoteEventIds
        )
    }

    private static func latestConfirmedOwnEventId(
        in items: [TimelineItem],
        body: String,
        startedAtMs: UInt64,
        baselineRemoteEventIds: Set<String>
    ) -> String? {
        items
            .compactMap { $0.asEvent() }
            .compactMap { event -> (UInt64, String)? in
                guard let eventId = confirmedOwnEventIdAfterSend(
                    from: event,
                    body: body,
                    startedAtMs: startedAtMs,
                    baselineRemoteEventIds: baselineRemoteEventIds
                ) else {
                    return nil
                }
                return (event.localCreatedAt ?? event.timestamp, eventId)
            }
            .sorted { $0.0 < $1.0 }
            .last?
            .1
    }

    private static func remoteEventIds(in items: [TimelineItem]) -> Set<String> {
        Set(
            items
                .compactMap { $0.asEvent() }
                .compactMap(confirmedEventId(from:))
        )
    }

    private static func transactionId(from event: EventTimelineItem) -> String? {
        guard case .transactionId(let transactionId) = event.eventOrTransactionId,
              !transactionId.isEmpty else {
            return nil
        }
        return transactionId
    }

    private static func confirmedEventId(from event: EventTimelineItem) -> String? {
        guard case .eventId(let eventId) = event.eventOrTransactionId,
              !eventId.isEmpty else {
            return nil
        }
        return eventId
    }

    private static func confirmedOwnEventIdAfterSend(
        from event: EventTimelineItem,
        body: String,
        startedAtMs: UInt64,
        baselineRemoteEventIds: Set<String>
    ) -> String? {
        guard event.isOwn,
              let eventId = confirmedEventId(from: event) else {
            return nil
        }
        let eventIsNewInTimeline = !baselineRemoteEventIds.contains(eventId)
        let eventTimeIsPlausible = Self.eventTimestampIsPlausibleAfterSend(event, startedAtMs: startedAtMs)
        guard eventIsNewInTimeline || eventTimeIsPlausible else {
            return nil
        }

        let preview = bodyPreview(from: event.content)
        if preview == body {
            return eventId
        }

        // Matrix Rust can expose the just-accepted encrypted remote echo before
        // the local timeline has decrypted it back into the original plaintext
        // body. At this point Synapse has already returned a server event id, so
        // keeping a crisis message as local `pending` is misleading. Restrict
        // this weak confirmation to own, fresh, server-backed echoes only.
        if event.isRemote, isUndecryptedOwnEchoPreview(preview), eventIsNewInTimeline {
            return eventId
        }

        return nil
    }

    private static func eventTimestampIsPlausibleAfterSend(
        _ event: EventTimelineItem,
        startedAtMs: UInt64
    ) -> Bool {
        // Prefer the local echo timestamp when the SDK exposes one. Server event
        // timestamps are generated by Synapse and can be hours behind a phone
        // whose local clock is wrong; using the baseline event-id set above is
        // the primary skew-safe confirmation path.
        let observedAtMs = event.localCreatedAt ?? event.timestamp
        return observedAtMs + 1_500 >= startedAtMs
    }

    private static func isUndecryptedOwnEchoPreview(_ preview: String) -> Bool {
        preview == "Sifrovana zprava" || preview == "Zprava"
    }

    private static func queueWedgeDescription(_ error: QueueWedgeError, recoverable: Bool) -> String {
        let recoveryText = recoverable ? "recoverable" : "manual"
        switch error {
        case .insecureDevices(let userDeviceMap):
            let deviceCount = userDeviceMap.values.reduce(0) { $0 + $1.count }
            return "untrusted Matrix devices (\(userDeviceMap.count) users, \(deviceCount) devices, \(recoveryText))"
        case .identityViolations(let users):
            return "Matrix identity violation (\(users.count) users, \(recoveryText))"
        case .crossVerificationRequired:
            return "cross verification required (\(recoveryText))"
        case .missingMediaContent:
            return "missing media content (\(recoveryText))"
        case .invalidMimeType(let mimeType):
            return "invalid MIME type \(mimeType) (\(recoveryText))"
        case .genericApiError(let msg):
            return "\(msg) (\(recoveryText))"
        }
    }

    private static func attachments(from type: MessageType, body: String) -> [MessageAttachment] {
        switch type {
        case .image(let content):
            let kind: MessageAttachmentKind = isCSMStickerFallbackImage(
                filename: content.filename,
                caption: content.caption,
                mimeType: content.info?.mimetype
            ) ? .sticker : .image
            return [
                MessageAttachment(
                    kind: kind,
                    title: content.caption ?? content.filename,
                    mimeType: content.info?.mimetype,
                    byteCount: intByteCount(content.info?.size),
                    localOnly: false
                )
            ]
        case .video(let content):
            return [
                MessageAttachment(
                    kind: .video,
                    title: content.caption ?? content.filename,
                    mimeType: content.info?.mimetype,
                    byteCount: intByteCount(content.info?.size),
                    durationSeconds: content.info?.duration,
                    localOnly: false
                )
            ]
        case .audio(let content):
            return [
                MessageAttachment(
                    kind: .voiceNote,
                    title: content.caption ?? content.filename,
                    mimeType: content.info?.mimetype,
                    byteCount: intByteCount(content.info?.size),
                    durationSeconds: content.info?.duration,
                    localOnly: false
                )
            ]
        case .file(let content):
            return [
                MessageAttachment(
                    kind: .document,
                    title: content.caption ?? content.filename,
                    mimeType: content.info?.mimetype,
                    byteCount: intByteCount(content.info?.size),
                    localOnly: false
                )
            ]
        case .location(let content):
            return [
                MessageAttachment(
                    kind: .location,
                    title: content.description ?? body,
                    location: geoPoint(from: content.geoUri),
                    localOnly: false
                )
            ]
        case .emote, .gallery, .notice, .text, .other:
            return []
        }
    }

    static func isCSMStickerFallbackImage(filename: String, caption: String?, mimeType: String?) -> Bool {
        let normalizedFilename = (filename as NSString)
            .lastPathComponent
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard normalizedFilename.contains(csmStickerFallbackFilenamePrefix) else {
            return false
        }
        let normalizedMimeType = mimeType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard normalizedMimeType == nil || normalizedMimeType == "image/png" else {
            return false
        }
        return caption?.isEmpty == false || normalizedFilename.hasSuffix(".png")
    }

    private static func replyReference(from details: InReplyToDetails?) -> MessageReplyReference? {
        guard let details else { return nil }
        let eventId = details.eventId()
        switch details.event() {
        case .ready(let content, let sender, let senderProfile, _, _):
            let body = bodyPreview(from: content)
            return MessageReplyReference(
                messageId: eventId,
                senderDisplayName: displayName(from: senderProfile, fallback: sender),
                bodyPreview: body
            )
        case .unavailable, .pending, .error:
            return MessageReplyReference(
                messageId: eventId,
                senderDisplayName: "Matrix",
                bodyPreview: "Zprava"
            )
        }
    }

    private static func deliveryState(from event: EventTimelineItem) -> MessageDeliveryState {
        guard let localState = event.localSendState else {
            return event.isOwn ? .sent : .read
        }

        switch localState {
        case .notSentYet(progress: _):
            return .pending
        case .sent(eventId: _):
            return .sent
        case .sendingFailed(error: _, isRecoverable: _):
            return .failed
        }
    }

    private static func reactions(from sdkReactions: [Reaction], ownUserId: String) -> [MessageReaction] {
        sdkReactions.map { reaction in
            MessageReaction(
                emoji: reaction.key,
                count: reaction.senders.count,
                reactedByMe: reaction.senders.contains { $0.senderId == ownUserId },
                ownEventId: nil
            )
        }
    }

    private static func bodyPreview(from content: TimelineItemContent) -> String {
        guard case .msgLike(let messageLike) = content else { return "Zprava" }
        switch messageLike.kind {
        case .message(let message):
            return message.body
        case .sticker(let body, _, _):
            return body
        case .unableToDecrypt:
            return "Sifrovana zprava"
        case .redacted:
            return "Smazana zprava"
        case .poll(let question, _, _, _, _, _, _):
            return question
        case .liveLocation(let content):
            return content.description ?? "Živá poloha"
        case .other:
            return "Zprava"
        }
    }

    private static func eventIdString(from value: EventOrTransactionId, fallback: String) -> String {
        switch value {
        case .eventId(let eventId):
            return eventId
        case .transactionId(let transactionId):
            return transactionId.isEmpty ? fallback : transactionId
        }
    }

    private static func unconfirmedEventId(transactionId: String?) -> String {
        let safeTransactionId = transactionId?
            .filter { character in
                character.isLetter || character.isNumber || character == "-" || character == "_"
            }
            .prefix(48)

        if let safeTransactionId, !safeTransactionId.isEmpty {
            return "matrix-unconfirmed-\(safeTransactionId)"
        }
        return "matrix-unconfirmed-\(UUID().uuidString)"
    }

    private static func eventOrTransactionId(for messageId: String) -> EventOrTransactionId {
        messageId.hasPrefix("$") ? .eventId(eventId: messageId) : .transactionId(transactionId: messageId)
    }

    private static func displayName(from profile: ProfileDetails, fallback userId: String) -> String {
        if case .ready(let displayName, _, _, _, _) = profile,
           let displayName,
           !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return displayName
        }
        return matrixDisplayName(userId)
    }

    private static func matrixDisplayName(_ matrixUserId: String) -> String {
        guard matrixUserId.hasPrefix("@") else { return matrixUserId }
        let localpart = String(matrixUserId.dropFirst().split(separator: ":").first ?? Substring(matrixUserId))
        return localpart.hasPrefix("cop_") ? String(localpart.dropFirst(4)) : localpart
    }

    private static func geoPoint(from geoURI: String) -> GeoPoint? {
        guard geoURI.lowercased().hasPrefix("geo:") else { return nil }
        let value = geoURI.dropFirst(4).split(separator: "?").first.map(String.init) ?? ""
        let coordinateAndParameters = value.split(separator: ";", omittingEmptySubsequences: true)
        let coordinates = coordinateAndParameters.first?.split(separator: ",") ?? []
        guard coordinates.count >= 2,
              let lat = Double(coordinates[0]),
              let lon = Double(coordinates[1]) else {
            return nil
        }
        let accuracy = coordinateAndParameters
            .dropFirst()
            .first { $0.lowercased().hasPrefix("u=") }
            .flatMap { Double($0.dropFirst(2)) }
        return GeoPoint(lat: lat, lon: lon, accuracyM: accuracy, source: "matrix.geo")
    }

    private static func intByteCount(_ value: UInt64?) -> Int? {
        value.map { Int(min($0, UInt64(Int.max))) }
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func currentUnixMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000)
    }

    private static func matrixEncryptionRecoveryStatus(
        backupState: BackupState,
        recoveryState: RecoveryState,
        backupExistsResult: Result<Bool, any Error>
    ) -> MatrixEncryptionRecoveryStatus {
        let keyBackupEnabled = backupState.isEnabledForRecovery
        let recoveryEnabled = recoveryState == .enabled
        let backupExists: Bool
        let detail: String?
        switch backupExistsResult {
        case .success(let exists):
            backupExists = exists || keyBackupEnabled
            detail = nil
        case .failure(let error):
            backupExists = keyBackupEnabled
            detail = "Matrix backup status check failed: \(error.localizedDescription)"
        }

        let ready = keyBackupEnabled
        return MatrixEncryptionRecoveryStatus(
            supported: true,
            keyBackupExists: backupExists,
            keyBackupEnabled: keyBackupEnabled,
            recoveryEnabled: recoveryEnabled,
            keyBackupUsable: keyBackupEnabled,
            matrixRustCompatible: recoveryEnabled,
            needsSetup: !backupExists,
            needsRecovery: backupExists && !keyBackupEnabled,
            ready: ready,
            backupState: backupState.csmName,
            recoveryState: recoveryState.csmName,
            detail: detail
        )
    }

    static func recoveryKeyCandidates(from rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let grouped = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .joined(separator: " ")
        let compact = rawValue.filter { !$0.isWhitespace }

        var seen = Set<String>()
        return [trimmed, grouped, compact]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                guard !seen.contains(value) else { return false }
                seen.insert(value)
                return true
            }
    }

    static func shouldRetryCleanRecoveryCreation(
        reset: Bool,
        status: MatrixEncryptionRecoveryStatus
    ) -> Bool {
        !reset &&
            status.supported &&
            !status.keyBackupExists &&
            !status.keyBackupEnabled
    }

    static func shouldDeleteServerBackupBeforeCleanRecovery(
        reset: Bool,
        status: MatrixEncryptionRecoveryStatus
    ) -> Bool {
        reset &&
            status.supported &&
            status.keyBackupExists &&
            !status.keyBackupEnabled
    }

    private static func isBackupExistsOnServerError(_ error: any Error) -> Bool {
        let text = "\(error.localizedDescription)\n\(String(reflecting: error))".lowercased()
        return text.contains("backupexistsonserver") ||
            text.contains("backup exists on server")
    }

    private static func matrixClientURL(homeserver: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: homeserver, resolvingAgainstBaseURL: false) else {
            throw CSMServiceError.invalidState("Matrix homeserver URL neni platne.")
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedQuery = nil
        guard let url = components.url else {
            throw CSMServiceError.invalidState("Matrix API URL neni platne.")
        }
        return url
    }

    private static func authorizedMatrixRequest(
        url: URL,
        method: String,
        context: MatrixRustSessionContext
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(context.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func percentEncodedMatrixPathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func matrixKeyBackupHTTPError(
        data: Data,
        response: HTTPURLResponse,
        operation: String
    ) -> CSMServiceError {
        let payload = try? JSONDecoder().decode(MatrixErrorResponse.self, from: data)
        let message = [payload?.errcode, payload?.error]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")
        let suffix = message.isEmpty ? "" : " \(message)"
        return .unavailable("Matrix key-backup \(operation) returned HTTP \(response.statusCode).\(suffix)")
    }

    private static func recoveryCreationUserFacingError(technicalDetail: String) -> MatrixEncryptionRecoveryUserFacingError {
        MatrixEncryptionRecoveryUserFacingError(
            reason: .generic,
            userMessage: CSMLocalization.text(
                "matrix.recovery.create_failed.actionable",
                fallback: "Nový E2EE obnovovací klíč se nepodařilo vytvořit. Zkuste to znovu po synchronizaci, případně použijte přihlášení a párování z webové aplikace COP."
            ),
            technicalDetail: technicalDetail
        )
    }

    private static func preferredRecoveryError(
        firstError: (any Error)?,
        lastError: (any Error)?
    ) -> any Error {
        let candidate = [firstError, lastError]
            .compactMap { $0 }
            .first { Self.isWebSecretStorageCompatibilityError($0) } ?? lastError ?? firstError

        guard let candidate else {
            return CSMServiceError.unavailable(CSMLocalization.text("matrix.recovery.restore_failed.generic", fallback: "Zařízení se nepodařilo obnovit."))
        }

        if Self.isWebSecretStorageCompatibilityError(candidate) {
            return webSecretStorageCompatibilityError(technicalDetail: candidate.localizedDescription)
        }

        return candidate
    }

    private static func userFacingRecoveryError(from error: any Error) -> any Error {
        if let userFacingError = error as? MatrixEncryptionRecoveryUserFacingError {
            return userFacingError
        }
        if isWebSecretStorageCompatibilityError(error) {
            return webSecretStorageCompatibilityError(technicalDetail: error.localizedDescription)
        }
        return error
    }

    private static func webSecretStorageCompatibilityError(technicalDetail: String) -> MatrixEncryptionRecoveryUserFacingError {
        MatrixEncryptionRecoveryUserFacingError(
            reason: .webSecretStorageCompatibility,
            userMessage: CSMLocalization.text(
                "matrix.recovery.web_metadata_error",
                fallback: "Obnovovací klíč je platný, ale starší webová cross-signing metadata blokují iOS Matrix SDK. V COP webu připravte nový recovery cyklus pro iPhone/iPad, bezpečně uložte nový klíč a potom ho zadejte zde."
            ),
            technicalDetail: technicalDetail
        )
    }

    static func isWebSecretStorageCompatibilityError(_ error: any Error) -> Bool {
        if let recoveryError = error as? RecoveryError {
            switch recoveryError {
            case .Import(let errorMessage):
                if isCrossSigningSecretImportError(errorMessage) {
                    return true
                }
            case .BackupExistsOnServer, .Client, .SecretStorage:
                break
            }
        }

        let text = "\(error.localizedDescription)\n\(String(reflecting: error))".lowercased()
        return isCrossSigningSecretImportError(text)
    }

    private static func isCrossSigningSecretImportError(_ value: String) -> Bool {
        let text = value.lowercased()
        let identifiesCrossSigning = text.contains("m.cross_signing") ||
            text.contains("cross-signing") ||
            text.contains("cross signing")
        let identifiesImportFailure = text.contains("import") ||
            text.contains("missing field") ||
            text.contains("deserialize") ||
            text.contains("decrypt") ||
            text.contains("encrypted") ||
            text.contains("secret")
        return identifiesCrossSigning && identifiesImportFailure
    }

    private static func isWebSecretStorageRetryCandidate(_ error: any Error) -> Bool {
        if let recoveryError = error as? MatrixEncryptionRecoveryUserFacingError {
            return recoveryError.reason == .webSecretStorageCompatibility
        }
        return isWebSecretStorageCompatibilityError(error)
    }

    private static func serverName(from matrixUserId: String) -> String {
        matrixUserId.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }

}

private struct MatrixRustSessionContext {
    var homeserverURL: URL
    var accessToken: String
    var refreshToken: String?
    var userId: String
    var deviceId: String
    var serverName: String
    var e2eeRequired: Bool

    var storeSubject: String {
        "\(homeserverURL.absoluteString)|\(userId)|\(deviceId)"
    }

    var safeUserId: String {
        let digest = SHA256.hash(data: Data(userId.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    func isEquivalent(to other: MatrixRustSessionContext) -> Bool {
        homeserverURL == other.homeserverURL &&
            accessToken == other.accessToken &&
            refreshToken == other.refreshToken &&
            userId == other.userId &&
            deviceId == other.deviceId &&
            serverName == other.serverName &&
            e2eeRequired == other.e2eeRequired
    }
}

private struct MatrixRustStorePaths {
    var dataPath: String
    var cachePath: String
}

private struct MatrixRustTimelineSubscription {
    var timeline: Timeline
    var listener: MatrixRustTimelineCache
    var handle: TaskHandle
}

private struct MatrixRustQueuedSendFailure {
    var error: QueueWedgeError
    var isRecoverable: Bool
}

private struct MatrixKeyBackupVersionResponse: Decodable {
    var version: String?
}

private final class MatrixRustEnableRecoveryProgressListener: EnableRecoveryProgressListener, @unchecked Sendable {
    func onUpdate(status: EnableRecoveryProgress) {
        _ = status
    }
}

private extension BackupState {
    var isEnabledForRecovery: Bool {
        switch self {
        case .enabled, .downloading, .resuming:
            return true
        case .unknown, .creating, .enabling, .disabling:
            return false
        }
    }

    var csmName: String {
        switch self {
        case .unknown: return "unknown"
        case .creating: return "creating"
        case .enabling: return "enabling"
        case .resuming: return "resuming"
        case .enabled: return "enabled"
        case .downloading: return "downloading"
        case .disabling: return "disabling"
        }
    }
}

private extension RecoveryState {
    var csmName: String {
        switch self {
        case .unknown: return "unknown"
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .incomplete: return "incomplete"
        }
    }
}

private final class MatrixRustSendQueueTracker: SendQueueListener, SendQueueRoomUpdateListener, @unchecked Sendable {
    private let lock = NSLock()
    private let roomId: String?
    private var updates: [RoomSendQueueUpdate] = []

    init(roomId: String? = nil) {
        self.roomId = roomId
    }

    func onUpdate(update: RoomSendQueueUpdate) {
        lock.lock()
        updates.append(update)
        lock.unlock()
    }

    func onUpdate(roomId: String, update: RoomSendQueueUpdate) {
        guard self.roomId == nil || self.roomId == roomId else { return }
        onUpdate(update: update)
    }

    func snapshotTransactionIds() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(updates.compactMap(Self.transactionId(from:)))
    }

    func singleNewTransactionId(excluding baseline: Set<String>) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let candidates = orderedNewLocalTransactionIds(excluding: baseline)
        return candidates.count == 1 ? candidates[0] : nil
    }

    func sentEventId(for transactionId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return updates.reversed().compactMap { update -> String? in
            guard case .sentEvent(let currentTransactionId, let eventId) = update,
                  currentTransactionId == transactionId else {
                return nil
            }
            return eventId
        }.first
    }

    func singleNewSentEventId(excluding baseline: Set<String>) -> String? {
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        var eventIds: [String] = []
        for update in updates {
            guard case .sentEvent(let transactionId, let eventId) = update,
                  !transactionId.isEmpty,
                  !eventId.isEmpty,
                  !baseline.contains(transactionId),
                  seen.insert(transactionId).inserted else {
                continue
            }
            eventIds.append(eventId)
        }
        return eventIds.count == 1 ? eventIds[0] : nil
    }

    func failure(for transactionId: String) -> MatrixRustQueuedSendFailure? {
        lock.lock()
        defer { lock.unlock() }
        return updates.reversed().compactMap { update -> MatrixRustQueuedSendFailure? in
            guard case .sendError(let currentTransactionId, let error, let isRecoverable) = update,
                  currentTransactionId == transactionId else {
                return nil
            }
            return MatrixRustQueuedSendFailure(error: error, isRecoverable: isRecoverable)
        }.first
    }

    private func orderedNewLocalTransactionIds(excluding baseline: Set<String>) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for update in updates {
            guard case .newLocalEvent(let transactionId) = update,
                  !transactionId.isEmpty,
                  !baseline.contains(transactionId),
                  seen.insert(transactionId).inserted else {
                continue
            }
            ordered.append(transactionId)
        }
        return ordered
    }

    private static func transactionId(from update: RoomSendQueueUpdate) -> String? {
        switch update {
        case .newLocalEvent(let transactionId),
             .cancelledLocalEvent(let transactionId),
             .replacedLocalEvent(let transactionId),
             .sendError(let transactionId, _, _),
             .retryEvent(let transactionId),
             .sentEvent(let transactionId, _):
            return transactionId.isEmpty ? nil : transactionId
        case .mediaUpload(let relatedTo, _, _, _):
            return relatedTo.isEmpty ? nil : relatedTo
        }
    }
}

private final class MatrixRustSendQueueErrorTracker: SendQueueRoomErrorListener, @unchecked Sendable {
    private let lock = NSLock()
    private let roomId: String
    private var errors: [String] = []

    init(roomId: String) {
        self.roomId = roomId
    }

    func onError(roomId: String, error: ClientError) {
        guard roomId == self.roomId else { return }
        lock.lock()
        errors.append(String(describing: error))
        lock.unlock()
    }

    func latestErrorDescription() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return errors.last
    }
}

private final class MatrixRustTimelineCache: TimelineListener, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [TimelineItem] = []
    private var observers: [UUID: @Sendable ([TimelineItem]) -> Void] = [:]

    func onUpdate(diff: [TimelineDiff]) {
        let snapshot: [TimelineItem]
        let callbacks: [@Sendable ([TimelineItem]) -> Void]
        lock.lock()
        for update in diff {
            apply(update)
        }
        snapshot = items
        callbacks = Array(observers.values)
        lock.unlock()

        for callback in callbacks {
            callback(snapshot)
        }
    }

    func snapshot() -> [TimelineItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func addObserver(_ observer: @escaping @Sendable ([TimelineItem]) -> Void) -> UUID {
        let id = UUID()
        let snapshot: [TimelineItem]
        lock.lock()
        observers[id] = observer
        snapshot = items
        lock.unlock()
        observer(snapshot)
        return id
    }

    func removeObserver(id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }

    private func apply(_ update: TimelineDiff) {
        switch update {
        case .append(let values):
            items.append(contentsOf: values)
        case .clear:
            items.removeAll()
        case .insert(let rawIndex, let item):
            let index = Int(rawIndex)
            if index <= items.count {
                items.insert(item, at: index)
            }
        case .set(let rawIndex, let item):
            let index = Int(rawIndex)
            if index < items.count {
                items[index] = item
            }
        case .remove(let rawIndex):
            let index = Int(rawIndex)
            if index < items.count {
                items.remove(at: index)
            }
        case .pushBack(let item):
            items.append(item)
        case .pushFront(let item):
            items.insert(item, at: 0)
        case .popBack:
            if !items.isEmpty {
                items.removeLast()
            }
        case .popFront:
            if !items.isEmpty {
                items.removeFirst()
            }
        case .truncate(let rawLength):
            let length = Int(rawLength)
            if length < items.count {
                items = Array(items.prefix(length))
            }
        case .reset(let values):
            items = values
        }
    }
}

private final class MatrixRustSyncListener: SyncListenerV2, @unchecked Sendable {
    func onUpdate(response: SyncResponseV2) {
        _ = response
    }
}
#endif
