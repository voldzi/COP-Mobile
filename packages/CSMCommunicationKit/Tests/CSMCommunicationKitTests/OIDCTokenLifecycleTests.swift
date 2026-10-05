import Foundation
import XCTest
@testable import CSMCommunicationKit

final class OIDCTokenLifecycleTests: XCTestCase {
    private let issuer = URL(string: "https://identity.test/realms/cop")!
    override func tearDown() { OIDCStub.reset(); super.tearDown() }

    func testDeviceConsumersShareOneLifecycle() {
        let a = DeviceOIDCSession.shared.lifecycle(issuer: issuer, clientId: "test-client")
        let b = DeviceOIDCSession.shared.lifecycle(issuer: issuer, clientId: "test-client")
        XCTAssertTrue(a === b)
    }
    func testConcurrentConsumersRefreshAndCommitOnlyOnce() async throws {
        let store = MemoryOIDCCredentials(tokens: expired())
        OIDCStub.configure { _ in (200, #"{"access_token":"fresh","refresh_token":"rotated","expires_in":3600}"#) }
        let lifecycle = lifecycle(store)
        let values = try await withThrowingTaskGroup(of: String?.self) { group in
            for _ in 0..<24 { group.addTask { try await lifecycle.accessToken() } }
            var values: [String?] = []
            for try await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(values.count, 24)
        XCTAssertTrue(values.allSatisfy { $0 == "fresh" })
        XCTAssertEqual(OIDCStub.tokenRequestCount, 1)
        let saves = await store.saveCount
        XCTAssertEqual(saves, 1)
        let tokens = try await store.loadTokens()
        XCTAssertEqual(tokens?.refreshToken, "rotated")
    }
    func testTemporaryProviderFailurePreservesCredentialsAndLogicalSession() async throws {
        let original = expired(); let store = MemoryOIDCCredentials(tokens: original)
        OIDCStub.configure { _ in (503, #"{"error":"temporarily_unavailable"}"#) }
        let lifecycle = lifecycle(store)
        do { _ = try await lifecycle.accessToken(); XCTFail("Must fail temporarily") }
        catch { XCTAssertEqual(CSMMobilityFailureKind.classify(error), .serviceUnavailable) }
        let usable = await lifecycle.canUseExistingSession()
        XCTAssertTrue(usable)
        let tokens = try await store.loadTokens(); let deletes = await store.deleteCount
        XCTAssertEqual(tokens, original); XCTAssertEqual(deletes, 0)
    }
    func testTemporaryNetworkFailurePreservesCredentials() async throws {
        let original = expired(); let store = MemoryOIDCCredentials(tokens: original)
        OIDCStub.configure { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await lifecycle(store).accessToken(); XCTFail("Must fail offline") }
        catch { XCTAssertEqual(CSMMobilityFailureKind.classify(error), .temporaryNetwork) }
        let tokens = try await store.loadTokens(); XCTAssertEqual(tokens, original)
    }
    func testInvalidGrantRequiresReauthenticationWithoutDeletingMatrixMaterial() async throws {
        let store = MemoryOIDCCredentials(tokens: expired())
        OIDCStub.configure { _ in (400, #"{"error":"invalid_grant"}"#) }
        let value = try await lifecycle(store).accessToken()
        XCTAssertNil(value)
        let tokens = try await store.loadTokens(); let deleted = await store.deletedAccounts
        XCTAssertNil(tokens); XCTAssertEqual(deleted, ["oidc"])
    }
    func testSameAccountReauthenticationRestoresExpiredSession() async throws {
        let store = MemoryOIDCCredentials(tokens: nil); let lifecycle = lifecycle(store)
        let revision = await lifecycle.sessionRevision()
        let tokens = fresh(subject: "account-a")
        try await lifecycle.saveReauthenticatedTokens(tokens, issuer: issuer.absoluteString, subject: "account-a", revision: revision)
        let value = try await lifecycle.accessToken(); XCTAssertEqual(value, tokens.accessToken)
        let deletes = await store.deleteCount; XCTAssertEqual(deletes, 0)
    }
    func testDifferentAccountOrIssuerNeverReplacesCredentials() async throws {
        let original = fresh(subject: "account-a"); let store = MemoryOIDCCredentials(tokens: original)
        let lifecycle = lifecycle(store); let revision = await lifecycle.sessionRevision()
        for tokens in [fresh(subject: "account-b"), fresh(subject: "account-a", issuer: "https://wrong.test")] {
            do { try await lifecycle.saveReauthenticatedTokens(tokens, issuer: issuer.absoluteString, subject: "account-a", revision: revision); XCTFail("Wrong actor must fail") }
            catch { XCTAssertEqual(CSMMobilityFailureKind.classify(error), .accountChanged) }
        }
        let tokens = try await store.loadTokens(); XCTAssertEqual(tokens, original)
    }
    func testReauthenticationCannotOverwriteNewerSession() async throws {
        let store = MemoryOIDCCredentials(tokens: nil); let lifecycle = lifecycle(store)
        let revision = await lifecycle.sessionRevision(); let current = fresh(subject: "account-b")
        try await lifecycle.saveTokens(current)
        do { try await lifecycle.saveReauthenticatedTokens(fresh(subject: "account-a"), issuer: issuer.absoluteString, subject: "account-a", revision: revision); XCTFail("Stale browser must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        let tokens = try await store.loadTokens(); XCTAssertEqual(tokens, current)
    }
    func testExpiredCredentialWithoutRefreshRequiresAuthentication() async throws {
        var original = expired(); original.refreshToken = nil
        let value = try await lifecycle(MemoryOIDCCredentials(tokens: original)).accessToken()
        XCTAssertNil(value); XCTAssertEqual(OIDCStub.tokenRequestCount, 0)
    }
    func testPublicClassificationSeparatesAuthLimitsServiceAndMalformedResponses() {
        for (status, expected): (Int, CSMMobilityFailureKind) in [(401,.authenticationRequired),(403,.forbidden),(429,.rateLimited),(503,.serviceUnavailable),(404,.invalidResponse)] {
            XCTAssertEqual(CSMMobilityFailureKind.classify(CSMMobilityServiceFailure(statusCode: status, code: "TEST", message: "", correlationId: nil, retryAfter: nil)), expected)
        }
        XCTAssertEqual(CSMMobilityFailureKind.classify(CSMServiceError.disabled("")), .configuration)
        XCTAssertEqual(CSMMobilityFailureKind.classify(CSMServiceError.authenticationRequired("")), .authenticationRequired)
        XCTAssertEqual(CSMMobilityFailureKind.classify(CancellationError()), .cancelled)
        XCTAssertEqual(CSMMobilityFailureKind.classify(DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))), .invalidResponse)
    }
    private func lifecycle(_ store: MemoryOIDCCredentials) -> OIDCTokenLifecycle {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OIDCStub.self]
        return OIDCTokenLifecycle(issuer: issuer, clientId: "test-client", credentialStore: store, session: URLSession(configuration: config))
    }
    private func expired() -> TokenPair { .init(accessToken: "expired-synthetic", refreshToken: "synthetic-refresh", expiresAt: .distantPast, subjectId: "account-a") }
    private func fresh(subject: String, issuer: String? = nil) -> TokenPair {
        let claims = try! JSONSerialization.data(withJSONObject: ["iss":issuer ?? self.issuer.absoluteString,"sub":subject])
        let payload = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return .init(accessToken: "synthetic." + payload + ".synthetic", refreshToken: "synthetic-refresh", expiresAt: .distantFuture, subjectId: subject)
    }
}

private actor MemoryOIDCCredentials: TokenCredentialStoring {
    private var tokens: TokenPair?
    private(set) var saveCount = 0
    private(set) var deletedAccounts: [String] = []
    var deleteCount: Int { deletedAccounts.count }
    init(tokens: TokenPair?) { self.tokens = tokens }
    func saveTokens(_ tokens: TokenPair, account: String) throws { self.tokens = tokens; saveCount += 1 }
    func loadTokens(account: String) throws -> TokenPair? { tokens }
    func delete(account: String) throws { deletedAccounts.append(account); tokens = nil }
}

private final class OIDCStub: URLProtocol, @unchecked Sendable {
    private struct State { var handler: (@Sendable (URLRequest) throws -> (Int,String))?; var count = 0 }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()
    static var tokenRequestCount: Int { lock.withLock { state.count } }
    static func configure(_ handler: @escaping @Sendable (URLRequest) throws -> (Int,String)) { lock.withLock { state = State(handler:handler) } }
    static func reset() { lock.withLock { state = State() } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "identity.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let response: (Int,String)
            if request.url!.path.contains(".well-known") {
                response = (200,#"{"issuer":"https://identity.test/realms/cop","authorization_endpoint":"https://identity.test/authorize","token_endpoint":"https://identity.test/token"}"#)
            } else {
                let handler = Self.lock.withLock { Self.state.count += 1; return Self.state.handler! }
                Thread.sleep(forTimeInterval: 0.03)
                response = try handler(request)
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url:request.url!,statusCode:response.0,httpVersion:nil,headerFields:["Content-Type":"application/json"])!, cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self, didLoad:Data(response.1.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError:error) }
    }
    override func stopLoading() {}
}
