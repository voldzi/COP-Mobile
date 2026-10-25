import Foundation
import XCTest
import MatrixRustSDK
@testable import CSMCommunicationKit

final class ChatStatusSummaryTests: XCTestCase {
    private var idle: ChatDeliveryPresentation {
        .init(isVisible: false, title: "", subtitle: "", detail: "", technicalDetail: nil,
              systemImage: "lock.shield", canSync: false, pendingCount: 0, syncStatus: "idle", syncStatusText: nil, severity: .waiting)
    }
    private func recovery(verification: ChatDeviceVerification = .unknown) -> MatrixEncryptionRecoveryStatus {
        .init(supported: true, keyBackupExists: true, keyBackupEnabled: true, recoveryEnabled: false,
              keyBackupUsable: true, matrixRustCompatible: false, needsSetup: false, needsRecovery: false,
              backupState: "enabled", recoveryState: "disabled", detail: nil, deviceVerification: verification)
    }

    func testScreenshotBackupCompatibilityWarningDoesNotProveChatOrDeviceVerification() {
        let status = recovery()
        XCTAssertTrue(status.hasMatrixRustCompatibilityWarning)
        XCTAssertFalse(status.requiresUserAction)
        XCTAssertEqual(status.deviceVerification, .unknown)
        XCTAssertFalse(status.title.contains("Chat funguje"))
        XCTAssertFalse(status.title.contains("Chat works"))
        let summary = ChatStatusSummary.make(delivery: idle, unreadableMessageCount: 1, verification: status.deviceVerification)
        XCTAssertTrue(summary.needsAttention)
        XCTAssertNotEqual(summary.title, status.title)
        XCTAssertNotEqual(summary.subtitle, status.userMessage)
    }

    func testVerifiedDeviceDoesNotHideUnreadableContentOrSendingFailure() {
        let unreadable = ChatStatusSummary.make(delivery: idle, unreadableMessageCount: 2, verification: .verified)
        XCTAssertTrue(unreadable.needsAttention)
        var failure = idle
        failure.isVisible = true; failure.title = "Synthetic send unavailable"; failure.severity = .blocked
        let result = ChatStatusSummary.make(delivery: failure, unreadableMessageCount: 0, verification: .verified)
        XCTAssertEqual(result.title, failure.title)
        XCTAssertTrue(result.needsAttention)
    }

    func testDeviceVerificationComesFromTheActualSDKStateAndDoesNotGrantSending() {
        XCTAssertEqual(MatrixRustE2EEMessagingClient.deviceVerification(.unknown), .unknown)
        XCTAssertEqual(MatrixRustE2EEMessagingClient.deviceVerification(.verified), .verified)
        XCTAssertEqual(MatrixRustE2EEMessagingClient.deviceVerification(.unverified), .unverified)
        let unverified = recovery(verification: .unverified)
        XCTAssertTrue(unverified.requiresUserAction)
        XCTAssertFalse(unverified.blocksSending, "Backup UI does not replace the transport's E2EE/trust authorization")
        XCTAssertTrue(ChatStatusSummary.make(delivery: idle, unreadableMessageCount: 0, verification: .unverified).needsAttention)
    }

    func testOlderRecoverySnapshotDecodesAsUnknownNotVerified() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recovery())) as? [String: Any])
        json.removeValue(forKey: "deviceVerification")
        let decoded = try JSONDecoder().decode(MatrixEncryptionRecoveryStatus.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.deviceVerification)
        XCTAssertFalse(decoded.requiresUserAction)
    }

    func testUserDiscussionOfDecryptionIsNotAnUnreadableSystemPlaceholder() {
        let sample = ChatMessage(id: "$synthetic", roomId: "!room", senderId: "@peer", senderDisplayName: "Synthetic",
            body: "Zprávu se nepodařilo dešifrovat na tomto zařízení.", sentAt: .now, deliveryState: .read, isOwnMessage: false)
        XCTAssertTrue(sample.hasUnavailableEncryptedContent)
        var discussion = sample
        discussion.body = "Nápis unable to decrypt mi není jasný."
        XCTAssertFalse(discussion.hasUnavailableEncryptedContent)
    }
}
