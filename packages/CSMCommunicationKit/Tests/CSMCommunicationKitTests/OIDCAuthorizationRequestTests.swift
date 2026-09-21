import Foundation
import XCTest

@testable import CSMCommunicationKit

final class OIDCAuthorizationRequestTests: XCTestCase {
    func testRegularSignInCanReuseOrganizationBrowserSession() throws {
        let policy = OIDCInteractiveAuthenticationPolicy(forceAuthentication: false)
        let url = try makeAuthorizationURL(policy: policy)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertNil(query.first(where: { $0.name == "prompt" }))
        XCTAssertFalse(policy.prefersEphemeralWebBrowserSession)
    }

    func testDifferentAccountForcesCredentialsInIsolatedBrowserSession() throws {
        let policy = OIDCInteractiveAuthenticationPolicy(forceAuthentication: true)
        let url = try makeAuthorizationURL(policy: policy)
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(query.first(where: { $0.name == "prompt" })?.value, "login")
        XCTAssertTrue(policy.prefersEphemeralWebBrowserSession)
    }

    private func makeAuthorizationURL(policy: OIDCInteractiveAuthenticationPolicy) throws -> URL {
        try OIDCAuthorizationRequestBuilder.makeURL(
            authorizationEndpoint: XCTUnwrap(URL(string: "https://auth.example.test/authorize")),
            clientId: "mobile-client",
            redirectURI: "csm://oauth/callback",
            scope: "openid profile offline_access",
            state: "state-value",
            nonce: "nonce-value",
            challenge: "challenge-value",
            challengeMethod: "S256",
            policy: policy
        )
    }
}
