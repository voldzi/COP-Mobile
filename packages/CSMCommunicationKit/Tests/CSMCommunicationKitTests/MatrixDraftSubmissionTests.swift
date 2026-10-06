import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class MatrixDraftSubmissionTests: XCTestCase {
    private func setup() async throws -> (MessagingBootstrap, Conversation) {
        var bootstrap = try await PreviewCopAPIClient().messagingBootstrap(deviceId: "synthetic-device")
        bootstrap.userId = "@a:matrix.test"
        let conversations = try await PreviewCopAPIClient().conversations()
        var conversation = try XCTUnwrap(conversations.first)
        conversation.matrix = MessagingMatrixRoom(roomId: "!synthetic:matrix.test", state: "active", encrypted: true)
        return (bootstrap, conversation)
    }

    func testPendingQueueIsNotSentOrBlindRetriedAndLateExactAckCompletes() async throws {
        let (bootstrap, conversation) = try await setup()
        let outbox = InMemoryMessageOutbox()
        let history = InMemoryMessageHistoryStore()
        let live = DraftSubmissionMessaging(confirmation: .pending)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox, history: history)
        try await wrapper.configure(with: bootstrap)
        let pending = try await wrapper.sendMessage("Synthetic", to: conversation)
        XCTAssertEqual(pending.deliveryState, .pending)
        _ = try await wrapper.synchronizePendingMessages(for: conversation)
        let callsBefore = await live.queuedParts
        XCTAssertEqual(callsBefore, [0])
        let before = try await outbox.pendingRecords(for: conversation.conversationId)
        let tx = try XCTUnwrap(before.first?.matrixSubmission?.parts.first?.transactionID)
        XCTAssertEqual(tx, DraftSubmissionMessaging.fullTransactionID)
        await live.confirm(transaction: "unrelated-own-transaction", event: "$unrelated")
        _ = try await wrapper.synchronizePendingMessages(for: conversation)
        let unmatched = try await outbox.pendingMessageCount()
        XCTAssertEqual(unmatched, 1)
        await live.confirm(transaction: tx, event: "$exact")
        let result = try await wrapper.synchronizePendingMessages(for: conversation)
        XCTAssertEqual(result.delivered, 1)
        let after = try await outbox.pendingMessageCount()
        XCTAssertEqual(after, 0)
        let stored = try await history.messages(for: conversation.conversationId)
        XCTAssertEqual(stored.map(\.id), ["$exact"])
        let callsAfter = await live.queuedParts
        XCTAssertEqual(callsAfter, [0])
    }

    func testEncryptedJournalSurvivesRestartAndDoesNotRepeatUnknownSubmission() async throws {
        let (bootstrap, conversation) = try await setup()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cop-draft-ledger-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = KeychainCredentialStore(service: "synthetic-unused-ledger")
        let key = Data(repeating: 7, count: 32)
        let firstStore = EncryptedMessageOutbox(keychain: keychain, rootDirectory: root, fixedKeyData: key)
        let first = DraftSubmissionMessaging(confirmation: .throwBeforeReceipt)
        let wrapper = OfflineFirstMessagingClient(liveClient: first, outbox: firstStore)
        try await wrapper.configure(with: bootstrap)
        let message = try await wrapper.sendMessage("Synthetic", to: conversation)
        XCTAssertEqual(message.deliveryState, .pending)
        let reopenedStore = EncryptedMessageOutbox(keychain: keychain, rootDirectory: root, fixedKeyData: key)
        let reopenedLive = DraftSubmissionMessaging(confirmation: .confirmed)
        let reopened = OfflineFirstMessagingClient(liveClient: reopenedLive, outbox: reopenedStore)
        try await reopened.configure(with: bootstrap)
        _ = try await reopened.synchronizePendingMessages(for: conversation)
        let records = try await reopenedStore.pendingRecords(for: conversation.conversationId)
        XCTAssertEqual(records.first?.matrixSubmission?.parts.first?.state, .queuing)
        let calls = await reopenedLive.queuedParts
        XCTAssertTrue(calls.isEmpty)
        do { _ = try await reopenedStore.discardPendingMessages(for: conversation.conversationId); XCTFail("Ambiguous queue cannot be discarded") } catch {}
    }

    func testMultipartAckDoesNotRepeatConfirmedPartAndRequiresAllParts() async throws {
        let (bootstrap, conversation) = try await setup()
        let outbox = InMemoryMessageOutbox()
        let live = DraftSubmissionMessaging(confirmation: .secondPartPending)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        try await wrapper.configure(with: bootstrap)
        let draft = OutgoingMessageDraft(body: "Synthetic", attachments: [
            MessageAttachment(id: "one", kind: .document, title: "one.txt", mimeType: "text/plain", byteCount: 1, payloadData: Data([1])),
            MessageAttachment(id: "two", kind: .document, title: "two.txt", mimeType: "text/plain", byteCount: 1, payloadData: Data([2]))
        ])
        let message = try await wrapper.sendMessage(draft, to: conversation)
        XCTAssertEqual(message.deliveryState, .pending)
        _ = try await wrapper.synchronizePendingMessages(for: conversation)
        let calls = await live.queuedParts
        XCTAssertEqual(calls, [0, 1])
        let records = try await outbox.pendingRecords(for: conversation.conversationId)
        let state = try XCTUnwrap(records.first?.matrixSubmission)
        XCTAssertEqual(state.parts.map(\.state), [.confirmed, .queued])
        await live.confirm(transaction: state.parts[1].transactionID!, event: "$second-ack")
        let result = try await wrapper.synchronizePendingMessages(for: conversation)
        XCTAssertEqual(result.delivered, 1)
        let finalCalls = await live.queuedParts
        XCTAssertEqual(finalCalls, [0, 1])
    }

    func testDifferentAccountCannotPublishOrResendJournalAndLegacyRecordsAreHeld() async throws {
        var (bootstrap, conversation) = try await setup()
        let outbox = InMemoryMessageOutbox()
        let live = DraftSubmissionMessaging(confirmation: .pending)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        try await wrapper.configure(with: bootstrap)
        let pending = try await wrapper.sendMessage("Synthetic", to: conversation)
        bootstrap.userId = "@b:matrix.test"
        try await wrapper.configure(with: bootstrap)
        let visible = try await wrapper.messages(for: conversation)
        XCTAssertFalse(visible.contains { $0.id == pending.id })
        _ = try await wrapper.synchronizePendingMessages(for: conversation)
        var legacy = pending; legacy.id = "legacy-unscoped"
        try await outbox.enqueue(legacy, conversation: conversation)
        _ = try await wrapper.synchronizePendingMessages(for: conversation)
        let calls = await live.queuedParts
        XCTAssertEqual(calls, [0])
        let retained = try await outbox.pendingMessageCount()
        XCTAssertEqual(retained, 2)
    }

    func testLateExactAckInLiveSnapshotRemovesPendingWithoutNewSend() async throws {
        let (bootstrap, conversation) = try await setup()
        let outbox = InMemoryMessageOutbox()
        let live = DraftSubmissionMessaging(confirmation: .pending)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        try await wrapper.configure(with: bootstrap)
        _ = try await wrapper.sendMessage("Synthetic", to: conversation)
        var echo = ChatMessage(id: "$late-live-ack", roomId: conversation.activeMatrixRoomId ?? conversation.conversationId,
            senderId: bootstrap.userId!, senderDisplayName: "Synthetic", body: "Synthetic",
            sentAt: .now, deliveryState: .sent, isOwnMessage: true)
        echo.matrixTransactionID = DraftSubmissionMessaging.fullTransactionID
        await live.setLiveMessages([echo])
        _ = try await wrapper.messages(for: conversation)
        let remaining = try await outbox.pendingMessageCount()
        let calls = await live.queuedParts
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(calls, [0])
    }

    func testConcurrentEncryptedWritersPreserveEveryDraftAndJournalCannotRegress() async throws {
        let (bootstrap, conversation) = try await setup()
        let scope = try XCTUnwrap(MatrixLocalStoreScope(bootstrap))
        let draft = OutgoingMessageDraft(body: "Synthetic")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cop-draft-concurrent-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Data(repeating: 8, count: 32)
        let a = EncryptedMessageOutbox(keychain: KeychainCredentialStore(service: "synthetic-unused"), rootDirectory: root, fixedKeyData: key)
        let b = EncryptedMessageOutbox(keychain: KeychainCredentialStore(service: "synthetic-unused"), rootDirectory: root, fixedKeyData: key)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let message = ChatMessage(id: "synthetic-" + String(index), roomId: conversation.conversationId,
                        senderId: scope.userID, senderDisplayName: "Synthetic", body: "Synthetic",
                        sentAt: .now, deliveryState: .pending, isOwnMessage: true)
                    try await (index.isMultiple(of: 2) ? a : b).enqueueMatrixDraft(message, conversation: conversation,
                        submission: MatrixDraftSubmission(scope: scope, draft: draft, roomID: conversation.activeMatrixRoomId ?? ""))
                }
            }
            try await group.waitForAll()
        }
        let records = try await a.pendingRecords(for: conversation.conversationId)
        XCTAssertEqual(records.count, 12)
        let first = try XCTUnwrap(records.first)
        var queued = try XCTUnwrap(first.matrixSubmission)
        queued.parts[0].state = .queued; queued.parts[0].transactionID = "synthetic-exact-tx"
        try await a.updateMatrixSubmission(queued, messageId: first.id, conversationId: conversation.conversationId)
        do {
            try await b.updateMatrixSubmission(first.matrixSubmission!, messageId: first.id, conversationId: conversation.conversationId)
            XCTFail("Journal cannot regress to notStarted and make another send possible")
        } catch {}
    }

    func testExplicitTrustFailureRemainsVisibleAfterLiveSnapshotAndAccountSwitchDoesNotLeakIt() async throws {
        var (bootstrap, conversation) = try await setup()
        let wrapper = OfflineFirstMessagingClient(liveClient: DraftSubmissionMessaging(confirmation: .pendingWithTrustFailure), outbox: InMemoryMessageOutbox())
        try await wrapper.configure(with: bootstrap)
        _ = try await wrapper.sendMessage("Synthetic", to: conversation)
        var otherConversation = conversation
        otherConversation.conversationId = "synthetic-other-conversation"
        otherConversation.matrix = MessagingMatrixRoom(roomId: "!other:matrix.test", state: "active", encrypted: true)
        let unrelatedFailure = await wrapper.latestTransportError(for: otherConversation)
        XCTAssertNil(unrelatedFailure, "Trust failure belongs to the original room even before a snapshot clears global state")
        _ = try await wrapper.messages(for: conversation)
        let failure = await wrapper.latestTransportError(for: conversation)
        XCTAssertEqual(failure, MatrixDraftSubmission.Failure.untrustedDevices.message)
        bootstrap.userId = "@b:matrix.test"
        try await wrapper.configure(with: bootstrap)
        let otherFailure = await wrapper.latestTransportError(for: conversation)
        XCTAssertNil(otherFailure)
    }

    func testRoomRebindingCannotConfirmOrResumeOriginalJournal() async throws {
        let (bootstrap, original) = try await setup()
        let outbox = InMemoryMessageOutbox()
        let live = DraftSubmissionMessaging(confirmation: .pending)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        try await wrapper.configure(with: bootstrap)
        let pending = try await wrapper.sendMessage("Synthetic", to: original)
        var rebound = original
        rebound.matrix = MessagingMatrixRoom(roomId: "!different:matrix.test", state: "active", encrypted: true)
        await live.confirm(transaction: DraftSubmissionMessaging.fullTransactionID, event: "$foreign-room-ack")
        var echo = pending
        echo.id = "$foreign-room-ack"; echo.roomId = rebound.activeMatrixRoomId!
        echo.deliveryState = .sent; echo.matrixTransactionID = DraftSubmissionMessaging.fullTransactionID
        await live.setLiveMessages([echo])
        _ = try await wrapper.synchronizePendingMessages(for: rebound)
        let visible = try await wrapper.messages(for: rebound)
        XCTAssertFalse(visible.contains { $0.id == pending.id })
        let records = try await outbox.pendingRecords(for: original.conversationId)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.matrixSubmission?.roomID, original.activeMatrixRoomId)
        XCTAssertEqual(records.first?.matrixSubmission?.parts.first?.state, .queued)
        let calls = await live.queuedParts
        XCTAssertEqual(calls, [0])
    }

    func testAccountSwitchWhileRemovingConfirmedDraftCannotPublishSentToNewAccount() async throws {
        var (bootstrap, conversation) = try await setup()
        let outbox = PausingRemovalOutbox()
        let live = DraftSubmissionMessaging(confirmation: .confirmed)
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        try await wrapper.configure(with: bootstrap)
        let send = Task { try await wrapper.sendMessage("Synthetic", to: conversation) }
        let reachedRemoval = await outbox.waitUntilRemoving()
        guard reachedRemoval else {
            let reason = await wrapper.latestTransportError(for: conversation)
            XCTFail("Fixture did not reach removal: " + (reason ?? "unknown"))
            send.cancel(); return
        }
        bootstrap.userId = "@b:matrix.test"
        try await wrapper.configure(with: bootstrap)
        await outbox.resumeRemoval()
        do { _ = try await send.value; XCTFail("Old account must not publish sent after removal") }
        catch is CancellationError {} catch { XCTFail("Expected cancellation") }
    }

    func testExactAckMarkerPreventsBodyBasedFalseConfirmationAndHistoricalFakeSentDecodesPending() throws {
        var local = ChatMessage(id: "local", roomId: "room", senderId: "own", senderDisplayName: "Synthetic",
                                body: "same text", sentAt: .now, deliveryState: .pending, isOwnMessage: true)
        local.requiresExactMatrixAcknowledgement = true
        var remote = local; remote.id = "$other"; remote.deliveryState = .sent
        XCTAssertEqual(ChatMessage.removingSupersededLocalEchoes(from: [local, remote]).count, 2)
        local.matrixTransactionID = "full-original-transaction"; remote.matrixTransactionID = "different"
        XCTAssertEqual(ChatMessage.removingSupersededLocalEchoes(from: [local, remote]).count, 2)
        remote.matrixTransactionID = local.matrixTransactionID
        XCTAssertEqual(ChatMessage.removingSupersededLocalEchoes(from: [local, remote]).map(\.id), ["$other"])
        var historical = local; historical.id = "matrix-unconfirmed-old"; historical.deliveryState = .sent
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(historical))
        XCTAssertEqual(decoded.deliveryState, .pending)
    }

    func testTextReplyLocationAndSafetyDraftsNeedExactConfirmation() async throws {
        let (bootstrap, conversation) = try await setup()
        let drafts = [OutgoingMessageDraft(body: "text"),
            OutgoingMessageDraft(body: "reply", replyTo: MessageReplyReference(messageId: "$reply", senderDisplayName: "Synthetic", bodyPreview: "Synthetic")),
            OutgoingMessageDraft(body: "location", attachments: [MessageAttachment(id: "location", kind: .location, title: "Synthetic", location: GeoPoint(lat: 50, lon: 14))]),
            OutgoingMessageDraft(body: "safety", attachments: [MessageAttachment(id: "safety", kind: .safetyStatus, title: "Synthetic")])]
        for draft in drafts {
            let live = DraftSubmissionMessaging(confirmation: .pending)
            let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
            try await wrapper.configure(with: bootstrap)
            let message = try await wrapper.sendMessage(draft, to: conversation)
            XCTAssertEqual(message.deliveryState, .pending)
            let calls = await live.queuedParts
            XCTAssertEqual(calls, [0])
        }
    }
}

private actor DraftSubmissionMessaging: MessagingClientProtocol, MatrixDraftSending {
    enum Confirmation: Sendable { case pending, pendingWithTrustFailure, confirmed, throwBeforeReceipt, secondPartPending }
    static let fullTransactionID = "synthetic-SDK-tx-with-special_chars+and-much-more-than-forty-eight-characters-EXACT"
    let confirmation: Confirmation
    private(set) var queuedParts: [Int] = []
    private var acknowledgements: [String: String] = [:]
    private var liveMessages: [ChatMessage] = []
    func setLiveMessages(_ messages: [ChatMessage]) { liveMessages = messages }
    init(confirmation: Confirmation) { self.confirmation = confirmation }
    func configure(with bootstrap: MessagingBootstrap) {}
    func messages(for conversation: Conversation) -> [ChatMessage] { liveMessages }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { XCTFail("Untracked path must not be used"); throw CancellationError() }
    func confirm(transaction: String, event: String) { acknowledgements[transaction] = event }
    func reconcileMatrixDraft(_ submission: MatrixDraftSubmission, in conversation: Conversation) -> MatrixDraftSubmission {
        var result = submission
        for (transaction, event) in acknowledgements { result.confirm(transactionID: transaction, eventID: event) }
        return result
    }
    func submitMatrixDraft(_ draft: OutgoingMessageDraft, to conversation: Conversation,
                           submission: MatrixDraftSubmission,
                           persist: @escaping @Sendable (MatrixDraftSubmission) async throws -> Void) async throws -> MatrixDraftSubmission {
        var state = submission
        guard state.canResume else { return state }
        for index in state.parts.indices where state.parts[index].state == .notStarted {
            state.parts[index].state = .queuing
            try await persist(state)
            queuedParts.append(index)
            if confirmation == .throwBeforeReceipt { throw URLError(.timedOut) }
            state.parts[index].state = .queued
            state.parts[index].transactionID = index == 0 ? Self.fullTransactionID : Self.fullTransactionID + "-part-" + String(index)
            try await persist(state)
            if confirmation == .pendingWithTrustFailure {
                state.failure = .untrustedDevices; try await persist(state); return state
            }
            if confirmation == .pending || (confirmation == .secondPartPending && index == 1) { return state }
            state.confirm(transactionID: state.parts[index].transactionID!, eventID: "$ack-" + String(index))
            try await persist(state)
        }
        return state
    }
}

private actor PausingRemovalOutbox: MessageOutboxStoring {
    private let store: any MessageOutboxStoring = InMemoryMessageOutbox()
    private var started = false
        private var release: CheckedContinuation<Void, Never>?
    func waitUntilRemoving() async -> Bool {
        for _ in 0..<100 {
            if started { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }
    func resumeRemoval() { release?.resume(); release = nil }
    func enqueue(_ message: ChatMessage, conversation: Conversation) async throws { try await store.enqueue(message, conversation: conversation) }
    func enqueueMatrixDraft(_ message: ChatMessage, conversation: Conversation, submission: MatrixDraftSubmission) async throws {
        try await store.enqueueMatrixDraft(message, conversation: conversation, submission: submission)
    }
    func updateMatrixSubmission(_ submission: MatrixDraftSubmission, messageId: String, conversationId: String) async throws {
        try await store.updateMatrixSubmission(submission, messageId: messageId, conversationId: conversationId)
    }
    func pendingMessages(for conversationId: String) async throws -> [ChatMessage] { try await store.pendingMessages(for: conversationId) }
    func pendingRecords(for conversationId: String) async throws -> [PendingMessageRecord] { try await store.pendingRecords(for: conversationId) }
    func pendingMessageCount() async throws -> Int { try await store.pendingMessageCount() }
    func recordAttempt(messageId: String, conversationId: String, error: String, retryAfter: TimeInterval) async throws {
        try await store.recordAttempt(messageId: messageId, conversationId: conversationId, error: error, retryAfter: retryAfter)
    }
    func removeMessage(id: String, conversationId: String) async throws {
        started = true
        await withCheckedContinuation { release = $0 }
        try await store.removeMessage(id: id, conversationId: conversationId)
    }
    func discardPendingMessages(for conversationId: String) async throws -> Int { try await store.discardPendingMessages(for: conversationId) }
    func clear() async throws { try await store.clear() }
}
