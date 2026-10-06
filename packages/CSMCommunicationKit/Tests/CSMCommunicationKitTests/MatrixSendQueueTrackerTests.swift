import XCTest
@testable import CSMCommunicationKit
#if canImport(MatrixRustSDK) && !os(watchOS)
import MatrixRustSDK

final class MatrixSendQueueTrackerTests: XCTestCase {
    func testPinnedImmediateReplayAndDelayedDuplicateCannotBecomeFreshSend() {
        let tracker = MatrixRustSendQueueTracker(roomId: "synthetic-room")
        // The pinned native implementation delivers this replay synchronously
        // before returning the subscription handle. Capture that boundary.
        tracker.onUpdate(update: .newLocalEvent(transactionId: "existing-upload"))
        tracker.onUpdate(update: .newLocalEvent(transactionId: "existing-text"))
        let baseline = tracker.snapshotTransactionIds()
        tracker.onUpdate(update: .newLocalEvent(transactionId: "existing-upload"))
        tracker.onUpdate(update: .sentEvent(transactionId: "existing-text", eventId: "$old"))
        XCTAssertNil(tracker.singleNewTransactionId(excluding: baseline))
        let exact = "synthetic-full-transaction-id-with-special_chars+and-over-forty-eight-characters"
        tracker.onUpdate(update: .newLocalEvent(transactionId: exact))
        tracker.onUpdate(update: .sentEvent(transactionId: exact, eventId: "$exact"))
        XCTAssertEqual(tracker.singleNewTransactionId(excluding: baseline), exact)
        XCTAssertEqual(tracker.sentEventId(for: exact), "$exact")
        XCTAssertNil(tracker.sentEventId(for: String(exact.prefix(48))))
    }
    func testAmbiguousFreshTransactionsNeverChooseAnAcknowledgement() {
        let tracker = MatrixRustSendQueueTracker(roomId: "synthetic-room")
        let baseline = tracker.snapshotTransactionIds()
        tracker.onUpdate(update: .newLocalEvent(transactionId: "first"))
        tracker.onUpdate(update: .newLocalEvent(transactionId: "second"))
        tracker.onUpdate(update: .sentEvent(transactionId: "second", eventId: "$other"))
        XCTAssertNil(tracker.singleNewTransactionId(excluding: baseline))
        XCTAssertNil(tracker.sentEventId(for: "first"))
        tracker.onUpdate(roomId: "another-room", update: .sentEvent(transactionId: "first", eventId: "$foreign"))
        XCTAssertNil(tracker.sentEventId(for: "first"))
    }
}
#endif
