import Foundation
import XCTest
import MatrixRustSDK
@testable import CSMCommunicationKit

final class MessageDecryptionFailureTests: XCTestCase {
    func testPinnedSDKCausesKeepMissingKeysSeparateFromTrustAndHistory() {
        let cases: [(UtdCause, MessageDecryptionFailure)] = [
            (.unknown, .missingKeys), (.sentBeforeWeJoined, .sentBeforeJoining),
            (.verificationViolation, .senderIdentityChanged), (.unsignedDevice, .senderVerificationRequired),
            (.unknownDevice, .unknownSenderDevice), (.historicalMessageAndBackupIsDisabled, .historicalKeysUnavailable),
            (.withheldForUnverifiedOrInsecureDevice, .recipientVerificationRequired),
            (.historicalMessageAndDeviceIsUnverified, .recipientVerificationRequired), (.withheldBySender, .withheldBySender)
        ]
        for (cause, expected) in cases {
            let result = MatrixRustE2EEMessagingClient.decryptionFailure(for: .megolmV1AesSha2(sessionId: "synthetic-session", cause: cause))
            XCTAssertEqual(result, expected)
            XCTAssertFalse(result.userMessage.contains("synthetic-session"))
            XCTAssertFalse(result.userMessage.contains("neodesláno"))
        }
    }

    func testRetryIsBoundedPerRoomAndNeverRetriesTrustOrHistoricalFailures() {
        var gate = MatrixDecryptionRetryGate()
        let now = Date(timeIntervalSince1970: 1000)
        let messages: [EncryptedMessage] = [
            .megolmV1AesSha2(sessionId: "retry", cause: .unknown),
            .megolmV1AesSha2(sessionId: "retry", cause: .unknown),
            .megolmV1AesSha2(sessionId: "trust", cause: .withheldForUnverifiedOrInsecureDevice),
            .megolmV1AesSha2(sessionId: "history", cause: .historicalMessageAndBackupIsDisabled)
        ]
        XCTAssertEqual(gate.sessionsToRetry(messages, in: "!room", now: now), ["retry"])
        XCTAssertTrue(gate.sessionsToRetry(messages, in: "!room", now: now.addingTimeInterval(29)).isEmpty)
        XCTAssertEqual(gate.sessionsToRetry(messages, in: "!other", now: now), ["retry"])
        XCTAssertEqual(gate.sessionsToRetry(messages, in: "!room", now: now.addingTimeInterval(30)), ["retry"])
        let many = (0..<100).map { EncryptedMessage.megolmV1AesSha2(sessionId: "session-\($0)", cause: .unknown) }
        XCTAssertEqual(gate.sessionsToRetry(many, in: "!large", now: now).count, 50)
    }

    func testTypedReceivedContentFailureSurvivesStorageWithoutBecomingAnOutgoingFailure() throws {
        let message = ChatMessage(id: "$received", roomId: "!room", senderId: "@peer", senderDisplayName: "Synthetic",
            body: MessageDecryptionFailure.recipientVerificationRequired.userMessage, sentAt: .now,
            deliveryState: .failed, isOwnMessage: false, decryptionFailure: .recipientVerificationRequired)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.decryptionFailure, .recipientVerificationRequired)
        XCTAssertFalse(decoded.isOwnMessage)
    }
}
