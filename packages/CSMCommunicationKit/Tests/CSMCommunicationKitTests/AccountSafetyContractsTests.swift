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
        let draft = CSMCommunicationReportDraft(target: .call(peerSubjectId: "peer", callId: "e6450609-cbe5-4c9c-adfa-598db1d125ef"), reason: .threats, evidence: excerpt)
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
    func testDecoderCannotBypassEvidenceValidation() throws {
        for (text, confirmed) in [("selected", false), ("", true), (" \n\t", true), (String(repeating: "x", count: 4097), true), (String(repeating: "á", count: 2049), true)] {
            let data = try JSONSerialization.data(withJSONObject: ["selectedText": text, "explicitlyConfirmed": confirmed])
            XCTAssertThrowsError(try JSONDecoder().decode(CSMCommunicationReportEvidence.self, from: data))
        }
        let evidence = try CSMCommunicationReportEvidence(selectedText: String(repeating: "á", count: 2048), explicitlyConfirmed: true)
        let decoded = try JSONDecoder().decode(CSMCommunicationReportEvidence.self, from: JSONEncoder().encode(evidence))
        XCTAssertEqual(decoded.selectedText.utf8.count, 4096)
        let draft = CSMCommunicationReportDraft(target: .user(peerSubjectId: "peer", conversationId: "conversation"), reason: .spam, evidence: decoded)
        XCTAssertNoThrow(try draft.validatedPayload())
    }
    func testMalformedTargetRejectedBeforeHTTPPayloadIsCreated() throws {
        let targets = [CSMCommunicationReportTarget.call(peerSubjectId: "peer", callId: "call"),
                       .message(peerSubjectId: "peer", conversationId: "conversation", eventId: "bad-event"),
                       .user(peerSubjectId: " ", conversationId: "conversation"),
                       .user(peerSubjectId: String(repeating: "x", count: 257), conversationId: "conversation"),
                       .user(peerSubjectId: "peer", conversationId: String(repeating: "x", count: 256))]
        for target in targets {
            XCTAssertThrowsError(try CSMCommunicationReportDraft(target: target, reason: .other).validatedPayload())
        }
        for object: [String: Any] in [
            ["kind":"call", "peerSubjectId":"peer", "callId":"e6450609-cbe5-4c9c-adfa-598db1d125ef", "conversationId":"other"],
            ["kind":"user", "peerSubjectId":"peer", "conversationId":"conversation", "roomId":"!caller-room:test"],
            ["kind":"unknown", "peerSubjectId":"peer", "conversationId":"conversation"]
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(CSMCommunicationReportTarget.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }
    func testPlainEncoderCannotBypassReportTargetValidation() throws {
        let targets = [CSMCommunicationReportTarget.call(peerSubjectId: "peer", callId: "call"),
                       .message(peerSubjectId: "peer", conversationId: "conversation", eventId: "bad-event"),
                       .user(peerSubjectId: " ", conversationId: "conversation"),
                       .user(peerSubjectId: String(repeating: "x", count: 257), conversationId: "conversation"),
                       .user(peerSubjectId: "peer", conversationId: String(repeating: "x", count: 256))]
        for target in targets {
            XCTAssertThrowsError(try JSONEncoder().encode(target))
            XCTAssertThrowsError(try JSONEncoder().encode(CSMCommunicationReportDraft(target: target, reason: .other)))
        }
        let target = CSMCommunicationReportTarget.call(peerSubjectId: "peer", callId: "e6450609-cbe5-4c9c-adfa-598db1d125ef")
        let encoded = try JSONEncoder().encode(target)
        XCTAssertEqual(try JSONDecoder().decode(CSMCommunicationReportTarget.self, from: encoded), target)
    }
    func testEvidenceEncodingRetainsOnlyConfirmedBoundedExcerpt() throws {
        let evidence = try CSMCommunicationReportEvidence(selectedText: String(repeating: "á", count: 2048), explicitlyConfirmed: true)
        let encoded = try JSONEncoder().encode(evidence)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["selectedText", "explicitlyConfirmed"])
        XCTAssertEqual((object["selectedText"] as? String)?.utf8.count, 4096)
        XCTAssertEqual(object["explicitlyConfirmed"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(CSMCommunicationReportEvidence.self, from: encoded), evidence)
    }
    func testUnlinkIsNotDeletionOrCompletionWhileCleanupRemains() throws {
        let pending = Data(#"{"contractVersion":"cop-jizda-link-v1","app":"jizda","scope":"jizda_app_link","status":"disconnecting","operationId":"e6450609-cbe5-4c9c-adfa-598db1d125ef","requestedAt":"2026-10-11T00:00:00.000Z","accountDeleted":false,"localDataDeleted":false,"remaining":["matrix_devices","live_permissions"]}"#.utf8)
        let receipt = try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: pending)
        XCTAssertNoThrow(try receipt.validate()); XCTAssertFalse(receipt.isComplete)
        let falseSuccess = String(decoding: pending, as: UTF8.self).replacingOccurrences(of: "disconnecting", with: "disconnected")
        XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: Data(falseSuccess.utf8)).validate())
    }
    func testDisconnectHTTPStatusMustMatchCleanupReceipt() throws {
        let pending = try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: Data(#"{"contractVersion":"cop-jizda-link-v1","app":"jizda","scope":"jizda_app_link","status":"disconnecting","operationId":"e6450609-cbe5-4c9c-adfa-598db1d125ef","requestedAt":"2026-10-11T00:00:00.000Z","accountDeleted":false,"localDataDeleted":false,"remaining":["matrix_devices"]}"#.utf8))
        let complete = try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: Data(#"{"contractVersion":"cop-jizda-link-v1","app":"jizda","scope":"jizda_app_link","status":"disconnected","operationId":"e6450609-cbe5-4c9c-adfa-598db1d125ef","requestedAt":"2026-10-11T00:00:00.000Z","accountDeleted":false,"localDataDeleted":false,"remaining":[]}"#.utf8))
        XCTAssertNoThrow(try pending.validate(disconnectHTTPStatus: 202))
        XCTAssertNoThrow(try complete.validate(disconnectHTTPStatus: 200))
        XCTAssertFalse(pending.isComplete)
        XCTAssertTrue(complete.isComplete)
        XCTAssertThrowsError(try complete.validate(disconnectHTTPStatus: 202))
        XCTAssertThrowsError(try pending.validate(disconnectHTTPStatus: 200))
        for unsupportedStatus in [201, 204] {
            XCTAssertThrowsError(try pending.validate(disconnectHTTPStatus: unsupportedStatus))
            XCTAssertThrowsError(try complete.validate(disconnectHTTPStatus: unsupportedStatus))
        }
        // GET status is allowed to describe pending cleanup without POST semantics.
        XCTAssertNoThrow(try pending.validate())
        XCTAssertNoThrow(try complete.validate())
    }
    func testUnlinkRejectsDuplicateCleanupAndLinkedOperationData() throws {
        let duplicate = Data(#"{"contractVersion":"cop-jizda-link-v1","app":"jizda","scope":"jizda_app_link","status":"disconnecting","operationId":"e6450609-cbe5-4c9c-adfa-598db1d125ef","requestedAt":"2026-10-11T00:00:00.000Z","accountDeleted":false,"localDataDeleted":false,"remaining":["matrix_devices","matrix_devices"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: duplicate))
        let linkedFields: [String: Any] = ["contractVersion": "cop-jizda-link-v1", "app": "jizda", "scope": "jizda_app_link", "status": "linked", "accountDeleted": false, "localDataDeleted": false]
        let linked = try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: linkedFields))
        XCTAssertNoThrow(try linked.validate())
        XCTAssertFalse(linked.isComplete)
        XCTAssertThrowsError(try linked.validate(disconnectHTTPStatus: 200))
        XCTAssertThrowsError(try linked.validate(disconnectHTTPStatus: 202))
        for (field, value): (String, Any) in [("operationId", "e6450609-cbe5-4c9c-adfa-598db1d125ef"), ("requestedAt", "2026-10-11T00:00:00.000Z"), ("remaining", [String]())] {
            var invalidLinked = linkedFields
            invalidLinked[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: invalidLinked)))
        }
    }
    func testAccountSafetyCapabilitiesEnforceCurrentVersionIndependently() throws {
        let fields: [String: Any] = ["contractVersion": "cop-account-safety-v1", "reporting": false, "blocking": false, "accountDeletion": false,
                                     "accountDeletionUrl": NSNull(), "evidence": "explicitly_selected_text_only", "blockDelivery": "matrix_ignore_policy"]
        for (reporting, blocking) in [(false, false), (true, false), (false, true), (true, true)] {
            var independent = fields
            independent["reporting"] = reporting; independent["blocking"] = blocking
            let capability = try JSONDecoder().decode(CSMAccountSafetyCapabilities.self, from: JSONSerialization.data(withJSONObject: independent))
            XCTAssertEqual(capability.reporting, reporting); XCTAssertEqual(capability.blocking, blocking)
            XCTAssertFalse(capability.accountDeletion); XCTAssertNil(capability.accountDeletionUrl)
            XCTAssertEqual(try JSONDecoder().decode(CSMAccountSafetyCapabilities.self, from: JSONEncoder().encode(capability)), capability)
        }
        for (field, value): (String, Any) in [("accountDeletion", true), ("accountDeletionUrl", "https://cop.example/account/delete"), ("accountDeletionUrl", ""),
                                           ("contractVersion", "future-version"), ("evidence", "automatic_history"), ("blockDelivery", "local_only"), ("extra", true)] {
            var invalid = fields; invalid[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CSMAccountSafetyCapabilities.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
    }
    func testJizdaLinkCapabilitiesCannotClaimAccountOrLocalDataDeletion() throws {
        let fields: [String: Any] = ["contractVersion": "cop-jizda-link-v1", "app": "jizda", "scope": "jizda_app_link", "disconnectAvailable": false,
                                     "accountDeletion": false, "localDataDeleted": false, "unavailableReason": "not_enabled"]
        for available in [false, true] {
            var truthful = fields; truthful["disconnectAvailable"] = available
            let capability = try JSONDecoder().decode(CSMJizdaLinkCapabilities.self, from: JSONSerialization.data(withJSONObject: truthful))
            XCTAssertEqual(capability.disconnectAvailable, available)
            XCTAssertEqual(try JSONDecoder().decode(CSMJizdaLinkCapabilities.self, from: JSONEncoder().encode(capability)), capability)
        }
        for (field, value): (String, Any) in [("accountDeletion", true), ("localDataDeleted", true), ("contractVersion", "future-version"), ("app", "cop-mobile"),
                                           ("scope", "whole_account"), ("unavailableReason", "unknown"), ("extra", true)] {
            var invalid = fields; invalid[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkCapabilities.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
    }
    func testStandaloneUnlinkDecoderRejectsFalseCompletionAndInvalidIdentity() throws {
        let fields: [String: Any] = ["contractVersion": "cop-jizda-link-v1", "app": "jizda", "scope": "jizda_app_link", "status": "disconnected",
                                     "operationId": "e6450609-cbe5-4c9c-adfa-598db1d125ef", "requestedAt": "2026-10-11T00:00:00.000Z",
                                     "accountDeleted": false, "localDataDeleted": false, "remaining": [String]()]
        for (field, value): (String, Any) in [("accountDeleted", true), ("localDataDeleted", true), ("contractVersion", "future-version"), ("app", "cop-mobile"),
                                           ("scope", "whole_account"), ("operationId", "invalid"), ("requestedAt", "invalid"), ("remaining", ["matrix_devices"]),
                                           ("status", "disconnecting"), ("extra", true)] {
            var invalid = fields; invalid[field] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
        for field in ["operationId", "requestedAt", "remaining"] {
            var missing = fields; missing.removeValue(forKey: field)
            XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: missing)))
        }
    }
    func testStandaloneUnlinkDecoderRoundTripsTruthfulStates() throws {
        let linked: [String: Any] = ["contractVersion": "cop-jizda-link-v1", "app": "jizda", "scope": "jizda_app_link", "status": "linked",
                                     "accountDeleted": false, "localDataDeleted": false]
        for status in ["linked", "disconnecting", "disconnected"] {
            var fields = linked; fields["status"] = status
            if status != "linked" {
                fields["operationId"] = "e6450609-cbe5-4c9c-adfa-598db1d125ef"; fields["requestedAt"] = "2026-10-11T00:00:00.000Z"
                fields["remaining"] = status == "disconnecting" ? ["matrix_devices"] : []
            }
            let receipt = try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: fields))
            XCTAssertEqual(receipt.isComplete, status == "disconnected")
            XCTAssertEqual(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONEncoder().encode(receipt)), receipt)
        }
        for field in ["operationId", "requestedAt", "remaining"] {
            var invalid = linked; invalid[field] = NSNull()
            XCTAssertThrowsError(try JSONDecoder().decode(CSMJizdaLinkReceipt.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
    }
}
