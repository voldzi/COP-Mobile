import Foundation

struct OIDCDiscoveryLoader: Sendable {
    var issuer: URL
    var session: URLSession = .shared

    func load() async throws -> OIDCDiscoveryDocument {
        let validatedIssuer = try OIDCDiscoveryValidator.validatedConfiguredIssuer(issuer)
        let discoveryURL = validatedIssuer
            .appendingPathComponent(".well-known")
            .appendingPathComponent("openid-configuration")
        let (data, response) = try await session.data(from: discoveryURL)
        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw CSMServiceError.unavailable("OIDC discovery failed.")
        }
        let discovery = try CSMJSONCoding.decoder.decode(OIDCDiscoveryDocument.self, from: data)
        return try OIDCDiscoveryValidator.validate(discovery, configuredIssuer: validatedIssuer)
    }
}

/// Owns the complete device-local OIDC token lifecycle.
///
/// A short-lived access token is refreshed on demand for every authorized API
/// consumer. Temporary network/identity-provider failures never erase the
/// Keychain session. Only an explicit OAuth `invalid_grant` response proves
/// that the refresh session is no longer usable.
actor OIDCTokenLifecycle: AccessTokenProviding {
    private let clientId: String
    private let credentialStore: any TokenCredentialStoring
    private let discoveryLoader: OIDCDiscoveryLoader
    private let tokenExchanger: OIDCTokenExchanger
    private var refreshTask: Task<TokenPair, any Error>?
    private var sessionGeneration: UInt64 = 0

    init(
        issuer: URL,
        clientId: String,
        credentialStore: any TokenCredentialStoring,
        session: URLSession = .shared
    ) {
        self.clientId = clientId
        self.credentialStore = credentialStore
        self.discoveryLoader = OIDCDiscoveryLoader(issuer: issuer, session: session)
        self.tokenExchanger = OIDCTokenExchanger(session: session)
    }

    func accessToken() async throws -> String? {
        guard let tokens = try await credentialStore.loadTokens() else { return nil }
        if tokens.isAccessTokenFresh {
            return tokens.accessToken
        }
        guard hasRefreshToken(tokens) else { return nil }

        do {
            return try await refresh(tokens).accessToken
        } catch OIDCTokenRequestError.invalidSession {
            return nil
        } catch {
            // A timeout, offline device, locked Keychain or an IdP outage is
            // not a logout. Propagate the temporary failure without deleting
            // the refresh token.
            throw error
        }
    }

    func canUseExistingSession() async -> Bool {
        let tokens: TokenPair
        do {
            guard let storedTokens = try await credentialStore.loadTokens() else { return false }
            tokens = storedTokens
        } catch is DecodingError {
            // Corrupt local credentials cannot be recovered safely.
            try? await credentialStore.delete(account: "oidc")
            return false
        } catch {
            // Protected data can be temporarily unavailable while iOS is
            // locked. Preserve the logical session and retry after unlock.
            return true
        }

        if tokens.isAccessTokenFresh {
            return true
        }
        guard hasRefreshToken(tokens) else { return false }

        do {
            _ = try await refresh(tokens)
            return true
        } catch OIDCTokenRequestError.invalidSession {
            return false
        } catch {
            // Retain the device session during network and server outages.
            return true
        }
    }

    func saveTokens(_ tokens: TokenPair) async throws {
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        try await credentialStore.saveTokens(tokens)
    }

    func clear() async throws {
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        try await credentialStore.delete(account: "oidc")
    }

    private func hasRefreshToken(_ tokens: TokenPair) -> Bool {
        !(tokens.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func sessionRevision() -> UInt64 { sessionGeneration }

    /// Reject a different account before replacing the device credential.
    func saveReauthenticatedTokens(_ tokens: TokenPair, issuer: String, subject: String, revision: UInt64) async throws {
        guard revision == sessionGeneration else { throw CancellationError() }
        guard mobilityTokenMatchesSelectedActor(tokens.accessToken, issuer: issuer, subject: subject) else {
            throw CSMCOPSessionError(.accountChanged)
        }
        try await saveTokens(tokens)
    }

    private func refresh(_ tokens: TokenPair) async throws -> TokenPair {
        if let refreshTask { return try await refreshTask.value }
        // Another caller may have loaded an expired credential before the previous
        // flight committed its rotated token. Never refresh that stale snapshot.
        guard let current = try await credentialStore.loadTokens() else {
            throw OIDCTokenRequestError.invalidSession
        }
        if let refreshTask { return try await refreshTask.value }
        if current.isAccessTokenFresh { return current }
        let generation = sessionGeneration
        let task = Task { try await self.performRefresh(current, generation: generation) }
        refreshTask = task
        do {
            let result = try await task.value
            guard generation == sessionGeneration else { throw CancellationError() }
            refreshTask = nil
            return result
        } catch {
            if generation == sessionGeneration { refreshTask = nil }
            throw error
        }
    }

    private func performRefresh(_ tokens: TokenPair, generation: UInt64) async throws -> TokenPair {
        do {
            guard let refreshToken = tokens.refreshToken, !refreshToken.isEmpty else {
                throw OIDCTokenRequestError.invalidSession
            }
            let discovery = try await discoveryLoader.load()
            let refreshed = try await tokenExchanger.refresh(refreshToken: refreshToken,
                clientId: clientId, tokenEndpoint: discovery.tokenEndpoint, subjectId: tokens.subjectId)
            guard generation == sessionGeneration else { throw CancellationError() }
            // Commit once, before any waiter receives a token. Joined callers do
            // not write credentials or clear the shared flight themselves.
            try await credentialStore.saveTokens(refreshed)
            guard generation == sessionGeneration else { throw CancellationError() }
            return refreshed
        } catch OIDCTokenRequestError.invalidSession {
            guard generation == sessionGeneration else { throw CancellationError() }
            try? await credentialStore.delete(account: "oidc")
            throw OIDCTokenRequestError.invalidSession
        }
    }

}

enum AuthState: String, Sendable {
    case checking
    case locked
    case signedOut
    case signingIn
    case signedIn
}

@MainActor
struct PreviewAuthSession: AuthSessionManaging {
    var hasExistingSession = true

    func canUseExistingSession() async -> Bool {
        hasExistingSession
    }

    func signIn() async throws {
    }

    func signOut() async throws {
    }
}

#if os(iOS)
@MainActor
final class ProductionOIDCAuthSession: AuthSessionManaging {
    private let clientId: String
    private let issuer: URL
    private let redirectScheme: String
    private let scope: String
    private let tokenLifecycle: OIDCTokenLifecycle
    private let discoveryLoader: OIDCDiscoveryLoader
    private let authenticator: OIDCWebAuthenticator
    private let tokenExchanger: OIDCTokenExchanger

    init(
        issuer: URL,
        clientId: String,
        redirectScheme: String,
        scope: String,
        keychain: KeychainCredentialStore,
        session: URLSession = .shared,
        authenticator: OIDCWebAuthenticator = OIDCWebAuthenticator(),
        tokenExchanger: OIDCTokenExchanger = OIDCTokenExchanger(),
        tokenLifecycle: OIDCTokenLifecycle? = nil
    ) {
        self.clientId = clientId
        self.issuer = issuer
        self.redirectScheme = redirectScheme
        self.scope = scope
        self.tokenLifecycle = tokenLifecycle ?? OIDCTokenLifecycle(
            issuer: issuer,
            clientId: clientId,
            credentialStore: keychain,
            session: session
        )
        self.discoveryLoader = OIDCDiscoveryLoader(issuer: issuer, session: session)
        self.authenticator = authenticator
        self.tokenExchanger = tokenExchanger
    }

    func canUseExistingSession() async -> Bool {
        await tokenLifecycle.canUseExistingSession()
    }

    func signIn() async throws {
        try await signIn(forceAuthentication: false)
    }

    func signIn(forceAuthentication: Bool) async throws {
        let discovery = try await discoveryLoader.load()
        let tokenRequest = try await authenticator.authenticate(
            discovery: discovery,
            clientId: clientId,
            redirectScheme: redirectScheme,
            scope: scope,
            anchor: nil,
            forceAuthentication: forceAuthentication
        )
        let tokens = try await tokenExchanger.exchange(tokenRequest, tokenEndpoint: discovery.tokenEndpoint)
        try await tokenLifecycle.saveTokens(tokens)
    }

    func reauthenticate(expectedSubjectID: String) async throws {
        let revision = await tokenLifecycle.sessionRevision()
        let discovery = try await discoveryLoader.load()
        let request = try await authenticator.authenticate(discovery: discovery, clientId: clientId,
            redirectScheme: redirectScheme, scope: scope, anchor: nil, forceAuthentication: true)
        let tokens = try await tokenExchanger.exchange(request, tokenEndpoint: discovery.tokenEndpoint)
        try await tokenLifecycle.saveReauthenticatedTokens(tokens, issuer: issuer.absoluteString,
            subject: expectedSubjectID, revision: revision)
    }

    func signOut() async throws {
        try await tokenLifecycle.clear()
    }
}
#else
@MainActor
struct ProductionOIDCAuthSession: AuthSessionManaging {
    func canUseExistingSession() async -> Bool {
        false
    }

    func signIn() async throws {
        throw CSMServiceError.disabled("Interactive OIDC sign-in is available on iOS only.")
    }

    func signIn(forceAuthentication: Bool) async throws {
        try await signIn()
    }

    func signOut() async throws {
    }
}
#endif
