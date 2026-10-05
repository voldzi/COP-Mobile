import Foundation
#if os(iOS)
import AuthenticationServices
#endif

/// Purpose-specific error classification; contains no credentials or actor identifiers.
public enum CSMMobilityFailureKind: String, Equatable, Sendable {
    case authenticationRequired, accountChanged, temporaryNetwork, serviceUnavailable
    case configuration, invalidResponse, forbidden, rateLimited, cancelled, unknown

    public static func classify(_ error: any Error) -> Self {
        if let error = error as? CSMCOPSessionError { return error.kind }
        if error is CancellationError { return .cancelled }
        #if os(iOS)
        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { return .cancelled }
        #endif
        if let error = error as? URLError {
            return error.code == .cancelled ? .cancelled : .temporaryNetwork
        }
        if error is DecodingError { return .invalidResponse }
        if let error = error as? CSMMobilityServiceFailure {
            switch error.statusCode {
            case 401: return .authenticationRequired
            case 403: return .forbidden
            case 429: return .rateLimited
            case 500...599: return .serviceUnavailable
            default: return .invalidResponse
            }
        }
        if let error = error as? OIDCTokenRequestError {
            switch error {
            case .invalidSession: return .authenticationRequired
            case .rejected: return .serviceUnavailable
            }
        }
        if let error = error as? CSMServiceError {
            switch error {
            case .authenticationRequired: return .authenticationRequired
            case .disabled: return .configuration
            case .invalidState: return .invalidResponse
            case .unavailable: return .serviceUnavailable
            }
        }
        return .unknown
    }
}

public struct CSMCOPSessionError: LocalizedError, Sendable {
    public let kind: CSMMobilityFailureKind
    public init(_ kind: CSMMobilityFailureKind) { self.kind = kind }
    public var errorDescription: String? {
        switch kind {
        case .authenticationRequired: return "Přihlášení ke službám COP vypršelo. Obnovte přihlášení stejného účtu."
        case .accountChanged: return "Účet COP se změnil. Pro změnu účtu použijte přepnutí účtu."
        case .configuration: return "Služby COP nejsou v tomto režimu dostupné."
        case .cancelled: return "Obnova přihlášení byla zrušena."
        default: return "Přihlášení ke službám COP se nyní nepodařilo obnovit. Zkuste to znovu."
        }
    }
}

/// OIDC availability is independent of an already established Matrix chat session.
public enum CSMCOPSessionStatus: Equatable, Sendable {
    case ready, signedOut, authenticationRequired, accountChanged, temporarilyUnavailable, configuration
}

public extension CSMCommunicationRuntime {
    /// Checks/refreshes only OIDC; does not log out Matrix or expose credentials.
    func mobilityCOPSessionStatus(expectedScope: String) async -> CSMCOPSessionStatus {
        guard model.authState == .signedIn else { return .signedOut }
        guard mobilitySessionScope() == expectedScope, let subject = model.actor?.subjectId else { return .accountChanged }
        let configuration = AppConfiguration.fromBundle()
        guard !configuration.usePreviewServices else { return .configuration }
        let lifecycle = DeviceOIDCSession.shared.lifecycle(issuer: configuration.oidcIssuer, clientId: configuration.oidcClientId)
        do {
            guard let token = try await lifecycle.accessToken(), !token.isEmpty else { return .authenticationRequired }
            guard mobilitySessionScope() == expectedScope else { return .accountChanged }
            guard mobilityTokenMatchesSelectedActor(token, issuer: configuration.oidcIssuer.absoluteString, subject: subject) else {
                return .accountChanged
            }
            return .ready
        } catch { return .temporarilyUnavailable }
    }

    /// Explicit user action: reauthenticate the SAME account, without deleting
    /// Matrix state. A different issuer/subject is rejected before credential save.
    /// Call only for authenticationRequired, never as recovery for a network/503 failure.
    func mobilityRestoreSession(expectedScope: String) async throws {
        guard model.authState == .signedIn else { throw CSMCOPSessionError(.authenticationRequired) }
        guard mobilitySessionScope() == expectedScope, let subject = model.actor?.subjectId else {
            throw CSMCOPSessionError(.accountChanged)
        }
        if let task = copSessionRestoreTask { try await task.value; return }
        let task = Task { @MainActor in
            try await self.model.reauthenticateCOPSession(expectedSubjectID: subject)
            guard self.mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        }
        copSessionRestoreTask = task
        defer { copSessionRestoreTask = nil }
        try await task.value
    }
}
