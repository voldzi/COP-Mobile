import Foundation

/// Server capability, not a promise that an unavailable feature is implemented.
public struct CSMAccountSafetyCapabilities: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let reporting: Bool
    public let blocking: Bool
    public let accountDeletion: Bool
    public let accountDeletionUnavailableReason: String?
    public let reportContactEmail: String?
    public let retentionPolicyId: String?
    public let evidence: String
    public let blockDelivery: String
}

public enum CSMCommunicationReportReason: String, Codable, Sendable {
    case harassment, threats, spam, sexualContent = "sexual_content", other
}
public struct CSMCommunicationReportTarget: Codable, Equatable, Sendable {
    public let kind: String
    public let peerSubjectId: String
    public let conversationId: String?
    public let eventId: String?
    public let callId: String?

    public static func user(peerSubjectId: String, conversationId: String) -> Self {
        .init(kind: "user", peerSubjectId: peerSubjectId, conversationId: conversationId, eventId: nil, callId: nil)
    }
    public static func message(peerSubjectId: String, conversationId: String, eventId: String) -> Self {
        .init(kind: "message", peerSubjectId: peerSubjectId, conversationId: conversationId, eventId: eventId, callId: nil)
    }
    public static func call(peerSubjectId: String, callId: String) -> Self {
        .init(kind: "call", peerSubjectId: peerSubjectId, conversationId: nil, eventId: nil, callId: callId)
    }
}

/// Host must show the selected excerpt and obtain explicit confirmation before constructing this.
/// No timeline/history is read or selected automatically by the SDK.
public struct CSMCommunicationReportEvidence: Codable, Equatable, Sendable {
    public let selectedText: String
    public let explicitlyConfirmed: Bool
    public init(selectedText: String, explicitlyConfirmed: Bool) throws {
        guard explicitlyConfirmed, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedText.utf8.count <= 4096 else { throw CSMCOPSessionError(.invalidResponse) }
        self.selectedText = selectedText
        self.explicitlyConfirmed = explicitlyConfirmed
    }
}
public struct CSMCommunicationReportDraft: Codable, Sendable {
    public let target: CSMCommunicationReportTarget
    public let reason: CSMCommunicationReportReason
    public let evidence: CSMCommunicationReportEvidence?
    public init(target: CSMCommunicationReportTarget, reason: CSMCommunicationReportReason, evidence: CSMCommunicationReportEvidence? = nil) {
        self.target = target; self.reason = reason; self.evidence = evidence
    }
}
public struct CSMCommunicationReportReceipt: Codable, Equatable, Sendable {
    public let reportId: String
    public let createdAt: String
    public let status: String
    public let revision: Int
    public let resolution: String?
}
public struct CSMCommunicationBlockState: Codable, Equatable, Sendable {
    public let peerSubjectId: String
    public let blocked: Bool
}

public extension CSMCommunicationRuntime {
    func copAccountSafetyCapabilities(expectedScope: String) async throws -> CSMAccountSafetyCapabilities {
        let result: CSMAccountSafetyCapabilities = try await mobilityRequest(path: "/api/v1/me/account-safety/capabilities", method: "GET", body: nil, query: [], expectedScope: expectedScope)
        guard result.contractVersion == "cop-account-safety-v1",
              !result.accountDeletion, result.evidence == "explicitly_selected_text_only", result.blockDelivery == "matrix_ignore_policy" else {
            throw CSMCOPSessionError(.invalidResponse)
        }
        return result
    }
    /// Use one operation UUID for a report and all retries. Never generate a fresh UUID on retry.
    func copCommunicationReport(_ draft: CSMCommunicationReportDraft, operationId: UUID, expectedScope: String) async throws -> CSMCommunicationReportReceipt {
        let result: CSMCommunicationReportReceipt = try await mobilityRequest(path: "/api/v1/me/communication/reports", method: "POST", body: JSONEncoder().encode(draft), query: [], expectedScope: expectedScope, idempotencyKey: operationId.uuidString)
        try validateCOPReportReceipt(result)
        return result
    }
    func copCommunicationReportStatus(reportId: String, expectedScope: String) async throws -> CSMCommunicationReportReceipt {
        guard UUID(uuidString: reportId) != nil else { throw CSMCOPSessionError(.invalidResponse) }
        let result: CSMCommunicationReportReceipt = try await mobilityRequest(path: "/api/v1/me/communication/reports/" + reportId, method: "GET", body: nil, query: [], expectedScope: expectedScope)
        try validateCOPReportReceipt(result)
        guard result.reportId == reportId else { throw CSMCOPSessionError(.invalidResponse) }
        return result
    }
    func copCommunicationBlockState(peerSubjectId: String, expectedScope: String) async throws -> CSMCommunicationBlockState {
        try await communicationBlock(peerSubjectId: peerSubjectId, blocked: nil, expectedScope: expectedScope)
    }
    /// Server controls Matrix ignore state and blocks new direct call grants and push.
    /// After success, host hides this peer's cached history and discards pending drafts explicitly.
    /// This operation does not delete another person's account or shared group membership.
    func copCommunicationSetBlocked(_ blocked: Bool, peerSubjectId: String, expectedScope: String) async throws -> CSMCommunicationBlockState {
        try await communicationBlock(peerSubjectId: peerSubjectId, blocked: blocked, expectedScope: expectedScope)
    }
    private func communicationBlock(peerSubjectId: String, blocked: Bool?, expectedScope: String) async throws -> CSMCommunicationBlockState {
        guard !peerSubjectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, peerSubjectId.utf8.count <= 256,
              peerSubjectId != model.actor?.subjectId else { throw CSMCOPSessionError(.invalidResponse) }
        var body: [String: Any] = ["peerSubjectId": peerSubjectId]
        if let blocked { body["blocked"] = blocked }
        let result: CSMCommunicationBlockState = try await mobilityRequest(path: "/api/v1/me/communication/blocks" + (blocked == nil ? "/query" : ""), method: blocked == nil ? "POST" : "PUT", body: JSONSerialization.data(withJSONObject: body), query: [], expectedScope: expectedScope)
        guard result.peerSubjectId == peerSubjectId, blocked == nil || result.blocked == blocked else { throw CSMCOPSessionError(.invalidResponse) }
        return result
    }
    private func validateCOPReportReceipt(_ value: CSMCommunicationReportReceipt) throws {
        guard UUID(uuidString: value.reportId) != nil, value.revision > 0, ["submitted", "reviewing", "resolved"].contains(value.status),
              value.resolution == nil || ["no_action", "action_taken"].contains(value.resolution!) else { throw CSMCOPSessionError(.invalidResponse) }
    }
}
