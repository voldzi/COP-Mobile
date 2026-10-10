import Foundation
import XCTest
@testable import CSMCommunicationKit

final class AccountSafetyContractsTests: XCTestCase {
    func testUnconfirmedEvidenceCannotBeConstructed() throws {
        XCTAssertThrowsError(try CSMCommunicationReportEvidence(selectedText: "selected", explicitlyConfirmed: false))
        XCTAssertThrowsError(try CSMCommunicationReportEvidence(selectedText: " ", explicitlyConfirmed: true))
        XCTAssertThrowsError(try CSMCommunicationReportEvidence(selectedText: String(repeating: "á", count: 2049), explicitlyConfirmed: true))
    }
    func testMetadataOnlyReportNeverIncludesTextOrHistory() throws {
        let draft = CSMCommunicationReportDraft(target: .message(peerSubjectId: "peer", conversationId: "conversation", eventId: "$event"), reason: .harassment)
        let encoded = try JSONEncoder().encode(draft)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["target", "reason"])
        let target = try XCTUnwrap(object["target"] as? [String: Any])
        XCTAssertEqual(Set(target.keys), ["kind", "peerSubjectId", "conversationId", "eventId"])
        XCTAssertNil(object["reporter"])
        XCTAssertNil(object["context"])
    }
    func testOnlyExplicitExcerptIsAttached() throws {
        let excerpt = try CSMCommunicationReportEvidence(selectedText: "explicit selected excerpt", explicitlyConfirmed: true)
        let draft = CSMCommunicationReportDraft(target: .call(peerSubjectId: "peer", callId: "call"), reason: .threats, evidence: excerpt)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        let evidence = try XCTUnwrap(object["evidence"] as? [String: Any])
        XCTAssertEqual(evidence["selectedText"] as? String, "explicit selected excerpt")
        XCTAssertEqual(evidence["explicitlyConfirmed"] as? Bool, true)
        XCTAssertEqual(Set(evidence.keys), ["selectedText", "explicitlyConfirmed"])
    }
    func testUnavailableDeletionIsAnUnavailableCapability() throws {
        let payload = Data(#"{"contractVersion":"cop-account-safety-v1","reporting":false,"blocking":false,"accountDeletion":false,"accountDeletionUnavailableReason":"not_accepted","evidence":"explicitly_selected_text_only","blockDelivery":"matrix_ignore_policy"}"#.utf8)
        let capability = try JSONDecoder().decode(CSMAccountSafetyCapabilities.self, from: payload)
        XCTAssertFalse(capability.accountDeletion)
        XCTAssertFalse(capability.reporting)
        XCTAssertFalse(capability.blocking)
    }
}
