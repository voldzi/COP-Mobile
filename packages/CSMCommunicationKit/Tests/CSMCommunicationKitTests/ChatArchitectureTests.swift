import Foundation
import XCTest

@testable import CSMCommunicationKit

@MainActor
final class ChatArchitectureTests: XCTestCase {
    func testMatrixDeviceIdentityIsStableInsideOneInstallation() {
        let actor = AuthenticatedActor(
            subjectId: "user-1",
            username: "jiri",
            displayName: "Jiří",
            roles: ["user"]
        )

        let first = CommunicationModel.matrixDeviceId(
            actor: actor,
            deviceRegistration: nil,
            posture: nil,
            installationSeed: "installation-a"
        )
        let second = CommunicationModel.matrixDeviceId(
            actor: actor,
            deviceRegistration: nil,
            posture: nil,
            installationSeed: "installation-a"
        )

        XCTAssertEqual(first, second)
    }

    func testMatrixDeviceIdentityChangesAfterApplicationReinstall() {
        let actor = AuthenticatedActor(
            subjectId: "user-1",
            username: "jiri",
            displayName: "Jiří",
            roles: ["user"]
        )

        let original = CommunicationModel.matrixDeviceId(
            actor: actor,
            deviceRegistration: nil,
            posture: nil,
            installationSeed: "installation-a"
        )
        let reinstalled = CommunicationModel.matrixDeviceId(
            actor: actor,
            deviceRegistration: nil,
            posture: nil,
            installationSeed: "installation-b"
        )

        XCTAssertNotEqual(original, reinstalled)
    }

    func testReducerDeduplicatesAndKeepsBoundedWindow() {
        var state = TimelineState(conversationID: "room")
        let messages = (0..<10_000).map { index in
            makeMessage(id: "m-\(index)", offset: TimeInterval(index))
        }

        TimelineReducer.reduce(
            &state,
            action: .replaceRemote(messages + [messages[9_999]], hasEarlier: true),
            policy: .mobile
        )

        XCTAssertEqual(state.messages.count, TimelineWindowPolicy.mobile.retainedMessageLimit)
        XCTAssertEqual(state.messages.first?.id, "m-9500")
        XCTAssertEqual(state.messages.last?.id, "m-9999")
        XCTAssertEqual(Set(state.messages.map(\.id)).count, state.messages.count)
    }

    func testReducerUsesSingleUpsertPathForConfirmationAndReaction() {
        var state = TimelineState(conversationID: "room")
        var local = makeMessage(id: "txn-1", offset: 0, state: .pending)
        TimelineReducer.reduce(&state, action: .upsert(local))

        local.deliveryState = .sent
        local.reactions = [MessageReaction(emoji: "👍", count: 1, reactedByMe: true)]
        TimelineReducer.reduce(&state, action: .upsert(local))

        XCTAssertEqual(state.messages.count, 1)
        XCTAssertEqual(state.messages[0].deliveryState, .sent)
        XCTAssertEqual(state.messages[0].reactions.first?.emoji, "👍")
    }

    func testBurstOfOneHundredEventsLosesNothingAndCreatesNoDuplicates() {
        var state = TimelineState(conversationID: "room")
        for index in 0..<100 {
            TimelineReducer.reduce(
                &state,
                action: .upsert(makeMessage(id: "burst-\(index)", offset: TimeInterval(index)))
            )
        }
        for index in 0..<100 {
            TimelineReducer.reduce(
                &state,
                action: .upsert(makeMessage(id: "burst-\(index)", offset: TimeInterval(index)))
            )
        }

        XCTAssertEqual(state.messages.count, 100)
        XCTAssertEqual(Set(state.messages.map(\.id)).count, 100)
    }

    func testEarlierPagingShiftsBoundedWindowAndCanReturnToLatest() {
        var state = TimelineState(conversationID: "room")
        let latest = (500..<1_000).map { index in
            makeMessage(id: "m-\(index)", offset: TimeInterval(index))
        }
        let earlier = (0..<500).map { index in
            makeMessage(id: "m-\(index)", offset: TimeInterval(index))
        }
        TimelineReducer.reduce(&state, action: .replaceRemote(latest, hasEarlier: true))

        TimelineReducer.reduce(&state, action: .prependEarlier(earlier, hasEarlier: false))

        XCTAssertEqual(state.messages.count, TimelineWindowPolicy.mobile.retainedMessageLimit)
        XCTAssertEqual(state.messages.first?.id, "m-0")
        XCTAssertEqual(state.messages.last?.id, "m-499")
        XCTAssertFalse(state.hasEarlierMessages)
        XCTAssertTrue(state.hasLaterMessages)

        TimelineReducer.reduce(&state, action: .returnToLatest)
        TimelineReducer.reduce(&state, action: .replaceRemote(latest, hasEarlier: true))

        XCTAssertFalse(state.hasLaterMessages)
        XCTAssertEqual(state.messages.first?.id, "m-500")
        XCTAssertEqual(state.messages.last?.id, "m-999")
    }

    func testLiveRefreshDoesNotPullReaderAwayFromOlderWindow() {
        var state = TimelineState(conversationID: "room")
        let latest = (500..<1_000).map { index in
            makeMessage(id: "m-\(index)", offset: TimeInterval(index))
        }
        let earlier = (0..<500).map { index in
            makeMessage(id: "m-\(index)", offset: TimeInterval(index))
        }
        TimelineReducer.reduce(&state, action: .replaceRemote(latest, hasEarlier: true))
        TimelineReducer.reduce(&state, action: .prependEarlier(earlier, hasEarlier: false))

        TimelineReducer.reduce(
            &state,
            action: .replaceRemote(
                latest + [makeMessage(id: "m-1000", offset: 1_000)],
                hasEarlier: true
            )
        )

        XCTAssertTrue(state.hasLaterMessages)
        XCTAssertEqual(state.messages.first?.id, "m-0")
        XCTAssertEqual(state.messages.last?.id, "m-499")
    }

    func testTenThousandMessageReductionStaysWithinCachedOpenBudget() {
        let messages = (0..<10_000).map { index in
            makeMessage(id: "perf-\(index)", offset: TimeInterval(index))
        }
        var state = TimelineState(conversationID: "room")
        let clock = ContinuousClock()
        let start = clock.now

        TimelineReducer.reduce(
            &state,
            action: .replaceRemote(messages, hasEarlier: true),
            policy: .mobile
        )

        let elapsed = start.duration(to: clock.now)
        XCTAssertLessThan(
            milliseconds(elapsed),
            ChatPerformanceBudget.cachedConversationOpenMilliseconds,
            "10k fixture exceeded the cached-conversation release budget"
        )
    }

    func testTimelineFixturesStayBoundedAtAllReleaseSizes() {
        for count in [1, 100, 1_000, 10_000] {
            var state = TimelineState(conversationID: "room")
            let messages = (0..<count).map { index in
                makeMessage(id: "fixture-\(count)-\(index)", offset: TimeInterval(index))
            }

            TimelineReducer.reduce(
                &state,
                action: .replaceRemote(messages, hasEarlier: count > TimelineWindowPolicy.mobile.retainedMessageLimit),
                policy: .mobile
            )

            XCTAssertEqual(
                state.messages.count,
                min(count, TimelineWindowPolicy.mobile.retainedMessageLimit),
                "Unexpected retained window for \(count)-message fixture"
            )
            XCTAssertEqual(Set(state.messages.map(\.id)).count, state.messages.count)
        }
    }

    func testTimelinePresentationP95StaysWithinInteractionBudget() {
        let messages = (0..<TimelineWindowPolicy.mobile.retainedMessageLimit).map { index in
            makeMessage(
                id: "presentation-\(index)",
                body: index.isMultiple(of: 5) ? "Bouřka u Vrbna" : "Běžná zpráva",
                offset: TimeInterval(index)
            )
        }
        let samples = (0..<40).map { _ in
            let clock = ContinuousClock()
            let start = clock.now
            _ = ChatTimelinePresentation.make(
                messages: messages,
                voiceCallMessages: [],
                searchText: "bourka"
            )
            return milliseconds(start.duration(to: clock.now))
        }

        XCTAssertLessThan(
            percentile95(samples),
            ChatPerformanceBudget.interactionMilliseconds,
            "Timeline presentation exceeded the p95 interaction release budget"
        )
    }

    func testSearchIndexHandlesDiacriticsAndConversationBoundary() async {
        let index = SearchIndex()
        await index.replace(
            [
                makeMessage(id: "storm", body: "Silná bouřka u Vrbna", offset: 1),
                makeMessage(id: "water", body: "Stav vody", offset: 2)
            ],
            conversationID: "room-a"
        )

        let matches = await index.search("bourka", conversationID: "room-a", limit: 10)
        let otherRoomMatches = await index.search("bourka", conversationID: "room-b", limit: 10)

        XCTAssertEqual(matches, ["storm"])
        XCTAssertTrue(otherRoomMatches.isEmpty)
    }

    func testEncryptedHistoryIsPagedPerConversation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-history-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = EncryptedMessageHistoryStore(
            keychain: KeychainCredentialStore(),
            maxMessagesPerConversation: 1_000,
            defaultPageSize: 20,
            rootDirectory: root,
            fixedKeyData: Data(repeating: 7, count: 32)
        )
        let messages = (0..<100).map { index in
            makeMessage(id: "history-\(index)", offset: TimeInterval(index))
        }
        try await store.saveMessages(messages, conversationId: "room")

        let latest = try await store.messagePage(for: "room", before: nil, limit: 20)
        let earlier = try await store.messagePage(
            for: "room",
            before: latest.messages.first?.sentAt,
            limit: 20
        )

        XCTAssertEqual(latest.messages.count, 20)
        XCTAssertTrue(latest.hasEarlier)
        XCTAssertEqual(latest.messages.first?.id, "history-80")
        XCTAssertEqual(earlier.messages.first?.id, "history-60")
    }

    func testFileBackedMediaPipelineDoesNotEmbedPayload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-media-test-\(UUID().uuidString)", isDirectory: true)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-media-source-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source)
        }
        try Data(repeating: 4, count: 1_024).write(to: source)
        let pipeline = MediaPipelineActor(rootDirectory: root)

        let attachment = try await pipeline.prepare(
            sourceURL: source,
            kind: .document,
            title: "test.bin",
            mimeType: "application/octet-stream"
        )

        XCTAssertNil(attachment.payloadData)
        XCTAssertEqual(attachment.byteCount, 1_024)
        XCTAssertNotNil(attachment.localFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.localFileURL!.path))
    }

    func testEncryptedOutboxSurvivesRestartAndDeduplicatesStableTransaction() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-outbox-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixedKey = Data(repeating: 9, count: 32)
        let firstStore = EncryptedMessageOutbox(
            keychain: KeychainCredentialStore(),
            rootDirectory: root,
            fixedKeyData: fixedKey
        )
        let message = makeMessage(id: "offline-transaction-1", offset: 1, state: .pending)
        let conversation = makeConversation(id: "room")

        try await firstStore.enqueue(message, conversation: conversation)
        try await firstStore.enqueue(message, conversation: conversation)
        let firstCount = try await firstStore.pendingMessageCount()
        XCTAssertEqual(firstCount, 1)

        let restoredStore = EncryptedMessageOutbox(
            keychain: KeychainCredentialStore(),
            rootDirectory: root,
            fixedKeyData: fixedKey
        )
        let restored = try await restoredStore.pendingRecords(for: conversation.conversationId)

        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.message.id, message.id)
        XCTAssertEqual(restored.first?.stableTransactionId, message.id)
    }

    func testOfflineClientReturnsBoundedCacheWithoutWaitingForLiveTransport() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-cache-fast-path-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let keychain = KeychainCredentialStore()
        let history = EncryptedMessageHistoryStore(
            keychain: keychain,
            maxMessagesPerConversation: 1_000,
            defaultPageSize: 20,
            rootDirectory: root,
            fixedKeyData: Data(repeating: 3, count: 32)
        )
        let outbox = EncryptedMessageOutbox(
            keychain: keychain,
            rootDirectory: root,
            fixedKeyData: Data(repeating: 5, count: 32)
        )
        let conversation = makeConversation(id: "room")
        let stored = (0..<40).map { index in
            makeMessage(id: "cached-\(index)", offset: TimeInterval(index))
        }
        let pending = makeMessage(id: "pending-local", offset: 100, state: .pending)
        try await history.saveMessages(stored, conversationId: conversation.conversationId)
        try await outbox.enqueue(pending, conversation: conversation)
        let client = OfflineFirstMessagingClient(
            liveClient: PreviewMessagingClient(),
            outbox: outbox,
            history: history
        )

        let page = try await client.cachedMessagePage(for: conversation, limit: 20)

        XCTAssertTrue(page.hasEarlier)
        XCTAssertEqual(page.messages.count, 21)
        XCTAssertEqual(page.messages.last?.id, pending.id)
        XCTAssertEqual(Set(page.messages.map(\.id)).count, page.messages.count)
    }

    private func makeMessage(
        id: String,
        body: String = "Zpráva",
        offset: TimeInterval,
        state: MessageDeliveryState = .sent
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            roomId: "room",
            senderId: "sender",
            senderDisplayName: "Sender",
            body: body,
            sentAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            deliveryState: state,
            isOwnMessage: false
        )
    }

    private func makeConversation(id: String) -> Conversation {
        Conversation(
            conversationId: id,
            title: "Test",
            type: .direct,
            status: "active",
            encrypted: true,
            e2eeRequired: true,
            memberCount: 2,
            mapLinkCount: 0,
            members: [],
            mapLinks: [],
            updatedAt: .now
        )
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 +
            Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private func percentile95(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.up)) - 1)
        return sorted[index]
    }
}
