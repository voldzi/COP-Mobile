import Foundation

actor OfflineFirstMessagingClient: MessagingClientProtocol, MessagingClientDiagnostics, MessagingLiveMessageStreaming, MessagingLiveLocationSharing, MessagingHistoryPaging, MessagingCachedSnapshotLoading, MessagingConversationPresentationEnriching, MessagingConversationAvatarUpdating, MatrixEncryptionRecoveryManaging {
    private let liveClient: any MessagingClientProtocol
    private let outbox: any MessageOutboxStoring
    private let outboxActor: OutboxActor
    private let history: (any MessageHistoryStoring)?
    private var isConfigured = false
    private var liveClientReady = false
    private var lastBootstrap: MessagingBootstrap?
    private var lastTransportError: String?

    init(
        liveClient: any MessagingClientProtocol,
        outbox: any MessageOutboxStoring,
        history: (any MessageHistoryStoring)? = nil
    ) {
        self.liveClient = liveClient
        self.outbox = outbox
        self.outboxActor = OutboxActor(store: outbox)
        self.history = history
    }

    func configure(with bootstrap: MessagingBootstrap) async throws {
        guard bootstrap.enabled else {
            isConfigured = false
            liveClientReady = false
            throw CSMServiceError.disabled("Messaging is disabled by policy.")
        }

        let previousBootstrap = lastBootstrap
        let hadReadyLiveClient = liveClientReady
        isConfigured = true
        lastBootstrap = bootstrap
        do {
            try await liveClient.configure(with: bootstrap)
            liveClientReady = true
            lastTransportError = nil
        } catch {
            lastTransportError = error.localizedDescription
            if Self.canKeepExistingLiveReceiveSession(
                after: error,
                previousBootstrap: previousBootstrap,
                bootstrap: bootstrap,
                hadReadyLiveClient: hadReadyLiveClient
            ) {
                liveClientReady = true
                return
            }
            liveClientReady = false
            if bootstrap.e2eeRequired {
                throw error
            }
        }
    }

    func messages(for conversation: Conversation) async throws -> [ChatMessage] {
        let cachedMessages = try await history?.messages(for: conversation.conversationId) ?? []
        guard isConfigured else {
            let pending = try await outbox.pendingMessages(for: conversation.conversationId)
            return merge(liveMessages: cachedMessages, pendingMessages: pending)
        }

        if !liveClientReady {
            try? await restoreLiveClientIfPossible()
        }

        var liveMessages = cachedMessages
        if liveClientReady {
            do {
                liveMessages = try await liveClient.messages(for: conversation)
                var reconciliation = try await removePendingMessagesAlreadyConfirmedByMatrix(
                    liveMessages: liveMessages,
                    conversation: conversation
                )
                liveMessages = reconciliation.messages
                if reconciliation.removedCount == 0 {
                    _ = try await synchronizePendingMessages(for: conversation, force: false)
                    liveMessages = try await liveClient.messages(for: conversation)
                    reconciliation = try await removePendingMessagesAlreadyConfirmedByMatrix(
                        liveMessages: liveMessages,
                        conversation: conversation
                    )
                    liveMessages = reconciliation.messages
                }
                liveMessages = mergeHistory(cachedMessages: cachedMessages, liveMessages: liveMessages)
                try await history?.saveMessages(liveMessages, conversationId: conversation.conversationId)
                lastTransportError = nil
            } catch {
                liveClientReady = false
                lastTransportError = error.localizedDescription
            }
        }

        let pending = try await outbox.pendingMessages(for: conversation.conversationId)
        return merge(liveMessages: liveMessages, pendingMessages: pending)
    }

    func messageSnapshots(for conversation: Conversation) async throws -> AsyncStream<[ChatMessage]> {
        guard isConfigured else {
            return Self.singleSnapshotStream(try await messages(for: conversation))
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                var reconnectAttempt = 0
                while !Task.isCancelled {
                    do {
                        guard let liveStream = try await self.liveMessageStream(for: conversation) else {
                            continuation.yield(try await self.messages(for: conversation))
                            continuation.finish()
                            return
                        }

                        reconnectAttempt = 0
                        for await liveMessages in liveStream {
                            guard !Task.isCancelled else { return }
                            let visibleMessages = try await self.visibleMessages(
                                liveMessages: liveMessages,
                                conversation: conversation
                            )
                            continuation.yield(visibleMessages)
                        }

                        guard !Task.isCancelled else { return }
                        self.recordLiveStreamEnded()
                        if let fallbackMessages = try? await self.messages(for: conversation) {
                            continuation.yield(fallbackMessages)
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.recordLiveStreamFailure(error)
                        if let fallbackMessages = try? await self.messages(for: conversation) {
                            continuation.yield(fallbackMessages)
                        }
                    }

                    reconnectAttempt += 1
                    let delay = Self.liveStreamReconnectDelayNanoseconds(attempt: reconnectAttempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func hasEarlierMessages(for conversation: Conversation) async -> Bool {
        if let paging = liveClient as? any MessagingHistoryPaging,
           await paging.hasEarlierMessages(for: conversation) {
            return true
        }
        guard let history else { return false }
        return (try? await history.messagePage(
            for: conversation.conversationId,
            before: nil,
            limit: TimelineWindowPolicy.mobile.initialMessageLimit
        ).hasEarlier) ?? false
    }

    func cachedMessagePage(
        for conversation: Conversation,
        limit: Int
    ) async throws -> MessageHistoryPage {
        let cached = if let history {
            try await history.messagePage(
                for: conversation.conversationId,
                before: nil,
                limit: limit
            )
        } else {
            MessageHistoryPage(messages: [], hasEarlier: false)
        }
        let pending = try await outbox.pendingMessages(for: conversation.conversationId)
        return MessageHistoryPage(
            messages: merge(
                liveMessages: cached.messages,
                pendingMessages: pending
            ),
            hasEarlier: cached.hasEarlier
        )
    }

    func loadEarlierMessages(
        for conversation: Conversation,
        limit: Int
    ) async throws -> MessageHistoryPage {
        if !liveClientReady {
            try? await restoreLiveClientIfPossible()
        }
        if liveClientReady,
           let paging = liveClient as? any MessagingHistoryPaging {
            let page = try await paging.loadEarlierMessages(for: conversation, limit: limit)
            if !page.messages.isEmpty {
                try await history?.saveMessages(
                    page.messages,
                    conversationId: conversation.conversationId
                )
            }
            return page
        }
        guard let history else {
            return MessageHistoryPage(messages: [], hasEarlier: false)
        }
        let cached = try await history.messagePage(
            for: conversation.conversationId,
            before: nil,
            limit: limit
        )
        return cached
    }

    func enrichedConversationPresentation(_ conversation: Conversation) async -> Conversation {
        guard liveClientReady,
              let enricher = liveClient as? any MessagingConversationPresentationEnriching else {
            return conversation
        }
        return await enricher.enrichedConversationPresentation(conversation)
    }

    func updateGroupConversationAvatar(
        _ avatarDataUrl: String?,
        for conversation: Conversation
    ) async throws -> Conversation {
        guard liveClientReady,
              let updater = liveClient as? any MessagingConversationAvatarUpdating else {
            throw CSMServiceError.unavailable("Matrix není připraven pro změnu avataru skupiny.")
        }
        return try await updater.updateGroupConversationAvatar(avatarDataUrl, for: conversation)
    }

    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage {
        try await sendMessage(OutgoingMessageDraft(body: body), to: conversation)
    }

    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        guard isConfigured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        guard !draft.isEmpty else {
            throw CSMServiceError.invalidState("Message draft is empty.")
        }
        if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
            throw CSMServiceError.invalidState(validationError)
        }

        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }

        guard liveClientReady else {
            let reason = lastTransportError ?? "Matrix E2EE klient zatim neni pripraven."
            throw CSMServiceError.unavailable(reason)
        }

        let attemptedAt = Date()
        do {
            let sent = try await liveClient.sendMessage(draft, to: conversation)
            try await history?.appendMessage(sent, conversationId: conversation.conversationId)
            lastTransportError = nil
            return sent
        } catch {
            if Self.sendFailureMayHaveReachedMatrix(error),
               let confirmed = try? await latestConfirmedLiveMessage(
                for: draft,
                conversation: conversation,
                attemptedAt: attemptedAt
               ) {
                let message = Self.confirmedMessage(
                    from: draft,
                    conversation: conversation,
                    matchedLiveMessage: confirmed
                )
                try await history?.appendMessage(message, conversationId: conversation.conversationId)
                lastTransportError = nil
                return message
            }

            lastTransportError = error.localizedDescription
            guard shouldQueueAfterLiveFailure(error) else {
                liveClientReady = false
                throw error
            }
            preserveIncomingSessionIfPossible(afterSendFailure: error)
            let pending = makePendingMessage(draft, conversation: conversation)
            _ = try await outboxActor.enqueue(
                pending,
                conversation: conversation,
                transactionID: pending.id
            )
            try await outbox.recordAttempt(
                messageId: pending.id,
                conversationId: conversation.conversationId,
                error: error.localizedDescription,
                retryAfter: retryDelay(attempt: 1)
            )
            return pending
        }
    }

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {
        await liveClient.registerPusher(pushKey: pushKey, pushGatewayURL: pushGatewayURL)
    }

    func startLiveLocationShare(
        durationSeconds: TimeInterval,
        in conversation: Conversation
    ) async throws {
        let client = try await liveLocationClient()
        try await client.startLiveLocationShare(
            durationSeconds: durationSeconds,
            in: conversation
        )
    }

    func updateLiveLocation(
        _ location: GeoPoint,
        in conversation: Conversation
    ) async throws {
        let client = try await liveLocationClient()
        try await client.updateLiveLocation(location, in: conversation)
    }

    func stopLiveLocationShare(in conversation: Conversation) async throws {
        let client = try await liveLocationClient()
        try await client.stopLiveLocationShare(in: conversation)
    }

    private func liveLocationClient() async throws -> any MessagingLiveLocationSharing {
        guard isConfigured else {
            throw CSMServiceError.invalidState("Chat není připravený.")
        }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        guard liveClientReady,
              let client = liveClient as? any MessagingLiveLocationSharing else {
            throw CSMServiceError.unavailable("Živá poloha teď není dostupná.")
        }
        return client
    }

    func encryptionRecoveryStatus() async -> MatrixEncryptionRecoveryStatus {
        guard let recovery = liveClient as? any MatrixEncryptionRecoveryManaging else {
            return .unsupported("The active messaging client does not expose Matrix encryption recovery.")
        }

        if !liveClientReady {
            try? await restoreLiveClientIfPossible()
        }

        guard liveClientReady else {
            return .unavailable(lastTransportError ?? "Matrix E2EE client is not ready.")
        }

        return await recovery.encryptionRecoveryStatus()
    }

    func createEncryptionRecovery(reset: Bool) async throws -> String {
        guard let recovery = liveClient as? any MatrixEncryptionRecoveryManaging else {
            throw CSMServiceError.unavailable(CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu."))
        }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        return try await recovery.createEncryptionRecovery(reset: reset)
    }

    func resetEncryptionRecovery(oldRecoveryKey: String) async throws -> String {
        guard let recovery = liveClient as? any MatrixEncryptionRecoveryManaging else {
            throw CSMServiceError.unavailable(CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu."))
        }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        return try await recovery.resetEncryptionRecovery(oldRecoveryKey: oldRecoveryKey)
    }

    func restoreEncryptionRecovery(recoveryKey: String) async throws {
        guard let recovery = liveClient as? any MatrixEncryptionRecoveryManaging else {
            throw CSMServiceError.unavailable(CSMLocalization.text("matrix.recovery.unsupported_client", fallback: "Aktivní chatový klient nepodporuje E2EE obnovu."))
        }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        try await recovery.restoreEncryptionRecovery(recoveryKey: recoveryKey)
    }

    func latestTransportError(for conversation: Conversation?) async -> String? {
        if let conversation,
           let recordError = try? await outbox.pendingRecords(for: conversation.conversationId)
            .last(where: { $0.lastError?.isEmpty == false })?
            .lastError {
            return recordError
        }
        return lastTransportError
    }

    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        if isConfigured, liveClientReady {
            do {
                let updated = try await liveClient.toggleReaction(emoji, on: message, in: conversation)
                try await persistUpdatedMessage(updated, conversation: conversation)
                return updated
            } catch {
                liveClientReady = false
            }
        }

        let updated = message.applyingReactionToggle(emoji)
        try await persistUpdatedMessage(updated, conversation: conversation)
        return updated
    }

    func redactMessage(_ message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        if isConfigured, liveClientReady {
            do {
                let updated = try await liveClient.redactMessage(message, in: conversation)
                try await persistUpdatedMessage(updated, conversation: conversation)
                return updated
            } catch {
                liveClientReady = false
                throw error
            }
        }

        if message.deliveryState == .pending {
            try await outbox.removeMessage(id: message.id, conversationId: conversation.conversationId)
            let updated = message.markedDeleted()
            try await persistUpdatedMessage(updated, conversation: conversation)
            return updated
        }

        throw CSMServiceError.unavailable("Smazani pro vsechny vyzaduje dostupny sifrovany Matrix kanal.")
    }

    func setMessagePinned(_ pinned: Bool, message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        if isConfigured, liveClientReady {
            do {
                let updated = try await liveClient.setMessagePinned(pinned, message: message, in: conversation)
                try await persistUpdatedMessage(updated, conversation: conversation)
                return updated
            } catch {
                liveClientReady = false
                throw error
            }
        }

        throw CSMServiceError.unavailable("Pripnuti zpravy vyzaduje dostupny sifrovany Matrix kanal.")
    }

    func leaveConversation(_ conversation: Conversation) async throws {
        guard conversation.type == .group else {
            throw CSMServiceError.invalidState("Opustit lze jen skupinovou konverzaci.")
        }
        guard conversation.activeMatrixRoomId != nil else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }
        guard isConfigured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        guard liveClientReady else {
            throw CSMServiceError.unavailable(lastTransportError ?? "Matrix E2EE klient zatim neni pripraven.")
        }

        do {
            try await liveClient.leaveConversation(conversation)
            try await history?.removeMessages(for: conversation.conversationId)
            lastTransportError = nil
        } catch {
            liveClientReady = false
            lastTransportError = error.localizedDescription
            throw error
        }
    }

    func synchronizePendingMessages(for conversation: Conversation) async throws -> MessageOutboxSyncResult {
        try await synchronizePendingMessages(for: conversation, force: true)
    }

    private func synchronizePendingMessages(
        for conversation: Conversation,
        force: Bool
    ) async throws -> MessageOutboxSyncResult {
        guard isConfigured else { return .empty }
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        guard liveClientReady else {
            throw CSMServiceError.unavailable(lastTransportError ?? "Matrix E2EE klient zatim neni pripraven.")
        }

        var result = MessageOutboxSyncResult.empty
        result.delivered += await reconcilePendingMessagesAlreadyConfirmedIfPossible(for: conversation)
        let records = try await outbox.pendingRecords(for: conversation.conversationId)

        for record in records where force || record.isRetryDue {
            result.attempted += 1
            do {
                let draft = OutgoingMessageDraft(
                    body: record.message.body,
                    attachments: record.message.attachments,
                    replyTo: record.message.replyTo
                )
                let sent = try await liveClient.sendMessage(draft, to: conversation)
                try await history?.appendMessage(sent, conversationId: conversation.conversationId)
                try await outbox.removeMessage(id: record.message.id, conversationId: conversation.conversationId)
                lastTransportError = nil
                result.delivered += 1
            } catch {
                result.failed += 1
                lastTransportError = error.localizedDescription
                try await outbox.recordAttempt(
                    messageId: record.message.id,
                    conversationId: conversation.conversationId,
                    error: error.localizedDescription,
                    retryAfter: retryDelay(attempt: record.attemptCount + 1)
                )
                preserveIncomingSessionIfPossible(afterSendFailure: error)
                break
            }
        }

        return result
    }

    private func merge(
        liveMessages: [ChatMessage],
        pendingMessages: [ChatMessage]
    ) -> [ChatMessage] {
        var mergedById = Dictionary(uniqueKeysWithValues: liveMessages.map { ($0.id, $0) })
        for message in pendingMessages {
            mergedById[message.id] = message
        }
        return ChatMessage.removingSupersededLocalEchoes(
            from: mergedById.values.sorted { $0.sentAt < $1.sentAt }
        )
    }

    /// Matrix timelines are paginated snapshots, not authoritative replacements
    /// for the encrypted offline history. In particular, a newly restored device
    /// can temporarily return an empty page or an undecryptable placeholder for
    /// an event that this device had already cached as plaintext. Keep the richer
    /// cached representation until Matrix supplies a readable update with the
    /// same event id.
    private func mergeHistory(
        cachedMessages: [ChatMessage],
        liveMessages: [ChatMessage]
    ) -> [ChatMessage] {
        var mergedById = Dictionary(uniqueKeysWithValues: cachedMessages.map { ($0.id, $0) })
        for liveMessage in liveMessages {
            if let cachedMessage = mergedById[liveMessage.id],
               Self.isUndecryptablePlaceholder(liveMessage),
               !Self.isUndecryptablePlaceholder(cachedMessage) {
                continue
            }
            mergedById[liveMessage.id] = liveMessage
        }
        return ChatMessage.removingSupersededLocalEchoes(
            from: mergedById.values.sorted { $0.sentAt < $1.sentAt }
        )
    }

    private static func isUndecryptablePlaceholder(_ message: ChatMessage) -> Bool {
        let body = message.body.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return body.contains("nepodarilo desifrovat") ||
            body.contains("nelze desifrovat") ||
            body.contains("unable to decrypt")
    }

    private func visibleMessages(
        liveMessages: [ChatMessage],
        conversation: Conversation
    ) async throws -> [ChatMessage] {
        let reconciliation = try await removePendingMessagesAlreadyConfirmedByMatrix(
            liveMessages: liveMessages,
            conversation: conversation
        )
        let cachedMessages = try await history?.messages(for: conversation.conversationId) ?? []
        let mergedHistory = mergeHistory(
            cachedMessages: cachedMessages,
            liveMessages: reconciliation.messages
        )
        try await history?.saveMessages(mergedHistory, conversationId: conversation.conversationId)
        lastTransportError = nil
        let pending = try await outbox.pendingMessages(for: conversation.conversationId)
        return merge(liveMessages: mergedHistory, pendingMessages: pending)
    }

    private func recordLiveStreamFailure(_ error: any Error) {
        liveClientReady = false
        lastTransportError = error.localizedDescription
    }

    private func recordLiveStreamEnded() {
        liveClientReady = false
        lastTransportError = "Matrix live sync stream ended; reconnecting."
    }

    private func liveMessageStream(for conversation: Conversation) async throws -> AsyncStream<[ChatMessage]>? {
        if !liveClientReady {
            try await restoreLiveClientIfPossible()
        }
        guard liveClientReady,
              let liveStreaming = liveClient as? any MessagingLiveMessageStreaming else {
            return nil
        }
        return try await liveStreaming.messageSnapshots(for: conversation)
    }

    private static func liveStreamReconnectDelayNanoseconds(attempt: Int) -> UInt64 {
        let clampedAttempt = min(max(0, attempt - 1), 5)
        let seconds = min(15.0, pow(2.0, Double(clampedAttempt)) * 0.5)
        return UInt64(seconds * 1_000_000_000)
    }

    private static func singleSnapshotStream(_ messages: [ChatMessage]) -> AsyncStream<[ChatMessage]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuation.yield(messages)
            continuation.finish()
        }
    }

    private func removePendingMessagesAlreadyConfirmedByMatrix(
        liveMessages: [ChatMessage],
        conversation: Conversation
    ) async throws -> PendingMessageReconciliationResult {
        let records = try await outbox.pendingRecords(for: conversation.conversationId)
        guard !records.isEmpty else {
            return PendingMessageReconciliationResult(messages: liveMessages, removedCount: 0)
        }

        var unmatchedLiveMessages = liveMessages.filter(Self.canConfirmPendingRecord)
        var reconciledMessages = liveMessages
        var removedCount = 0
        for record in records where Self.recordMayHaveReachedMatrix(record) {
            guard let index = unmatchedLiveMessages.firstIndex(where: { Self.liveMessage($0, confirms: record) }) else {
                continue
            }
            let matchedLiveMessage = unmatchedLiveMessages[index]
            if let replacementIndex = reconciledMessages.firstIndex(where: { $0.id == matchedLiveMessage.id }),
               Self.shouldRestoreLocalBody(from: record, matchedLiveMessage: matchedLiveMessage) {
                reconciledMessages[replacementIndex] = Self.confirmedMessage(
                    from: record,
                    matchedLiveMessage: matchedLiveMessage
                )
            }
            try await outbox.removeMessage(id: record.message.id, conversationId: conversation.conversationId)
            removedCount += 1
            unmatchedLiveMessages.remove(at: index)
        }
        return PendingMessageReconciliationResult(messages: reconciledMessages, removedCount: removedCount)
    }

    private func reconcilePendingMessagesAlreadyConfirmedIfPossible(for conversation: Conversation) async -> Int {
        do {
            let liveMessages = try await liveClient.messages(for: conversation)
            let reconciliation = try await removePendingMessagesAlreadyConfirmedByMatrix(
                liveMessages: liveMessages,
                conversation: conversation
            )
            if reconciliation.removedCount > 0 {
                try await history?.saveMessages(reconciliation.messages, conversationId: conversation.conversationId)
                lastTransportError = nil
            }
            return reconciliation.removedCount
        } catch {
            lastTransportError = error.localizedDescription
            return 0
        }
    }

    private func latestConfirmedLiveMessage(
        for draft: OutgoingMessageDraft,
        conversation: Conversation,
        attemptedAt: Date
    ) async throws -> ChatMessage? {
        let liveMessages = try await liveClient.messages(for: conversation)
        try await history?.saveMessages(liveMessages, conversationId: conversation.conversationId)
        return liveMessages
            .filter { Self.liveMessage($0, confirms: draft, attemptedAt: attemptedAt) }
            .sorted { $0.sentAt < $1.sentAt }
            .last
    }

    private static func canConfirmPendingRecord(_ message: ChatMessage) -> Bool {
        message.isOwnMessage &&
            message.deliveryState != .pending &&
            (message.deliveryState != .failed || isOwnUndecryptedServerEcho(message)) &&
            message.id.hasPrefix("$")
    }

    private static func recordMayHaveReachedMatrix(_ record: PendingMessageRecord) -> Bool {
        guard let error = record.lastError?.lowercased() else { return false }
        return matrixAcceptanceAmbiguous(error)
    }

    private static func sendFailureMayHaveReachedMatrix(_ error: any Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return matrixAcceptanceAmbiguous(description)
    }

    private func preserveIncomingSessionIfPossible(afterSendFailure error: any Error) {
        if Self.sendFailureMayHaveReachedMatrix(error) {
            return
        }
        liveClientReady = false
    }

    private static func matrixAcceptanceAmbiguous(_ description: String) -> Bool {
        description.contains("send queue") ||
            description.contains("local echo") ||
            description.contains("lokalni matrix echo") ||
            description.contains("echo uz neslo zrusit") ||
            description.contains("sent event") ||
            description.contains("server event") ||
            description.contains("confirmation") ||
            description.contains("potvrdila") ||
            description.contains("nepotvrdila") ||
            description.contains("zablokovana")
    }

    private static func liveMessage(_ liveMessage: ChatMessage, confirms record: PendingMessageRecord) -> Bool {
        let pending = record.message
        let mayHaveReachedMatrix = recordMayHaveReachedMatrix(record)
        guard messageTimeIsPlausible(
            sentAt: liveMessage.sentAt,
            localAttemptedAt: record.queuedAt,
            allowClockSkew: mayHaveReachedMatrix
        ) else {
            return false
        }

        if normalizedBody(liveMessage.body) == normalizedBody(pending.body),
           attachmentSignature(liveMessage.attachments) == attachmentSignature(pending.attachments) {
            return true
        }

        // Older builds could time out waiting for the SDK send-queue callback
        // even though Synapse had accepted the encrypted event. In that case the
        // later live timeline may only expose an own server event that has not
        // been decrypted locally yet. Pair it conservatively with a pending
        // record only after an ambiguous send-queue error.
        return mayHaveReachedMatrix && isOwnUndecryptedServerEcho(liveMessage)
    }

    private static func liveMessage(
        _ liveMessage: ChatMessage,
        confirms draft: OutgoingMessageDraft,
        attemptedAt: Date
    ) -> Bool {
        guard canConfirmPendingRecord(liveMessage) else { return false }
        guard messageTimeIsPlausible(
            sentAt: liveMessage.sentAt,
            localAttemptedAt: attemptedAt,
            allowClockSkew: true
        ) else {
            return false
        }

        if normalizedBody(liveMessage.body) == normalizedBody(draft.body),
           attachmentSignature(liveMessage.attachments) == attachmentSignature(draft.attachments) {
            return true
        }

        return isOwnUndecryptedServerEcho(liveMessage)
    }

    private static func messageTimeIsPlausible(
        sentAt: Date,
        localAttemptedAt: Date,
        allowClockSkew: Bool
    ) -> Bool {
        let serverTimestampLooksCurrent = sentAt >= localAttemptedAt.addingTimeInterval(-60) &&
            sentAt <= Date().addingTimeInterval(300)
        if serverTimestampLooksCurrent {
            return true
        }

        // Matrix event timestamps come from Synapse, while queuedAt/attemptedAt
        // come from the phone. If a user's device clock is wrong, the server can
        // accept the encrypted event and still look "older" than the local
        // pending record. Only ambiguous send-queue/confirmation failures take
        // this skew-tolerant path.
        return allowClockSkew && sentAt <= Date().addingTimeInterval(300)
    }

    private static func normalizedBody(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attachmentSignature(_ attachments: [MessageAttachment]) -> [String] {
        attachments.map { attachment in
            [
                attachment.kind.rawValue,
                attachment.title.trimmingCharacters(in: .whitespacesAndNewlines),
                attachment.mimeType ?? "",
                attachment.byteCount.map(String.init) ?? ""
            ].joined(separator: "|")
        }
    }

    private static func isOwnUndecryptedServerEcho(_ message: ChatMessage) -> Bool {
        guard message.isOwnMessage, message.id.hasPrefix("$") else { return false }
        let normalized = normalizedBody(message.body).lowercased()
        return normalized.contains("nepodarilo desifrovat") ||
            normalized.contains("nepodařilo dešifrovat") ||
            normalized.contains("sifrovana zprava") ||
            normalized.contains("šifrovaná zpráva")
    }

    private static func shouldRestoreLocalBody(
        from record: PendingMessageRecord,
        matchedLiveMessage: ChatMessage
    ) -> Bool {
        recordMayHaveReachedMatrix(record) && isOwnUndecryptedServerEcho(matchedLiveMessage)
    }

    private static func confirmedMessage(
        from record: PendingMessageRecord,
        matchedLiveMessage: ChatMessage
    ) -> ChatMessage {
        var message = record.message
        message.id = matchedLiveMessage.id
        message.roomId = matchedLiveMessage.roomId
        message.senderId = matchedLiveMessage.senderId
        message.senderDisplayName = matchedLiveMessage.senderDisplayName
        message.sentAt = matchedLiveMessage.sentAt
        message.deliveryState = .sent
        message.isOwnMessage = true
        return message
    }

    private static func confirmedMessage(
        from draft: OutgoingMessageDraft,
        conversation: Conversation,
        matchedLiveMessage: ChatMessage
    ) -> ChatMessage {
        if !isOwnUndecryptedServerEcho(matchedLiveMessage) {
            return matchedLiveMessage
        }
        return ChatMessage(
            id: matchedLiveMessage.id,
            roomId: matchedLiveMessage.roomId.isEmpty ? conversation.conversationId : matchedLiveMessage.roomId,
            senderId: matchedLiveMessage.senderId,
            senderDisplayName: matchedLiveMessage.senderDisplayName,
            body: draft.body,
            attachments: draft.attachments.map { attachment in
                var sentAttachment = attachment
                sentAttachment.localOnly = false
                return sentAttachment
            },
            replyTo: draft.replyTo,
            reactions: matchedLiveMessage.reactions,
            sentAt: matchedLiveMessage.sentAt,
            deliveryState: .sent,
            isOwnMessage: true
        )
    }

    private func persistUpdatedMessage(_ message: ChatMessage, conversation: Conversation) async throws {
        guard let history else { return }
        var messages = try await history.messages(for: conversation.conversationId)
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        try await history.saveMessages(messages.sorted { $0.sentAt < $1.sentAt }, conversationId: conversation.conversationId)
    }

    private func restoreLiveClientIfPossible() async throws {
        guard let bootstrap = lastBootstrap else { return }
        do {
            try await liveClient.configure(with: bootstrap)
            liveClientReady = true
            lastTransportError = nil
        } catch {
            liveClientReady = false
            lastTransportError = error.localizedDescription
            throw error
        }
    }

    private static func canKeepExistingLiveReceiveSession(
        after error: any Error,
        previousBootstrap: MessagingBootstrap?,
        bootstrap: MessagingBootstrap,
        hadReadyLiveClient: Bool
    ) -> Bool {
        guard hadReadyLiveClient,
              sameLiveReceiveSession(previousBootstrap, bootstrap),
              !configureFailureInvalidatesExistingSession(error) else {
            return false
        }
        return true
    }

    private static func sameLiveReceiveSession(
        _ previousBootstrap: MessagingBootstrap?,
        _ bootstrap: MessagingBootstrap
    ) -> Bool {
        guard let previousBootstrap else { return false }
        return previousBootstrap.providerId == bootstrap.providerId &&
            previousBootstrap.homeserverBaseUrl == bootstrap.homeserverBaseUrl &&
            previousBootstrap.serverName == bootstrap.serverName &&
            previousBootstrap.userId == bootstrap.userId &&
            previousBootstrap.deviceId == bootstrap.deviceId
    }

    private static func configureFailureInvalidatesExistingSession(_ error: any Error) -> Bool {
        let description = error.localizedDescription.lowercased()
        return description.containsAny(of: Self.sessionInvalidationFailureMarkers)
    }

    private func shouldQueueAfterLiveFailure(_ error: any Error) -> Bool {
        if let matrixError = error as? MatrixAPIError {
            switch matrixError {
            case .missingBootstrap, .missingReactionEventId, .badURL:
                return false
            case .missingRoomBinding:
                // The message must not leave the device without an encrypted
                // room, but preserving the draft in the encrypted outbox is the
                // expected offline-first behavior while CSM Messaging finishes
                // room binding.
                return true
            case .httpError(let code, _):
                return code == 408 || code == 425 || code == 429 || code >= 500
            }
        }
        if let serviceError = error as? CSMServiceError {
            switch serviceError {
            case .authenticationRequired, .disabled, .invalidState:
                return false
            case .unavailable:
                break
            }
        }
        let description = error.localizedDescription.lowercased()
        if description.containsAny(of: Self.nonQueueableFailureMarkers) {
            return false
        }
        if description.containsAny(of: Self.queueableFailureMarkers) {
            return true
        }
        return true
    }

    private static let nonQueueableFailureMarkers = [
        "m_unknown_token",
        "unknown token",
        "access token expired",
        "unauthorized",
        "401",
        "m_forbidden",
        "forbidden",
        "403",
        "not in room",
        "not joined",
        "not a member",
        "m_not_joined",
        "m_room_forbidden",
        "matrix room neni sifrovana",
        "plaintext",
        "not encrypted",
        "untrusted matrix devices",
        "insecure devices",
        "identity violation",
        "cross verification required",
        "missing media content",
        "invalid mime type",
        "unable to encrypt",
        "olm",
        "megolm"
    ]

    private static let sessionInvalidationFailureMarkers = [
        "m_unknown_token",
        "unknown token",
        "access token expired",
        "unauthorized",
        "401",
        "invalid token",
        "missing bootstrap",
        "not configured",
        "session expired"
    ]

    private static let queueableFailureMarkers = [
        "timed out",
        "timeout",
        "network",
        "internet",
        "connection",
        "connect",
        "offline",
        "dns",
        "temporarily",
        "too many requests",
        "429",
        "502",
        "503",
        "504"
    ]

    private func makePendingMessage(_ draft: OutgoingMessageDraft, conversation: Conversation) -> ChatMessage {
        ChatMessage(
            id: UUID().uuidString,
            roomId: conversation.conversationId,
            senderId: "local-device",
            senderDisplayName: "Ja",
            body: draft.body,
            attachments: draft.attachments,
            replyTo: draft.replyTo,
            sentAt: .now,
            deliveryState: .pending,
            isOwnMessage: true
        )
    }

    private func retryDelay(attempt: Int) -> TimeInterval {
        min(300, pow(2.0, Double(max(0, attempt - 1))) * 15.0)
    }
}

private struct PendingMessageReconciliationResult: Sendable {
    var messages: [ChatMessage]
    var removedCount: Int
}

private extension String {
    func containsAny(of markers: [String]) -> Bool {
        markers.contains { contains($0) }
    }
}
