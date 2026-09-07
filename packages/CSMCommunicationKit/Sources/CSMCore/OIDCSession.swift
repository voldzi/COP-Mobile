import Foundation

struct OIDCDiscoveryDocument: Decodable, Equatable, Sendable {
    var authorizationEndpoint: URL
    var tokenEndpoint: URL
    var issuer: URL?

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case issuer
    }
}

/// Validates the trust boundary created by an OIDC discovery document before
/// any browser navigation or token request uses URLs supplied by that document.
struct OIDCDiscoveryValidator {
    private struct Origin: Equatable {
        var scheme: String
        var host: String
        var port: Int?
    }

    private struct NormalizedIssuer: Equatable {
        var origin: Origin
        var percentEncodedPath: String
    }

    static func validate(
        _ discovery: OIDCDiscoveryDocument,
        configuredIssuer: URL
    ) throws -> OIDCDiscoveryDocument {
        let configured = try normalizedIssuer(
            configuredIssuer,
            invalidMessage: "Configured OIDC issuer is not a secure absolute URL."
        )

        guard let declaredIssuer = discovery.issuer else {
            throw CSMServiceError.invalidState("OIDC discovery does not declare an issuer.")
        }
        let declared = try normalizedIssuer(
            declaredIssuer,
            invalidMessage: "OIDC discovery issuer is not a secure absolute URL."
        )
        guard declared == configured else {
            throw CSMServiceError.invalidState("OIDC discovery issuer does not match the configured issuer.")
        }

        try validateEndpoint(
            discovery.authorizationEndpoint,
            name: "authorization",
            expectedOrigin: configured.origin
        )
        try validateEndpoint(
            discovery.tokenEndpoint,
            name: "token",
            expectedOrigin: configured.origin
        )

        return discovery
    }

    static func validatedConfiguredIssuer(_ issuer: URL) throws -> URL {
        _ = try normalizedIssuer(
            issuer,
            invalidMessage: "Configured OIDC issuer is not a secure absolute URL."
        )
        return issuer
    }

    private static func normalizedIssuer(
        _ url: URL,
        invalidMessage: String
    ) throws -> NormalizedIssuer {
        let components = try secureComponents(
            for: url,
            allowsQuery: false,
            invalidMessage: invalidMessage
        )

        var path = components.percentEncodedPath
        if path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }

        return NormalizedIssuer(
            origin: origin(from: components),
            percentEncodedPath: path
        )
    }

    private static func validateEndpoint(
        _ url: URL,
        name: String,
        expectedOrigin: Origin
    ) throws {
        let invalidMessage = "OIDC discovery \(name) endpoint is not a secure absolute URL."
        let components = try secureComponents(
            for: url,
            allowsQuery: true,
            invalidMessage: invalidMessage
        )
        guard origin(from: components) == expectedOrigin else {
            throw CSMServiceError.invalidState(
                "OIDC discovery \(name) endpoint does not use the configured issuer origin."
            )
        }
    }

    private static func secureComponents(
        for url: URL,
        allowsQuery: Bool,
        invalidMessage: String
    ) throws -> URLComponents {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty,
            host == components.host,
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            allowsQuery || components.query == nil,
            components.port.map({ (1...65_535).contains($0) }) ?? true,
            !components.percentEncodedPath.contains("\\"),
            !components.percentEncodedPath.lowercased().contains("%5c")
        else {
            throw CSMServiceError.invalidState(invalidMessage)
        }
        return components
    }

    private static func origin(from components: URLComponents) -> Origin {
        Origin(
            scheme: components.scheme?.lowercased() ?? "",
            host: components.host?.lowercased() ?? "",
            port: components.port == 443 ? nil : components.port
        )
    }
}

struct OIDCTokenResponse: Decodable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: TimeInterval
    var idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

private struct OIDCTokenErrorResponse: Decodable {
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum OIDCTokenRequestError: LocalizedError, Equatable, Sendable {
    case invalidSession
    case rejected(statusCode: Int, errorCode: String?)

    var errorDescription: String? {
        switch self {
        case .invalidSession:
            return CSMLocalization.text(
                "auth.error.session_revoked",
                fallback: "Přihlášení bylo zneplatněno. Přihlaste se znovu."
            )
        case .rejected:
            return CSMLocalization.text(
                "auth.error.refresh_rejected",
                fallback: "Přihlášení se teď nepodařilo obnovit. Zkuste to znovu po obnovení spojení."
            )
        }
    }
}

struct OIDCTokenRequest: Sendable {
    var code: String
    var verifier: String
    var redirectURI: String
    var clientId: String
}

struct OIDCTokenExchanger: Sendable {
    var session: URLSession = .shared

    func exchange(_ request: OIDCTokenRequest, tokenEndpoint: URL) async throws -> TokenPair {
        let tokenResponse = try await performTokenRequest(fields: [
            "grant_type": "authorization_code",
            "code": request.code,
            "redirect_uri": request.redirectURI,
            "client_id": request.clientId,
            "code_verifier": request.verifier
        ], tokenEndpoint: tokenEndpoint, failureMessage: "OIDC token exchange failed.")

        return tokenPair(from: tokenResponse, fallbackRefreshToken: nil, subjectId: nil)
    }

    func refresh(refreshToken: String, clientId: String, tokenEndpoint: URL, subjectId: String? = nil) async throws -> TokenPair {
        let tokenResponse = try await performTokenRequest(fields: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ], tokenEndpoint: tokenEndpoint, failureMessage: "OIDC token refresh failed.")

        return tokenPair(from: tokenResponse, fallbackRefreshToken: refreshToken, subjectId: subjectId)
    }

    private func performTokenRequest(
        fields: [String: String],
        tokenEndpoint: URL,
        failureMessage: String
    ) async throws -> OIDCTokenResponse {
        var urlRequest = URLRequest(url: tokenEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = formEncoded(fields)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CSMServiceError.unavailable(failureMessage)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let oauthError = try? CSMJSONCoding.decoder.decode(OIDCTokenErrorResponse.self, from: data)
            if oauthError?.error == "invalid_grant" {
                throw OIDCTokenRequestError.invalidSession
            }
            throw OIDCTokenRequestError.rejected(
                statusCode: httpResponse.statusCode,
                errorCode: oauthError?.error
            )
        }
        let tokenResponse = try CSMJSONCoding.decoder.decode(OIDCTokenResponse.self, from: data)
        return tokenResponse
    }

    private func tokenPair(
        from tokenResponse: OIDCTokenResponse,
        fallbackRefreshToken: String?,
        subjectId: String?
    ) -> TokenPair {
        return TokenPair(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? fallbackRefreshToken,
            expiresAt: Date().addingTimeInterval(tokenResponse.expiresIn),
            subjectId: subjectId
        )
    }

    private func formEncoded(_ fields: [String: String]) -> Data {
        fields
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

#if os(iOS)
import AuthenticationServices
import UIKit

@MainActor
final class OIDCWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var presentationAnchor: ASPresentationAnchor?
    private var session: ASWebAuthenticationSession?

    func authenticate(
        discovery: OIDCDiscoveryDocument,
        clientId: String,
        redirectScheme: String,
        scope: String,
        anchor: ASPresentationAnchor?,
        forceAuthentication: Bool = false
    ) async throws -> OIDCTokenRequest {
        let pkce = try PKCEChallenge.generate()
        let redirectURI = "\(redirectScheme)://oauth/callback"
        let state = UUID().uuidString
        let nonce = UUID().uuidString
        self.presentationAnchor = anchor ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first

        guard var components = URLComponents(url: discovery.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
            throw CSMServiceError.invalidState("Invalid OIDC authorization endpoint.")
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method)
        ]
        if forceAuthentication {
            components.queryItems?.append(URLQueryItem(name: "prompt", value: "login"))
        }
        guard let authorizationURL = components.url else {
            throw CSMServiceError.invalidState("Invalid OIDC authorization URL.")
        }

        let callbackURL = try await callbackURL(for: authorizationURL, callbackURLScheme: redirectScheme)
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            callbackComponents.queryItems?.first(where: { $0.name == "state" })?.value == state,
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw CSMServiceError.invalidState("OIDC callback did not contain a valid code/state.")
        }

        return OIDCTokenRequest(
            code: code,
            verifier: pkce.verifier,
            redirectURI: redirectURI,
            clientId: clientId
        )
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let presentationAnchor {
            return presentationAnchor
        }
        if let windowScene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let anchor = ASPresentationAnchor(windowScene: windowScene)
            presentationAnchor = anchor
            return anchor
        }
        preconditionFailure("OIDC login requires an active UIWindowScene.")
    }

    private func callbackURL(for authorizationURL: URL, callbackURLScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? CSMServiceError.unavailable("OIDC login was cancelled."))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }
}
#endif
