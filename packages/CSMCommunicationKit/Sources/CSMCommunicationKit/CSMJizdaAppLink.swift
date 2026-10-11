import Foundation

public extension Notification.Name {
    /// No actor, credential, coordinate or content in this process-local event.
    static let csmJizdaLinkFenceAccepted = Notification.Name("cz.zeleznalady.csm.jizdaLinkFenceAccepted")
}

public struct CSMJizdaLinkCapabilities: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let app: String
    public let scope: String
    public let disconnectAvailable: Bool
    public let accountDeletion: Bool
    public let localDataDeleted: Bool
    public let unavailableReason: String?
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contractVersion, app, scope, disconnectAvailable, accountDeletion, localDataDeleted, unavailableReason
    }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try values.decode(String.self, forKey: .contractVersion)
        app = try values.decode(String.self, forKey: .app)
        scope = try values.decode(String.self, forKey: .scope)
        disconnectAvailable = try values.decode(Bool.self, forKey: .disconnectAvailable)
        accountDeletion = try values.decode(Bool.self, forKey: .accountDeletion)
        localDataDeleted = try values.decode(Bool.self, forKey: .localDataDeleted)
        unavailableReason = values.contains(.unavailableReason) ? try values.decode(String.self, forKey: .unavailableReason) : nil
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(contractVersion, forKey: .contractVersion)
        try values.encode(app, forKey: .app)
        try values.encode(scope, forKey: .scope)
        try values.encode(disconnectAvailable, forKey: .disconnectAvailable)
        try values.encode(accountDeletion, forKey: .accountDeletion)
        try values.encode(localDataDeleted, forKey: .localDataDeleted)
        try values.encodeIfPresent(unavailableReason, forKey: .unavailableReason)
    }
    private func validate() throws {
        guard contractVersion == "cop-jizda-link-v1", app == "jizda", scope == "jizda_app_link", !accountDeletion, !localDataDeleted,
              unavailableReason == nil || ["app_identity_not_separated", "not_enabled"].contains(unavailableReason!) else {
            throw CSMCOPSessionError(.invalidResponse)
        }
    }
}
public struct CSMJizdaLinkReceipt: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let app: String
    public let scope: String
    public let status: String
    public let operationId: String?
    public let requestedAt: String?
    public let accountDeleted: Bool
    public let localDataDeleted: Bool
    public let remaining: [String]?
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case contractVersion, app, scope, status, operationId, requestedAt, accountDeleted, localDataDeleted, remaining
    }
    public init(from decoder: Decoder) throws {
        try requireSafetyFields(decoder, allowed: Set(CodingKeys.allCases.map(\.rawValue)))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try values.decode(String.self, forKey: .contractVersion)
        app = try values.decode(String.self, forKey: .app)
        scope = try values.decode(String.self, forKey: .scope)
        status = try values.decode(String.self, forKey: .status)
        accountDeleted = try values.decode(Bool.self, forKey: .accountDeleted)
        localDataDeleted = try values.decode(Bool.self, forKey: .localDataDeleted)
        if status == "linked" {
            try requireSafetyFields(decoder, allowed: ["contractVersion", "app", "scope", "status", "accountDeleted", "localDataDeleted"])
            operationId = nil; requestedAt = nil; remaining = nil
        } else {
            operationId = try values.decode(String.self, forKey: .operationId)
            requestedAt = try values.decode(String.self, forKey: .requestedAt)
            remaining = try values.decode([String].self, forKey: .remaining)
        }
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(contractVersion, forKey: .contractVersion)
        try values.encode(app, forKey: .app)
        try values.encode(scope, forKey: .scope)
        try values.encode(status, forKey: .status)
        try values.encode(accountDeleted, forKey: .accountDeleted)
        try values.encode(localDataDeleted, forKey: .localDataDeleted)
        try values.encodeIfPresent(operationId, forKey: .operationId)
        try values.encodeIfPresent(requestedAt, forKey: .requestedAt)
        try values.encodeIfPresent(remaining, forKey: .remaining)
    }
    public var isComplete: Bool { status == "disconnected" && remaining == [] }
    func validate(disconnectHTTPStatus: Int? = nil) throws {
        guard contractVersion == "cop-jizda-link-v1", app == "jizda", scope == "jizda_app_link", !accountDeleted, !localDataDeleted,
              ["linked", "disconnecting", "disconnected"].contains(status) else { throw CSMCOPSessionError(.invalidResponse) }
        if status == "linked" {
            guard operationId == nil, requestedAt == nil, remaining == nil else { throw CSMCOPSessionError(.invalidResponse) }
        } else {
            guard let operationId, UUID(uuidString: operationId) != nil, let requestedAt, ISO8601DateFormatter().date(from: requestedAt) != nil || ISO8601DateFormatter.fractional.date(from: requestedAt) != nil,
                  let remaining, Set(remaining).count == remaining.count,
                  Set(remaining).isSubset(of: ["push_registrations", "legacy_installations", "matrix_devices", "live_permissions"]),
                  (status == "disconnected") == remaining.isEmpty else { throw CSMCOPSessionError(.invalidResponse) }
        }
        if let disconnectHTTPStatus {
            guard (disconnectHTTPStatus == 202 && status == "disconnecting") ||
                  (disconnectHTTPStatus == 200 && isComplete) else { throw CSMCOPSessionError(.invalidResponse) }
        }
    }
}
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter { let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value }
}
public extension CSMCommunicationRuntime {
    func copJizdaLinkCapabilities(expectedScope: String) async throws -> CSMJizdaLinkCapabilities {
        let result: CSMJizdaLinkCapabilities = try await mobilityRequest(path: "/api/v1/me/app-links/jizda/capabilities", method: "GET", body: nil, query: [], expectedScope: expectedScope)
        guard result.contractVersion == "cop-jizda-link-v1", result.app == "jizda", result.scope == "jizda_app_link", !result.accountDeletion, !result.localDataDeleted else { throw CSMCOPSessionError(.invalidResponse) }
        return result
    }
    func copJizdaLinkStatus(expectedScope: String) async throws -> CSMJizdaLinkReceipt {
        let result: CSMJizdaLinkReceipt = try await mobilityRequest(path: "/api/v1/me/app-links/jizda", method: "GET", body: nil, query: [], expectedScope: expectedScope)
        try result.validate()
        if result.status != "linked" {
            await model.suspendLocalCommunicationForJizdaUnlink()
            NotificationCenter.default.post(name: .csmJizdaLinkFenceAccepted, object: nil)
        }
        return result
    }
    /// Label the explicit confirmation "Odpojit Jízdu". 202/pending is not completion.
    /// Stop this host's producers when the fence is accepted; preserve SwiftData.
    /// Never call global COP/Matrix user deletion or unlink another app here.
    func copDisconnectJizda(operationId: UUID, expectedScope: String) async throws -> CSMJizdaLinkReceipt {
        let config = AppConfiguration.fromBundle()
        guard !["csm-mobile", "cop-web"].contains(config.oidcClientId) else { throw CSMCOPSessionError(.configuration) }
        let result: CSMJizdaLinkReceipt = try await mobilityRequest(path: "/api/v1/me/app-links/jizda/disconnect", method: "POST", body: nil, query: [], expectedScope: expectedScope, idempotencyKey: operationId.uuidString, responseValidator: { status, receipt in
            try receipt.validate(disconnectHTTPStatus: status)
        })
        try result.validate()
        guard result.operationId?.lowercased() == operationId.uuidString.lowercased(), result.status != "linked" else { throw CSMCOPSessionError(.invalidResponse) }
        await model.suspendLocalCommunicationForJizdaUnlink()
        NotificationCenter.default.post(name: .csmJizdaLinkFenceAccepted, object: nil)
        return result
    }
}
