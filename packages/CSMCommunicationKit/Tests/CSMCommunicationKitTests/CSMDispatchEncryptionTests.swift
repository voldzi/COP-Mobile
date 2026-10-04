import XCTest
import CryptoKit
@testable import CSMCommunicationKit

final class CSMDispatchEncryptionTests: XCTestCase {
    func testLocalTokenBindingRejectsAnotherAccountAndIssuer() throws {
        let data = try JSONSerialization.data(withJSONObject: ["iss": "https://issuer.example", "sub": "account-a"])
        let jwt = "header." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + ".signature"
        XCTAssertTrue(mobilityTokenMatchesSelectedActor(jwt, issuer: "https://issuer.example", subject: "account-a"))
        XCTAssertFalse(mobilityTokenMatchesSelectedActor(jwt, issuer: "https://issuer.example", subject: "account-b"))
        XCTAssertFalse(mobilityTokenMatchesSelectedActor(jwt, issuer: "https://other.example", subject: "account-a"))
        XCTAssertFalse(mobilityTokenMatchesSelectedActor("opaque", issuer: "https://issuer.example", subject: "account-a"))
    }
    func testAuthenticatedRecipientAgreementAndMetadataTampering() throws {
        let sender = Curve25519.KeyAgreement.PrivateKey()
        let receiver = Curve25519.KeyAgreement.PrivateKey()
        let stranger = Curve25519.KeyAgreement.PrivateKey()
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let share = CSMDispatchShare(shareId: UUID(), groupId: UUID(), accountId: UUID(), deviceId: UUID(), membershipRevision: 2, audienceHash: String(repeating: "a", count: 64), startedAt: "2026-10-04T12:00:00.000Z", expiresAt: "2026-10-04T12:15:00.000Z", endPolicy: .duration, state: .active, sequence: 1)
        let recipient = UUID()
        let sendingKey = try DispatchCipher.key(ephemeral: ephemeral.sharedSecretFromKeyAgreement(with: receiver.publicKey), authenticated: sender.sharedSecretFromKeyAgreement(with: receiver.publicKey), shareId: share.shareId)
        let receivingKey = try DispatchCipher.key(ephemeral: receiver.sharedSecretFromKeyAgreement(with: ephemeral.publicKey), authenticated: receiver.sharedSecretFromKeyAgreement(with: sender.publicKey), shareId: share.shareId)
        let aad = try DispatchCipher.aad(share: share, recipient: recipient, sequence: 1, observedAt: "2026-10-04T12:00:00.000Z")
        let clear = try JSONEncoder().encode(CSMDispatchPointPayload(lat: 50, lon: 14, horizontalAccuracyM: 5))
        let sealed = try AES.GCM.seal(clear, using: sendingKey, authenticating: aad)
        XCTAssertEqual(try AES.GCM.open(sealed, using: receivingKey, authenticating: aad), clear)
        let wrongKey = try DispatchCipher.key(ephemeral: receiver.sharedSecretFromKeyAgreement(with: ephemeral.publicKey), authenticated: receiver.sharedSecretFromKeyAgreement(with: stranger.publicKey), shareId: share.shareId)
        XCTAssertThrowsError(try AES.GCM.open(sealed, using: wrongKey, authenticating: aad))
        for modified in [try DispatchCipher.aad(share: share, recipient: UUID(), sequence: 1, observedAt: "2026-10-04T12:00:00.000Z"), try DispatchCipher.aad(share: share, recipient: recipient, sequence: 2, observedAt: "2026-10-04T12:00:00.000Z"), try DispatchCipher.aad(share: share, recipient: recipient, sequence: 1, observedAt: "2026-10-04T12:00:01.000Z")] {
            XCTAssertThrowsError(try AES.GCM.open(sealed, using: receivingKey, authenticating: modified))
        }
        XCTAssertFalse(String(decoding: sealed.combined!, as: UTF8.self).contains("horizontalAccuracyM"))
    }
    func testPublicCreateReceiptContainsExactOperationAndVehicleIdentity() throws {
        let operation = UUID(); let vehicle = UUID()
        let json = """
        {"operationId":"\(operation)","confirmed":true,"vehicle":{"contractVersion":"cop-shared-vehicles-v1","vehicleId":"\(vehicle)","details":{"name":"Synthetic"},"dataRevision":1,"membershipRevision":1,"members":[],"createdAt":"2026-10-04T12:00:00Z","updatedAt":"2026-10-04T12:00:00Z","deleted":false}}
        """
        let receipt = try JSONDecoder().decode(CSMSharedVehicleCreationReceipt.self, from: Data(json.utf8))
        XCTAssertEqual(receipt.operationId, operation); XCTAssertEqual(receipt.vehicle.vehicleId, vehicle); XCTAssertTrue(receipt.confirmed)
    }
}
