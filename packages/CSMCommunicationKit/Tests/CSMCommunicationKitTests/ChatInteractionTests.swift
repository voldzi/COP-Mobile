import CoreGraphics
import XCTest

@testable import CSMCommunicationKit

final class ChatInteractionTests: XCTestCase {
    func testReplySwipeRequiresIntentionalRightwardHorizontalMovement() {
        XCTAssertTrue(MessageReplySwipePolicy.shouldReply(for: CGSize(width: 80, height: 8)))
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(for: CGSize(width: -80, height: 8)))
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(for: CGSize(width: 80, height: 72)))
        XCTAssertFalse(MessageReplySwipePolicy.shouldReply(for: CGSize(width: 60, height: 0)))
    }

    func testReplySwipeDoesNotClaimBackDirectionOrVerticalScroll() {
        XCTAssertEqual(
            MessageReplySwipePolicy.dragOffset(for: CGSize(width: -90, height: 0)),
            0
        )
        XCTAssertEqual(
            MessageReplySwipePolicy.dragOffset(for: CGSize(width: 40, height: 60)),
            0
        )
        XCTAssertEqual(
            MessageReplySwipePolicy.dragOffset(for: CGSize(width: 120, height: 2)),
            MessageReplySwipePolicy.maximumOffset
        )
    }

    func testScrollFollowsOnlyInitialBottomOrOwnMessage() {
        XCTAssertTrue(
            TimelineScrollPolicy.shouldFollowLatest(
                previousVisibleMessageCount: 0,
                currentVisibleMessageCount: 1,
                isAtBottom: false,
                lastMessageIsOwn: false
            )
        )
        XCTAssertTrue(
            TimelineScrollPolicy.shouldFollowLatest(
                previousVisibleMessageCount: 10,
                currentVisibleMessageCount: 11,
                isAtBottom: true,
                lastMessageIsOwn: false
            )
        )
        XCTAssertTrue(
            TimelineScrollPolicy.shouldFollowLatest(
                previousVisibleMessageCount: 10,
                currentVisibleMessageCount: 11,
                isAtBottom: false,
                lastMessageIsOwn: true
            )
        )
        XCTAssertFalse(
            TimelineScrollPolicy.shouldFollowLatest(
                previousVisibleMessageCount: 10,
                currentVisibleMessageCount: 11,
                isAtBottom: false,
                lastMessageIsOwn: false
            )
        )
    }

    func testTimelinePresentationSortsAndFiltersOnceForRendering() {
        let later = makeMessage(id: "later", sender: "peer", body: "Bouřka", offset: 60)
        let earlier = makeMessage(id: "earlier", sender: "peer", body: "Voda", offset: 0)
        let voice = makeMessage(id: "voice", sender: "system", body: "Nepřijatý hovor", offset: 30)

        let all = ChatTimelinePresentation.make(
            messages: [later, earlier],
            voiceCallMessages: [voice],
            searchText: ""
        )
        XCTAssertEqual(all.messages.map(\.id), ["earlier", "voice", "later"])
        XCTAssertEqual(all.rows.map(\.id), ["earlier", "voice", "later"])

        let filtered = ChatTimelinePresentation.make(
            messages: [later, earlier],
            voiceCallMessages: [voice],
            searchText: "bouř"
        )
        XCTAssertEqual(filtered.messages.map(\.id), ["later"])
        XCTAssertEqual(filtered.searchableMessages.map(\.id), ["later"])
    }

    func testTimelineGroupsOnlyConsecutiveMessagesFromSameSender() {
        let first = makeMessage(id: "1", sender: "peer", body: "A", offset: 0)
        let second = makeMessage(id: "2", sender: "peer", body: "B", offset: 20)
        let third = makeMessage(id: "3", sender: "other", body: "C", offset: 30)

        let rows = TimelineMessageRow.makeRows(from: [first, second, third])

        XCTAssertEqual(rows.map(\.position), [.first, .last, .single])
        XCTAssertTrue(rows[0].showsSender)
        XCTAssertFalse(rows[0].showsAvatar)
        XCTAssertFalse(rows[1].showsSender)
        XCTAssertTrue(rows[1].showsAvatar)
    }

    func testLiveLocationMetadataPreservesDurationAndLatestPointState() throws {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let metadata = LiveLocationShareMetadata(
            isLive: true,
            startedAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(60 * 60),
            updatedAt: startedAt.addingTimeInterval(30)
        )
        let attachment = MessageAttachment(
            kind: .location,
            title: "Živá poloha",
            durationSeconds: 60 * 60,
            location: GeoPoint(
                lat: 50.08,
                lon: 14.42,
                accuracyM: 12,
                source: "test"
            ),
            liveLocationShare: metadata,
            localOnly: false
        )

        let restored = try JSONDecoder().decode(
            MessageAttachment.self,
            from: JSONEncoder().encode(attachment)
        )

        XCTAssertEqual(restored.liveLocationShare?.durationSeconds, 60 * 60)
        XCTAssertEqual(restored.location?.accuracyM, 12)
        XCTAssertEqual(restored.liveLocationShare?.updatedAt, startedAt.addingTimeInterval(30))
    }

    func testStaticLocationRemainsBackwardCompatibleWithoutLiveMetadata() throws {
        let attachment = MessageAttachment(
            kind: .location,
            title: "Moje poloha",
            location: GeoPoint(lat: 50.08, lon: 14.42, accuracyM: nil, source: "test")
        )

        let restored = try JSONDecoder().decode(
            MessageAttachment.self,
            from: JSONEncoder().encode(attachment)
        )

        XCTAssertNil(restored.liveLocationShare)
    }

    private func makeMessage(
        id: String,
        sender: String,
        body: String,
        offset: TimeInterval
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            roomId: "room",
            senderId: sender,
            senderDisplayName: sender,
            body: body,
            sentAt: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            deliveryState: .sent,
            isOwnMessage: false
        )
    }
}
