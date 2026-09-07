import Foundation
import Observation
import os

// MARK: - Session

/// The small, security-sensitive part of chat state.
///
/// `AppModel` remains the compatibility facade for the host application, while
/// this store is the single owner of the native chat session snapshot. Keeping
/// it separate prevents map/report refreshes from invalidating chat screens.
@MainActor
@Observable
final class ChatSessionStore {
    struct Snapshot: Equatable, Sendable {
        var authState: AuthState = .checking
        var actor: AuthenticatedActor?
        var isBusy = false
        var deviceID: String?
    }

    private(set) var snapshot = Snapshot()

    func update(
        authState: AuthState,
        actor: AuthenticatedActor?,
        isBusy: Bool,
        deviceID: String?
    ) {
        snapshot = Snapshot(
            authState: authState,
            actor: actor,
            isBusy: isBusy,
            deviceID: deviceID
        )
    }

    func reset() {
        snapshot = Snapshot(authState: .signedOut)
    }
}

// MARK: - Conversation list

struct ConversationListSnapshot: Equatable, Sendable {
    var conversations: [Conversation] = []
    var selectedConversation: Conversation?
    var loadState: ConversationListLoadState = .notLoaded
    var revision: UInt64 = 0
}

/// Owns immutable, screen-sized conversation list snapshots.
@MainActor
@Observable
final class ConversationListStore {
    private(set) var snapshot = ConversationListSnapshot()

    func replace(
        _ conversations: [Conversation],
        selection: Conversation?,
        loadState: ConversationListLoadState
    ) {
        snapshot = ConversationListSnapshot(
            conversations: conversations,
            selectedConversation: selection,
            loadState: loadState,
            revision: snapshot.revision &+ 1
        )
    }

    func setSelection(_ conversation: Conversation?) {
        guard snapshot.selectedConversation?.conversationId != conversation?.conversationId ||
                snapshot.selectedConversation != conversation else {
            return
        }
        snapshot.selectedConversation = conversation
        snapshot.revision &+= 1
    }

    func setLoadState(_ state: ConversationListLoadState) {
        guard snapshot.loadState != state else { return }
        snapshot.loadState = state
        snapshot.revision &+= 1
    }

    func reset() {
        snapshot = ConversationListSnapshot(revision: snapshot.revision &+ 1)
    }
}

// MARK: - Timeline

struct TimelineWindowPolicy: Equatable, Sendable {
    var initialMessageLimit = 200
    var retainedMessageLimit = 500

    static let mobile = TimelineWindowPolicy()
}

struct TimelineState: Equatable, Sendable {
    var conversationID: String?
    var messages: [ChatMessage] = []
    var voiceCallMessages: [ChatMessage] = []
    var isLoading = false
    var hasEarlierMessages = false
    var hasLaterMessages = false
    var revision: UInt64 = 0
}

enum TimelineAction: Sendable {
    case open(conversationID: String)
    case replaceRemote([ChatMessage], hasEarlier: Bool)
    case prependEarlier([ChatMessage], hasEarlier: Bool)
    case returnToLatest
    case upsert(ChatMessage)
    case remove(messageID: String)
    case removeWhere(@Sendable (ChatMessage) -> Bool)
    case replaceVoiceCalls([ChatMessage])
    case setLoading(Bool)
    case reset
}

/// Pure reducer: every add/confirmation/reaction/edit/delete goes through one
/// deterministic path. This is also the deduplication boundary.
enum TimelineReducer {
    static func reduce(
        _ state: inout TimelineState,
        action: TimelineAction,
        policy: TimelineWindowPolicy = .mobile
    ) {
        switch action {
        case .open(let conversationID):
            guard state.conversationID != conversationID else { return }
            state = TimelineState(
                conversationID: conversationID,
                isLoading: true,
                revision: state.revision &+ 1
            )

        case .replaceRemote(let incoming, let hasEarlier):
            if state.hasLaterMessages {
                let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
                state.messages = state.messages.map { incomingByID[$0.id] ?? $0 }
                state.isLoading = false
                state.revision &+= 1
                break
            }
            state.messages = normalized(incoming, limit: policy.retainedMessageLimit)
            state.hasEarlierMessages = hasEarlier
            state.hasLaterMessages = false
            state.isLoading = false
            state.revision &+= 1

        case .prependEarlier(let incoming, let hasEarlier):
            let merged = normalized(
                incoming + state.messages,
                limit: policy.retainedMessageLimit,
                retaining: .oldest
            )
            state.hasLaterMessages =
                state.hasLaterMessages ||
                Set(incoming.map(\.id) + state.messages.map(\.id)).count > merged.count
            state.messages = merged
            state.hasEarlierMessages = hasEarlier
            state.isLoading = false
            state.revision &+= 1

        case .returnToLatest:
            state.hasLaterMessages = false
            state.isLoading = true
            state.revision &+= 1

        case .upsert(let message):
            if state.hasLaterMessages,
               !message.isOwnMessage,
               !state.messages.contains(where: { $0.id == message.id }) {
                return
            }
            var byID = Dictionary(uniqueKeysWithValues: state.messages.map { ($0.id, $0) })
            byID[message.id] = message
            state.messages = normalized(Array(byID.values), limit: policy.retainedMessageLimit)
            if message.isOwnMessage {
                state.hasLaterMessages = false
            }
            state.revision &+= 1

        case .remove(let messageID):
            let oldCount = state.messages.count
            state.messages.removeAll { $0.id == messageID }
            if state.messages.count != oldCount {
                state.revision &+= 1
            }

        case .removeWhere(let predicate):
            let oldCount = state.messages.count
            state.messages.removeAll(where: predicate)
            if state.messages.count != oldCount {
                state.revision &+= 1
            }

        case .replaceVoiceCalls(let calls):
            state.voiceCallMessages = normalized(calls, limit: 100)
            state.revision &+= 1

        case .setLoading(let isLoading):
            guard state.isLoading != isLoading else { return }
            state.isLoading = isLoading
            state.revision &+= 1

        case .reset:
            state = TimelineState(revision: state.revision &+ 1)
        }
    }

    private enum RetentionEdge {
        case oldest
        case newest
    }

    private static func normalized(
        _ messages: [ChatMessage],
        limit: Int,
        retaining edge: RetentionEdge = .newest
    ) -> [ChatMessage] {
        let withoutSupersededEchoes = ChatMessage.removingSupersededLocalEchoes(from: messages)
        var byID: [String: ChatMessage] = [:]
        byID.reserveCapacity(withoutSupersededEchoes.count)
        for message in withoutSupersededEchoes {
            byID[message.id] = message
        }
        let sorted = byID.values.sorted {
            $0.sentAt == $1.sentAt ? $0.id < $1.id : $0.sentAt < $1.sentAt
        }
        guard sorted.count > limit else { return sorted }
        switch edge {
        case .oldest:
            return Array(sorted.prefix(limit))
        case .newest:
            return Array(sorted.suffix(limit))
        }
    }
}

@MainActor
@Observable
final class TimelineStore {
    private(set) var state = TimelineState()
    @ObservationIgnored private let policy: TimelineWindowPolicy
    @ObservationIgnored private let searchIndex: SearchIndex

    init(
        policy: TimelineWindowPolicy = .mobile,
        searchIndex: SearchIndex = SearchIndex()
    ) {
        self.policy = policy
        self.searchIndex = searchIndex
    }

    func send(_ action: TimelineAction) {
        TimelineReducer.reduce(&state, action: action, policy: policy)
        let conversationID = state.conversationID
        let messages = state.messages
        let revision = state.revision
        Task {
            await searchIndex.replace(
                messages,
                conversationID: conversationID,
                revision: revision
            )
        }
    }

    func searchMessageIDs(_ query: String, limit: Int = 100) async -> [String] {
        await searchIndex.replace(
            state.messages,
            conversationID: state.conversationID,
            revision: state.revision
        )
        return await searchIndex.search(
            query,
            conversationID: state.conversationID,
            limit: limit
        )
    }
}

// MARK: - Timeline synchronization

/// Owns exactly one synchronization loop for the active room.
///
/// A live stream is always preferred. Polling starts only after the stream is
/// unavailable or terminates, so the same remote event is never imported by
/// two competing loops. Changing rooms increments the generation and makes
/// late snapshots from the old room harmless.
@MainActor
final class TimelineSynchronizationController {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0

    func start(
        conversation: Conversation,
        messaging: any MessagingClientProtocol,
        prepareFallbackRefresh: @escaping @MainActor () async -> Void,
        consume: @escaping @MainActor ([ChatMessage]) async -> Void,
        reportError: @escaping @MainActor (Error) -> Void
    ) {
        stop()
        generation &+= 1
        let activeGeneration = generation

        task = Task { @MainActor [weak self] in
            guard let self else { return }

            if let streaming = messaging as? any MessagingLiveMessageStreaming {
                do {
                    let stream = try await streaming.messageSnapshots(for: conversation)
                    for await snapshot in stream {
                        guard self.isCurrent(activeGeneration) else { return }
                        await consume(snapshot)
                    }
                } catch {
                    guard self.isCurrent(activeGeneration) else { return }
                    reportError(error)
                }
            }

            await self.runFallbackPolling(
                generation: activeGeneration,
                conversation: conversation,
                messaging: messaging,
                prepareRefresh: prepareFallbackRefresh,
                consume: consume,
                reportError: reportError
            )
        }
    }

    func stop() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    private func runFallbackPolling(
        generation activeGeneration: UInt64,
        conversation: Conversation,
        messaging: any MessagingClientProtocol,
        prepareRefresh: @escaping @MainActor () async -> Void,
        consume: @escaping @MainActor ([ChatMessage]) async -> Void,
        reportError: @escaping @MainActor (Error) -> Void
    ) async {
        while isCurrent(activeGeneration) {
            do {
                try await Task.sleep(for: .seconds(8))
            } catch {
                return
            }
            guard isCurrent(activeGeneration) else { return }
            await prepareRefresh()
            do {
                let snapshot = try await messaging.messages(for: conversation)
                guard isCurrent(activeGeneration) else { return }
                await consume(snapshot)
            } catch {
                guard isCurrent(activeGeneration) else { return }
                reportError(error)
            }
        }
    }

    private func isCurrent(_ activeGeneration: UInt64) -> Bool {
        !Task.isCancelled && generation == activeGeneration
    }
}

enum ChatMessagePresentationFactory {
    static func voiceCallMessage(
        for call: CSMVoiceCall,
        conversation: Conversation,
        actor: AuthenticatedActor?
    ) -> ChatMessage {
        let isOutgoing = call.direction == .outgoing
        let senderID = isOutgoing
            ? (actor?.subjectId ?? call.initiatorSubjectId)
            : call.initiatorSubjectId
        let senderName = isOutgoing
            ? (actor?.displayName ?? CSMLocalization.text("chat.call.you", fallback: "Vy"))
            : conversation.title
        let body: String

        switch call.phase {
        case .missed:
            body = isOutgoing
                ? CSMLocalization.text("chat.call.no_answer", fallback: "Hovor bez odpovědi")
                : CSMLocalization.text("chat.call.missed", fallback: "Nepřijatý hovor")
        case .declined:
            body = isOutgoing
                ? CSMLocalization.text("chat.call.declined_by_recipient", fallback: "Hovor byl odmítnut")
                : CSMLocalization.text("chat.call.declined", fallback: "Odmítnutý hovor")
        case .cancelled:
            body = CSMLocalization.text("chat.call.cancelled", fallback: "Zrušený hovor")
        case .failed:
            body = CSMLocalization.text("chat.call.failed", fallback: "Hovor se nepodařilo spojit")
        case .ended:
            if let connectedAt = call.connectedAt, let endedAt = call.endedAt {
                body = String(
                    format: CSMLocalization.text(
                        "chat.call.completed.duration",
                        fallback: "Hlasový hovor · %@"
                    ),
                    voiceCallDurationText(max(0, endedAt.timeIntervalSince(connectedAt)))
                )
            } else {
                body = CSMLocalization.text("chat.call.ended", fallback: "Ukončený hovor")
            }
        default:
            body = CSMLocalization.text("chat.call.ended", fallback: "Ukončený hovor")
        }

        return ChatMessage(
            id: "voice-call:\(call.callId)",
            roomId: call.roomId,
            senderId: senderID,
            senderDisplayName: senderName,
            body: body,
            sentAt: call.endedAt ?? call.updatedAt,
            deliveryState: .read,
            isOwnMessage: isOutgoing
        )
    }

    static func forwardingDraft(from message: ChatMessage) -> OutgoingMessageDraft? {
        guard !message.isDeleted else { return nil }

        let forwardableAttachments = message.attachments.filter { attachment in
            attachment.payloadData != nil ||
                attachment.localFileURL != nil ||
                attachment.kind == .location ||
                attachment.kind == .safetyStatus
        }
        var body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let skippedAttachmentTitles = message.attachments
            .filter { attachment in
                !forwardableAttachments.contains(where: { $0.id == attachment.id })
            }
            .map(\.title)
        if !skippedAttachmentTitles.isEmpty {
            let note = "Původní příloha není na tomto zařízení dostupná: \(skippedAttachmentTitles.joined(separator: ", "))"
            body = body.isEmpty ? note : "\(body)\n\n\(note)"
        }

        let draft = OutgoingMessageDraft(body: body, attachments: forwardableAttachments)
        return draft.isEmpty ? nil : draft
    }

    private static func voiceCallDurationText(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Incremental local index used by the search UI instead of filtering and
/// normalizing the complete timeline for every keystroke.
actor SearchIndex {
    private struct Entry: Sendable {
        var conversationID: String?
        var normalizedText: String
        var sentAt: Date
    }

    private var entriesByMessageID: [String: Entry] = [:]
    private var indexedRevision: UInt64 = 0

    func replace(
        _ messages: [ChatMessage],
        conversationID: String?,
        revision: UInt64? = nil
    ) {
        if let revision {
            guard revision >= indexedRevision else { return }
            if revision == indexedRevision, !entriesByMessageID.isEmpty {
                return
            }
            indexedRevision = revision
        }
        let validIDs = Set(messages.map(\.id))
        entriesByMessageID = entriesByMessageID.filter { validIDs.contains($0.key) }
        for message in messages {
            entriesByMessageID[message.id] = Entry(
                conversationID: conversationID,
                normalizedText: Self.searchableText(message),
                sentAt: message.sentAt
            )
        }
    }

    func apply(_ message: ChatMessage, conversationID: String?) {
        entriesByMessageID[message.id] = Entry(
            conversationID: conversationID,
            normalizedText: Self.searchableText(message),
            sentAt: message.sentAt
        )
    }

    func remove(messageID: String) {
        entriesByMessageID.removeValue(forKey: messageID)
    }

    func search(_ query: String, conversationID: String?, limit: Int) -> [String] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return [] }
        return entriesByMessageID
            .filter { _, entry in
                entry.conversationID == conversationID &&
                    entry.normalizedText.localizedStandardContains(normalized)
            }
            .sorted { $0.value.sentAt < $1.value.sentAt }
            .suffix(max(0, limit))
            .map(\.key)
    }

    private static func searchableText(_ message: ChatMessage) -> String {
        normalize(
            [
                message.body,
                message.senderDisplayName,
                message.replyTo?.bodyPreview ?? "",
                message.attachments.map(\.title).joined(separator: " ")
            ].joined(separator: " ")
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Outbox

/// Serializes outbox mutations and assigns a stable idempotency key before a
/// message is persisted. The transaction id survives restart and reconnect.
actor OutboxActor {
    private let store: any MessageOutboxStoring

    init(store: any MessageOutboxStoring) {
        self.store = store
    }

    @discardableResult
    func enqueue(
        _ message: ChatMessage,
        conversation: Conversation,
        transactionID: String? = nil
    ) async throws -> String {
        let stableID = transactionID ?? message.id
        try await store.enqueue(message, conversation: conversation)
        return stableID
    }

    func pendingRecords(conversationID: String) async throws -> [PendingMessageRecord] {
        try await store.pendingRecords(for: conversationID)
    }

    func remove(messageID: String, conversationID: String) async throws {
        try await store.removeMessage(id: messageID, conversationId: conversationID)
    }
}

// MARK: - Media

/// File-backed media preparation. Large attachments are copied outside the main
/// actor and Matrix receives a file URL instead of an in-memory `Data` blob.
actor MediaPipelineActor {
    static let shared = MediaPipelineActor()

    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent("csm-message-media", isDirectory: true)
    }

    func prepare(
        sourceURL: URL,
        kind: MessageAttachmentKind,
        title: String,
        mimeType: String?,
        durationSeconds: Double? = nil
    ) throws -> MessageAttachment {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let target = rootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(sourceURL.pathExtension)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.copyItem(at: sourceURL, to: target)
        let values = try target.resourceValues(forKeys: [.fileSizeKey])
        return MessageAttachment(
            kind: kind,
            title: title,
            mimeType: mimeType,
            byteCount: values.fileSize,
            durationSeconds: durationSeconds,
            localFileURL: target
        )
    }

    func materializedFile(for attachment: MessageAttachment) throws -> URL {
        if let localFileURL = attachment.localFileURL,
           fileManager.fileExists(atPath: localFileURL.path) {
            return localFileURL
        }
        guard let payload = attachment.payloadData else {
            throw CSMServiceError.invalidState(
                "Příloha \(attachment.title) nemá lokální soubor pro odeslání."
            )
        }
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let target = rootDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        try payload.write(to: target, options: [.atomic])
        return target
    }

    func removeOwnedFile(for attachment: MessageAttachment) {
        guard let url = attachment.localFileURL,
              url.path.hasPrefix(rootDirectory.path) else {
            return
        }
        try? fileManager.removeItem(at: url)
    }
}

// MARK: - Performance release gates

enum ChatPerformanceBudget {
    static let localConversationListMilliseconds = 700.0
    static let cachedConversationOpenMilliseconds = 200.0
    static let localEchoMilliseconds = 100.0
    static let interactionMilliseconds = 100.0
    static let mainThreadHangMilliseconds = 250.0
}

enum ChatPerformance {
    private static let logger = Logger(subsystem: "cz.zeleznalady.csm.messenger", category: "ChatPerformance")
    private static let signpostLog = OSLog(
        subsystem: "cz.zeleznalady.csm.messenger",
        category: .pointsOfInterest
    )

    static func measure<T>(
        _ name: StaticString,
        budgetMilliseconds: Double,
        operation: () throws -> T
    ) rethrows -> T {
        let clock = ContinuousClock()
        let start = clock.now
        os_signpost(.begin, log: signpostLog, name: name)
        defer {
            os_signpost(.end, log: signpostLog, name: name)
        }
        let result = try operation()
        let elapsed = start.duration(to: clock.now)
        let components = elapsed.components
        let milliseconds =
            Double(components.seconds) * 1_000 +
            Double(components.attoseconds) / 1_000_000_000_000_000
        if milliseconds > budgetMilliseconds {
            logger.warning(
                "\(String(describing: name), privacy: .public) exceeded budget: \(milliseconds, privacy: .public) ms"
            )
        }
        return result
    }
}
