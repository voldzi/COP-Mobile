import CryptoKit
import Foundation

public struct CSMMobilityServiceFailure: Error, Sendable {
    public let statusCode: Int
    public let code: String
    public let message: String
    public let correlationId: String?
    public let retryAfter: String?
}

public extension Notification.Name {
    static let csmMobilitySessionChanged = Notification.Name("CSMMobilitySessionChanged")
}

public extension CSMCommunicationRuntime {
    func mobilitySessionScope() -> String? {
        guard model.authState == .signedIn, let actor = model.actor else { return nil }
        let issuer = AppConfiguration.fromBundle().oidcIssuer.absoluteString
        return SHA256.hash(data: Data((issuer + "\0" + actor.subjectId).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Opens the existing PKCE IdP page; registration is available only if the IdP offers it.
    func mobilitySignIn(switchAccount: Bool = false) async {
        await signIn(expectedSubjectID: nil, switchAccount: switchAccount)
    }

    func mobilityCapabilities(expectedScope: String) async throws -> CSMMobilityCapabilities {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/mobility/v1/capabilities", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func mobilityAccount(expectedScope: String) async throws -> CSMMobilityAccount {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/mobility/v1/account", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func sharedVehicles(expectedScope: String) async throws -> CSMSharedVehicleList {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func sharedVehicleCreate(request: CSMSharedVehicleCreate, expectedScope: String) async throws -> CSMSharedVehicleCreationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleGet(vehicleId: UUID, expectedScope: String) async throws -> CSMSharedVehicle {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func sharedVehicleUpdate(vehicleId: UUID, request: CSMSharedVehicleUpdate, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())", method: "PATCH", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleMembershipChange(vehicleId: UUID, request: CSMSharedVehicleMembershipChange, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/members", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleInvite(vehicleId: UUID, request: CSMMobilityInvitationCreate, expectedScope: String) async throws -> CSMMobilityInvitationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/invitations", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleInviteRevoke(vehicleId: UUID, request: CSMMobilityInvitationRevoke, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/invitations/revoke", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleInviteAccept(request: CSMMobilityInvitationAccept, expectedScope: String) async throws -> CSMSharedVehicleCreationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/invitations/accept", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleRecordWrite(vehicleId: UUID, request: CSMSharedVehicleRecordWrite, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/records", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleSync(vehicleId: UUID, cursor: String? = nil, limit: Int? = nil, expectedScope: String) async throws -> CSMSharedVehicleSync {
        var query: [URLQueryItem] = []
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/sync", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchGroups(expectedScope: String) async throws -> CSMDispatchGroupList {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchGroupCreate(request: CSMDispatchGroupCreate, expectedScope: String) async throws -> CSMDispatchGroupCreationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchGroupGet(groupId: UUID, expectedScope: String) async throws -> CSMDispatchGroup {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchMembershipChange(groupId: UUID, request: CSMDispatchMembershipChange, expectedScope: String) async throws -> CSMDispatchGroup {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/members", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchInvite(groupId: UUID, request: CSMDispatchInvitationCreate, expectedScope: String) async throws -> CSMMobilityInvitationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/invitations", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchInviteAccept(request: CSMMobilityInvitationAccept, expectedScope: String) async throws -> CSMDispatchGroupCreationReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/invitations/accept", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchDeviceRegister(request: CSMDispatchDeviceRegister, expectedScope: String) async throws -> CSMDispatchDevice {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/devices", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchReadiness(groupId: UUID, expectedScope: String) async throws -> CSMDispatchReadiness {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/readiness", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchSnapshot(groupId: UUID, deviceId: UUID, expectedScope: String) async throws -> CSMDispatchSnapshot {
        var query: [URLQueryItem] = []
        query.append(.init(name: "deviceId", value: deviceId.uuidString.lowercased()))
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/snapshot", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchStart(groupId: UUID, request: CSMDispatchShareStart, expectedScope: String) async throws -> CSMDispatchShareReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/shares", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchPublish(shareId: UUID, request: CSMDispatchPointPublish, expectedScope: String) async throws -> CSMDispatchShareReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/shares/\(shareId.uuidString.lowercased())/points", method: "PUT", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchStop(shareId: UUID, request: CSMDispatchStop, expectedScope: String) async throws -> CSMDispatchShareReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/shares/\(shareId.uuidString.lowercased())/stop", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleDelete(vehicleId: UUID, request: CSMSharedVehicleDelete, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/delete", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func sharedVehicleRecordDelete(vehicleId: UUID, request: CSMSharedVehicleRecordDelete, expectedScope: String) async throws -> CSMSharedVehicleReceipt {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/shared-vehicles/v1/vehicles/\(vehicleId.uuidString.lowercased())/records/delete", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchInviteRevoke(groupId: UUID, request: CSMMobilityInvitationRevoke, expectedScope: String) async throws -> CSMDispatchGroup {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/invitations/revoke", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchGroupDelete(groupId: UUID, request: CSMDispatchGroupDelete, expectedScope: String) async throws -> CSMDispatchGroup {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/groups/\(groupId.uuidString.lowercased())/delete", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func dispatchDeviceRevoke(request: CSMDispatchDeviceRevoke, expectedScope: String) async throws -> CSMDispatchDevice {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/devices/revoke", method: "POST", body: try JSONEncoder().encode(request), query: query, expectedScope: expectedScope)
    }

    func mobilityInvitations(expectedScope: String) async throws -> CSMMobilityPendingInvitations {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/mobility/v1/invitations", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }

    func dispatchOwnedShares(expectedScope: String) async throws -> CSMDispatchOwnedShares {
        let query: [URLQueryItem] = []
        return try await mobilityRequest(path: "/api/v1/private-dispatch/v1/shares", method: "GET", body: nil, query: query, expectedScope: expectedScope)
    }


    /// Cancels a possibly timed-out start before/after commit, account-bound and durable.
    /// Keep the local pending-stop barrier until the exact cancellation receipt is confirmed.
    func dispatchCancelStart(request: CSMDispatchStartCancel, expectedScope: String) async throws -> CSMDispatchStartCancelReceipt {
        try await mobilityRequest(path: "/api/v1/private-dispatch/v1/shares/cancel-start", method: "POST", body: try JSONEncoder().encode(request), query: [], expectedScope: expectedScope)
    }

    private func mobilityRequest<Response: Decodable>(path: String, method: String, body: Data?, query: [URLQueryItem], expectedScope: String) async throws -> Response {
        let generation = MobilitySessionGeneration.shared.value
        guard mobilitySessionScope() == expectedScope else { throw CSMServiceError.authenticationRequired("Účet COP se změnil.") }
        let configuration = AppConfiguration.fromBundle()
        guard !configuration.usePreviewServices, configuration.copBaseURL.scheme == "https",
              configuration.copBaseURL.user == nil, configuration.copBaseURL.password == nil,
              configuration.copBaseURL.query == nil, configuration.copBaseURL.fragment == nil,
              ["", "/"].contains(configuration.copBaseURL.path) else {
            throw CSMServiceError.disabled("Sdílení vyžaduje ověřenou konfiguraci COP.")
        }
        let lifecycle = OIDCTokenLifecycle(issuer: configuration.oidcIssuer, clientId: configuration.oidcClientId, credentialStore: KeychainCredentialStore())
        guard let token = try await lifecycle.accessToken(), !token.isEmpty, generation == MobilitySessionGeneration.shared.value, mobilitySessionScope() == expectedScope else {
            throw CSMServiceError.authenticationRequired("Přihlášení COP vypršelo.")
        }
        guard var components = URLComponents(url: configuration.copBaseURL, resolvingAgainstBaseURL: false) else { throw CSMServiceError.invalidState("Neplatná adresa COP.") }
        components.path = path; components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw CSMServiceError.invalidState("Neplatná adresa COP.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: MobilityNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard generation == MobilitySessionGeneration.shared.value, mobilitySessionScope() == expectedScope, let http = response as? HTTPURLResponse,
              http.url == url, data.count <= 4_194_304 else { throw CSMServiceError.authenticationRequired("Účet COP se změnil.") }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(CSMMobilityError.self, from: data)
            throw CSMMobilityServiceFailure(statusCode: http.statusCode, code: error?.error.code ?? "MOBILITY_UNAVAILABLE",
                message: error?.error.message ?? "Sdílení COP není dostupné.", correlationId: error?.error.correlationId,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
private final class MobilityNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor private final class MobilitySessionGeneration {
    static let shared = MobilitySessionGeneration()
    var value = UUID()
    private var observer: NSObjectProtocol?
    private init() {
        observer = NotificationCenter.default.addObserver(forName: .csmMobilitySessionChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.value = UUID() }
        }
    }
}
