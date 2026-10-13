import Foundation

/// Absence preserves the standalone COP Mobile behavior. Unknown bundle values
/// are conservative; only `automatic` and `explicit_host_consent` are valid.
public enum CSMCommunicationActivationPolicy: String, Sendable {
    case automatic
    case explicitHostConsent = "explicit_host_consent"
    case invalid

    static func fromBundleValue(_ value: Any?) -> Self {
        guard let value else { return .automatic }
        guard let text = value as? String else { return .invalid }
        return Self(rawValue: text) ?? .invalid
    }
}

/// Local feature state, never a statement that OAuth or remote grants were revoked.
public struct CSMHostCommunicationSnapshot: Equatable, Sendable {
    public let policy: CSMCommunicationActivationPolicy
    public let enabled: Bool
    public let registrationRemovalPending: Bool
    public let generation: UUID
    public let scope: String?
}

public extension Notification.Name {
    static let csmHostCommunicationConsentChanged = Notification.Name("cz.zeleznalady.csm.hostCommunicationConsentChanged")
}

public extension CSMCommunicationRuntime {
    var hostCommunicationSnapshot: CSMHostCommunicationSnapshot {
        model.hostCommunicationSnapshot(scope: mobilitySessionScope())
    }

    /// Restores only OIDC and verified COP identity/policy. No Matrix, APNs,
    /// PushKit, communication outbox or device registration is started here.
    func prepareAuthentication() async { await startAuthenticationIfNeeded() }

    /// Uses the same existing native PKCE login. The host has one login entry.
    func authenticationSignIn(loginHint: String? = nil, switchAccount: Bool = false) async {
        do { _ = try validatedCOPLoginHint(loginHint) }
        catch { model.recordCOPSessionRestoreFailure(error); return }
        await signIn(expectedSubjectID: nil, switchAccount: switchAccount,
                     loginHint: loginHint, authenticationOnly: true)
    }

    /// An explicit action in the host's account screen. This does not create a
    /// second login, delete history, sign out, or revoke another application's grants.
    @discardableResult
    func setHostCommunicationEnabled(_ enabled: Bool, expectedScope: String) async throws -> CSMHostCommunicationSnapshot {
        guard mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        try await model.setHostCommunicationEnabled(enabled)
        guard mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        refreshAccessState(expectedSubjectID: nil)
        return hostCommunicationSnapshot
    }

    /// Retries removal of this installation's known registration after an outage.
    /// The feature remains off. A pending result must not be presented as revoked.
    @discardableResult
    func retryHostCommunicationRegistrationRemoval(expectedScope: String) async throws -> CSMHostCommunicationSnapshot {
        guard mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        try await model.setHostCommunicationEnabled(false)
        guard mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        return hostCommunicationSnapshot
    }
}

enum CSMHostCommunicationRequestPolicy {
    static func requiresConsent(path: String, method: String) -> Bool {
        if path.hasPrefix("/api/v1/driver-measurements/v1/") {
            return !(path == "/api/v1/driver-measurements/v1/consent" && ["GET", "DELETE"].contains(method))
        }
        let optional = path.hasPrefix("/api/v1/shared-vehicles/") ||
            path.hasPrefix("/api/v1/private-dispatch/") || path == "/api/v1/mobility/v1/invitations"
        guard optional else { return false }
        // Existing cleanup must stay reachable after withdrawing the feature.
        if method == "POST", path.hasPrefix("/api/v1/private-dispatch/"),
           path.hasSuffix("/stop") || path.hasSuffix("/cancel-start") || path.hasSuffix("/devices/revoke") { return false }
        return true
    }
}
