import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class MessagingStreamLifecycleTests: XCTestCase {
    func testSameScopeTokenRefreshReconnectsExistingWrapperStream() async throws {
        let live = StreamLifecycleMessaging()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        var bootstrap = try await PreviewCopAPIClient().messagingBootstrap(deviceId: "synthetic-device")
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        bootstrap.accessToken = "synthetic-token-a"
        try await wrapper.configure(with: bootstrap)
        let stream = try await wrapper.messageSnapshots(for: conversation)
        let sink = StreamLifecycleSink()
        let task = Task { for await value in stream { await sink.append(value) } }
        defer { task.cancel() }
        try await waitUntil { await live.activeCount == 1 }
        await live.emit(id: "$before", conversation: conversation)
        try await waitUntil { await sink.ids.contains("$before") }
        bootstrap.accessToken = "synthetic-token-b"
        try await wrapper.configure(with: bootstrap)
        try await waitUntil { await live.subscriptionCount == 2 }
        await live.emit(id: "$after", conversation: conversation)
        try await waitUntil { await sink.ids.contains("$after") }
        let configured = await live.configurationCount
        let active = await live.activeCount
        XCTAssertEqual(configured, 2, "Reconnect must not install another Rust client.")
        XCTAssertEqual(active, 1)
    }

    func testAccountSwitchFinishesOldWrapperStreamWithoutPublishingNewAccount() async throws {
        let live = StreamLifecycleMessaging()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        var bootstrap = try await PreviewCopAPIClient().messagingBootstrap(deviceId: "synthetic-device")
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        bootstrap.userId = "@a:matrix.test"
        try await wrapper.configure(with: bootstrap)
        let stream = try await wrapper.messageSnapshots(for: conversation)
        let sink = StreamLifecycleSink()
        let task = Task {
            for await value in stream { await sink.append(value) }
            await sink.finish()
        }
        defer { task.cancel() }
        try await waitUntil { await live.activeCount == 1 }
        bootstrap.userId = "@b:matrix.test"
        try await wrapper.configure(with: bootstrap)
        try await waitUntil { await sink.finished }
        await live.emit(id: "$foreign", conversation: conversation)
        let ids = await sink.ids
        XCTAssertFalse(ids.contains("$foreign"))
        let subscriptions = await live.subscriptionCount
        XCTAssertEqual(subscriptions, 1, "The old account must not subscribe to the new account.")
    }

    #if canImport(MatrixRustSDK) && !os(watchOS)
    func testRustTimelineInvalidationFinishesConsumersAndRejectsLateObservers() async {
        let cache = MatrixRustTimelineCache()
        let firstEnded = expectation(description: "old stream ended")
        let lateEnded = expectation(description: "late stream ended")
        _ = cache.addObserver({ _ in }, onInvalidation: { firstEnded.fulfill() })
        cache.invalidate()
        cache.invalidate()
        _ = cache.addObserver({ _ in XCTFail("Invalidated SDK cache must not emit snapshots") },
                              onInvalidation: { lateEnded.fulfill() })
        cache.onUpdate(diff: [])
        await fulfillment(of: [firstEnded, lateEnded], timeout: 1)
    }
    #endif

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Stream lifecycle did not converge within one second")
        throw CancellationError()
    }
}

actor StreamLifecycleSink {
    private(set) var ids: Set<String> = []
    private(set) var finished = false
    func append(_ messages: [ChatMessage]) { ids.formUnion(messages.map(\.id)) }
    func finish() { finished = true }
}

actor StreamLifecycleMessaging: MessagingSessionInvalidating, MessagingClientProtocol, MessagingLiveMessageStreaming, MessagingLifecycleControlling {
    private var continuations: [UUID: AsyncStream<[ChatMessage]>.Continuation] = [:]
    private(set) var subscriptionCount = 0
    private(set) var configurationCount = 0
    private var nextPause: StreamConfigurationPause?
    private var invalidationRevision = 0
    private(set) var suspendCount = 0
    private(set) var pusherCount = 0
    func armConfigurationPause(_ pause: StreamConfigurationPause) { nextPause = pause }
    let finishOnConfigure: Bool
    init(finishOnConfigure: Bool = true) { self.finishOnConfigure = finishOnConfigure }
    var activeCount: Int { continuations.count }
    func configure(with bootstrap: MessagingBootstrap) async throws {
        configurationCount += 1
        let configuration = configurationCount
        let revision = invalidationRevision
        if let pause = nextPause { nextPause = nil; await pause.enterAndWait() }
        guard revision == invalidationRevision else { throw CancellationError() }
        if configuration != configurationCount { return }
        if finishOnConfigure {
            let old = continuations.values
            continuations.removeAll()
            old.forEach { $0.finish() }
        }
    }
    func messageSnapshots(for conversation: Conversation) -> AsyncStream<[ChatMessage]> {
        let id = UUID()
        subscriptionCount += 1
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[id] = continuation
            continuation.yield([])
            continuation.onTermination = { _ in Task { await self.remove(id) } }
        }
    }
    private func remove(_ id: UUID) { continuations.removeValue(forKey: id) }
    func emit(id: String, conversation: Conversation) {
        let message = ChatMessage(id: id, roomId: conversation.conversationId,
            senderId: "synthetic-peer", senderDisplayName: "Synthetic", body: "Synthetic event",
            sentAt: .now, deliveryState: .sent, isOwnMessage: false)
        continuations.values.forEach { $0.yield([message]) }
    }
    func messages(for conversation: Conversation) -> [ChatMessage] { [] }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { throw CancellationError() }
    func resumeMessaging() {}
    func suspendMessaging() { suspendCount += 1; continuations.values.forEach { $0.finish() }; continuations.removeAll() }
    func invalidateMessagingSession() { invalidationRevision += 1; suspendMessaging() }
    func registerPusher(pushKey: String, pushGatewayURL: URL) { pusherCount += 1 }
}

actor StreamConfigurationPause {
    private var entered = false
    private var entry: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entry = $0 }
    }
    func enterAndWait() async {
        entered = true; entry?.resume(); entry = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}
