import Foundation

private struct SafetyField: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
func requireSafetyFields(_ decoder: Decoder, allowed: Set<String>) throws {
    let keys = try decoder.container(keyedBy: SafetyField.self).allKeys.map(\.stringValue)
    guard Set(keys).isSubset(of: allowed) else { throw CSMCOPSessionError(.invalidResponse) }
}

/// Server capability, not a promise that an unavailable feature is implemented.
public struct CSMAccountSafetyCapabilities: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let reporting: Bool
    public let blocking: Bool
    public let accountDeletion: Bool
    public let accountDeletionUrl: String?
    public let accountDeletionUnavailableReason: String?
    public let reportContactEmail: String?
    public let retentionPolicyId: String?
    public let evidence: String
    public let blockDelivery: String
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contractVersion, reporting, blocking, accountDeletion, accountDeletionUrl
        case accountDeletionUnavailableReason, reportContactEmail, retentionPolicyId, evidence, blockDelivery
    }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try values.decode(String.self, forKey: .contractVersion)
        reporting = try values.decode(Bool.self, forKey: .reporting)
        blocking = try values.decode(Bool.self, forKey: .blocking)
        accountDeletion = try values.decode(Bool.self, forKey: .accountDeletion)
        if values.contains(.accountDeletionUrl), try !values.decodeNil(forKey: .accountDeletionUrl) {
            throw CSMCOPSessionError(.invalidResponse)
        }
        accountDeletionUrl = nil
        accountDeletionUnavailableReason = values.contains(.accountDeletionUnavailableReason) ? try values.decode(String.self, forKey: .accountDeletionUnavailableReason) : nil
        reportContactEmail = values.contains(.reportContactEmail) ? try values.decode(String.self, forKey: .reportContactEmail) : nil
        retentionPolicyId = values.contains(.retentionPolicyId) ? try values.decode(String.self, forKey: .retentionPolicyId) : nil
        evidence = try values.decode(String.self, forKey: .evidence)
        blockDelivery = try values.decode(String.self, forKey: .blockDelivery)
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(contractVersion, forKey: .contractVersion)
        try values.encode(reporting, forKey: .reporting)
        try values.encode(blocking, forKey: .blocking)
        try values.encode(accountDeletion, forKey: .accountDeletion)
        try values.encodeNil(forKey: .accountDeletionUrl)
        try values.encodeIfPresent(accountDeletionUnavailableReason, forKey: .accountDeletionUnavailableReason)
        try values.encodeIfPresent(reportContactEmail, forKey: .reportContactEmail)
        try values.encodeIfPresent(retentionPolicyId, forKey: .retentionPolicyId)
        try values.encode(evidence, forKey: .evidence)
        try values.encode(blockDelivery, forKey: .blockDelivery)
    }
    private func validate() throws {
        guard contractVersion == "cop-account-safety-v1", !accountDeletion, accountDeletionUrl == nil,
              evidence == "explicitly_selected_text_only", blockDelivery == "matrix_ignore_policy" else {
            throw CSMCOPSessionError(.invalidResponse)
        }
    }
}

public enum CSMCommunicationReportReason: String, Codable, Hashable, Sendable {
    case harassment, threats, spam, sexualContent = "sexual_content", other
}
public struct CSMCommunicationReportTarget: Codable, Equatable, Sendable {
    public let kind: String
    public let peerSubjectId: String
    public let conversationId: String?
    public let eventId: String?
    public let callId: String?
    private enum CodingKeys: String, CodingKey { case kind, peerSubjectId, conversationId, eventId, callId }
    private init(kind: String, peerSubjectId: String, conversationId: String?, eventId: String?, callId: String?) {
        self.kind = kind; self.peerSubjectId = peerSubjectId; self.conversationId = conversationId; self.eventId = eventId; self.callId = callId
    }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: ["kind", "peerSubjectId", "conversationId", "eventId", "callId"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: try values.decode(String.self, forKey: .kind), peerSubjectId: try values.decode(String.self, forKey: .peerSubjectId),
                  conversationId: try values.decodeIfPresent(String.self, forKey: .conversationId), eventId: try values.decodeIfPresent(String.self, forKey: .eventId), callId: try values.decodeIfPresent(String.self, forKey: .callId))
        try validateForSubmission()
    }
    public func encode(to encoder: Encoder) throws {
        try validateForSubmission()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(peerSubjectId, forKey: .peerSubjectId)
        try values.encodeIfPresent(conversationId, forKey: .conversationId)
        try values.encodeIfPresent(eventId, forKey: .eventId)
        try values.encodeIfPresent(callId, forKey: .callId)
    }
    func validateForSubmission() throws {
        func validReference(_ value: String?, limit: Int = 255) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= limit
        }
        guard validReference(peerSubjectId, limit: 256) else { throw CSMCOPSessionError(.invalidResponse) }
        switch kind {
        case "user":
            guard validReference(conversationId), eventId == nil, callId == nil else { throw CSMCOPSessionError(.invalidResponse) }
        case "message":
            guard validReference(conversationId), validReference(eventId), eventId?.hasPrefix("$") == true, callId == nil else { throw CSMCOPSessionError(.invalidResponse) }
        case "call":
            guard let callId, UUID(uuidString: callId) != nil, conversationId == nil, eventId == nil else { throw CSMCOPSessionError(.invalidResponse) }
        default: throw CSMCOPSessionError(.invalidResponse)
        }
    }

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
    private enum CodingKeys: String, CodingKey { case selectedText, explicitlyConfirmed }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: ["selectedText", "explicitlyConfirmed"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(selectedText: values.decode(String.self, forKey: .selectedText), explicitlyConfirmed: values.decode(Bool.self, forKey: .explicitlyConfirmed))
    }
    public init(selectedText: String, explicitlyConfirmed: Bool) throws {
        guard explicitlyConfirmed, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              selectedText.utf8.count <= 4096 else { throw CSMCOPSessionError(.invalidResponse) }
        self.selectedText = selectedText
        self.explicitlyConfirmed = explicitlyConfirmed
    }
    public func encode(to encoder: Encoder) throws {
        try validateForSubmission()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(selectedText, forKey: .selectedText)
        try values.encode(explicitlyConfirmed, forKey: .explicitlyConfirmed)
    }
    func validateForSubmission() throws {
        _ = try Self(selectedText: selectedText, explicitlyConfirmed: explicitlyConfirmed)
    }
}
public struct CSMCommunicationReportDraft: Codable, Sendable {
    public let target: CSMCommunicationReportTarget
    public let reason: CSMCommunicationReportReason
    public let evidence: CSMCommunicationReportEvidence?
    private enum CodingKeys: String, CodingKey { case target, reason, evidence }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: ["target", "reason", "evidence"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(target: try values.decode(CSMCommunicationReportTarget.self, forKey: .target),
                  reason: try values.decode(CSMCommunicationReportReason.self, forKey: .reason), evidence: try values.decodeIfPresent(CSMCommunicationReportEvidence.self, forKey: .evidence))
        _ = try validatedPayload()
    }
    public init(target: CSMCommunicationReportTarget, reason: CSMCommunicationReportReason, evidence: CSMCommunicationReportEvidence? = nil) {
        self.target = target; self.reason = reason; self.evidence = evidence
    }
    public func encode(to encoder: Encoder) throws {
        try target.validateForSubmission()
        try evidence?.validateForSubmission()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(target, forKey: .target)
        try values.encode(reason, forKey: .reason)
        try values.encodeIfPresent(evidence, forKey: .evidence)
    }
    func validatedPayload() throws -> Data {
        try target.validateForSubmission()
        try evidence?.validateForSubmission()
        return try JSONEncoder().encode(self)
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
              result.evidence == "explicitly_selected_text_only", result.blockDelivery == "matrix_ignore_policy" else {
            throw CSMCOPSessionError(.invalidResponse)
        }
        return result
    }
    /// Use one operation UUID for a report and all retries. Never generate a fresh UUID on retry.
    func copCommunicationReport(_ draft: CSMCommunicationReportDraft, operationId: UUID, expectedScope: String) async throws -> CSMCommunicationReportReceipt {
        let payload = try draft.validatedPayload() // Mandatory revalidation before creating any HTTP request.
        guard draft.target.peerSubjectId != model.actor?.subjectId else { throw CSMCOPSessionError(.invalidResponse) }
        let result: CSMCommunicationReportReceipt = try await mobilityRequest(path: "/api/v1/me/communication/reports", method: "POST", body: payload, query: [], expectedScope: expectedScope, idempotencyKey: operationId.uuidString)
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
