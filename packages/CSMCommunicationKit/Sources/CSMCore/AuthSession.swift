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
            try? await credentialStore.delete(account: "oidc")
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
            try? await credentialStore.delete(account: "oidc")
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

    private func refresh(_ tokens: TokenPair) async throws -> TokenPair {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refreshToken = tokens.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !refreshToken.isEmpty
        else {
            throw OIDCTokenRequestError.invalidSession
        }

        let discoveryLoader = discoveryLoader
        let tokenExchanger = tokenExchanger
        let clientId = clientId
        let generation = sessionGeneration
        let task = Task {
            let discovery = try await discoveryLoader.load()
            return try await tokenExchanger.refresh(
                refreshToken: refreshToken,
                clientId: clientId,
                tokenEndpoint: discovery.tokenEndpoint,
                subjectId: tokens.subjectId
            )
        }
        refreshTask = task

        do {
            let refreshedTokens = try await task.value
            guard generation == sessionGeneration else {
                throw CancellationError()
            }
            refreshTask = nil
            try await credentialStore.saveTokens(refreshedTokens)
            return refreshedTokens
        } catch {
            if generation == sessionGeneration {
                refreshTask = nil
            }
            throw error
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
