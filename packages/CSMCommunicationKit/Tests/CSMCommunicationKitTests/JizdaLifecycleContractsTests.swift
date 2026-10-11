import Foundation
import Security
import XCTest
@testable import CSMCommunicationKit

final class JizdaLifecycleContractsTests: XCTestCase {
    private func dedicated() -> CSMJizdaLifecyclePolicy {
        .init(appScope: "jizda_app_link", clientID: "jizda-mobile", redirectScheme: "jizda-cop")
    }
    func testDefaultClientDoesNotOptInAndDedicatedRequiresExactConfiguration() {
        let ordinary = CSMJizdaLifecyclePolicy(appScope: nil, clientID: "csm-mobile", redirectScheme: "csm")
        XCTAssertFalse(ordinary.required)
        XCTAssertEqual(ordinary.snapshot.readiness, .notRequired)
        for (scope, client, redirect): (String?, String, String) in [(nil, "jizda-mobile", "jizda-cop"), ("jizda_app_link", "csm-mobile", "csm"), ("jizda_app_link", "jizda-mobile", "csm"), ("jizda_app_link", "other-jizda-mobile", "jizda-cop")] {
            let policy = CSMJizdaLifecyclePolicy(appScope: scope, clientID: client, redirectScheme: redirect)
            XCTAssertTrue(policy.required)
            XCTAssertFalse(policy.configured)
            XCTAssertFalse(policy.snapshot.permitsProducers)
            XCTAssertEqual(policy.snapshot.readiness, .configurationInvalid)
        }
    }
    func testUnknownColdStartAndFailedVerificationCannotUseCachedReady() {
        var policy = dedicated()
        XCTAssertFalse(policy.snapshot.permitsProducers)
        let epoch = policy.beginVerification()
        XCTAssertEqual(policy.snapshot.readiness, .checking)
        XCTAssertTrue(policy.failed(epoch: epoch))
        XCTAssertEqual(policy.snapshot.readiness, .unavailable)
        XCTAssertFalse(policy.snapshot.permitsProducers)
        XCTAssertTrue(policy.verified(status: "linked", persistedFence: false, epoch: epoch))
        XCTAssertTrue(policy.snapshot.permitsProducers)
        policy.resetAccount()
        XCTAssertFalse(policy.snapshot.permitsProducers)
        XCTAssertEqual(policy.snapshot.readiness, .verificationRequired)
    }
    func testAcceptedFenceCannotBeResurrectedByForegroundOrDelayedLinkedReceipt() {
        var policy = dedicated()
        let epoch = policy.beginVerification()
        XCTAssertTrue(policy.verified(status: "linked", persistedFence: false, epoch: epoch))
        XCTAssertTrue(policy.acceptFence(epoch: epoch))
        _ = policy.beginVerification()
        XCTAssertTrue(policy.verified(status: "linked", persistedFence: false, epoch: epoch))
        XCTAssertFalse(policy.snapshot.permitsProducers)
        XCTAssertTrue(policy.failed(epoch: epoch))
        XCTAssertEqual(policy.snapshot.readiness, .suspended)
    }
    func testPendingCompletedAndPersistedFencesStaySuspended() {
        for (status, persisted) in [("disconnecting", false), ("disconnected", false), ("linked", true), ("unknown", false)] {
            var policy = dedicated()
            let epoch = policy.beginVerification()
            XCTAssertTrue(policy.verified(status: status, persistedFence: persisted, epoch: epoch))
            XCTAssertTrue(policy.acceptedFence)
            XCTAssertFalse(policy.snapshot.permitsProducers)
            XCTAssertEqual(policy.snapshot.readiness, .suspended)
        }
    }
    func testDelayedAccountAResultsCannotChangeAccountBReadiness() {
        var policy = dedicated()
        let oldEpoch = policy.beginVerification()
        policy.resetAccount()
        let current = policy.snapshot
        XCTAssertNotEqual(oldEpoch, current.generation)
        XCTAssertFalse(policy.verified(status: "linked", persistedFence: false, epoch: oldEpoch))
        XCTAssertFalse(policy.failed(epoch: oldEpoch))
        XCTAssertFalse(policy.acceptFence(epoch: oldEpoch))
        XCTAssertEqual(policy.snapshot, current)
    }
    func testTransportPreparationCannotAdvertiseReadyUntilClientIsConfigured() {
        var policy = dedicated()
        let epoch = policy.beginVerification()
        XCTAssertTrue(policy.verified(status: "linked", persistedFence: false, epoch: epoch))
        XCTAssertTrue(policy.beginTransportPreparation(epoch: epoch))
        XCTAssertEqual(policy.snapshot.readiness, .transportPreparing)
        XCTAssertFalse(policy.snapshot.permitsProducers)
        XCTAssertTrue(policy.permitsTransportPreparation)
        XCTAssertTrue(policy.finishTransportPreparation(epoch: epoch, succeeded: false))
        XCTAssertEqual(policy.snapshot.readiness, .transportUnavailable)
        XCTAssertFalse(policy.snapshot.permitsProducers)
        XCTAssertTrue(policy.permitsTransportPreparation)
        XCTAssertTrue(policy.finishTransportPreparation(epoch: epoch, succeeded: true))
        XCTAssertTrue(policy.snapshot.permitsProducers)
        XCTAssertTrue(policy.acceptFence(epoch: epoch))
        XCTAssertFalse(policy.permitsTransportPreparation)
        XCTAssertFalse(policy.finishTransportPreparation(epoch: epoch, succeeded: true))
    }
    func testDelayedTransportCannotRestoreReadinessOfAnotherAccount() {
        var policy = dedicated()
        let epoch = policy.beginVerification()
        _ = policy.verified(status: "linked", persistedFence: false, epoch: epoch)
        _ = policy.beginTransportPreparation(epoch: epoch)
        policy.resetAccount()
        let expected = policy.snapshot
        XCTAssertFalse(policy.finishTransportPreparation(epoch: epoch, succeeded: true))
        XCTAssertEqual(policy.snapshot, expected)
    }
    func testDriverMeasurementDedicatedClientRequiresExactOptInAndReadyWrites() {
        var ordinary = AppConfiguration.preview
        ordinary.usePreviewServices = false
        XCTAssertTrue(CSMDriverMeasurementAccessPolicy.allowsConfiguration(ordinary))
        var selected = ordinary
        selected.oidcClientId = "jizda-mobile"
        selected.oidcRedirectScheme = "jizda-cop"
        XCTAssertFalse(CSMDriverMeasurementAccessPolicy.allowsConfiguration(selected))
        selected.appScope = "jizda_app_link"
        XCTAssertTrue(CSMDriverMeasurementAccessPolicy.allowsConfiguration(selected))
        selected.oidcClientId = "other-jizda-mobile"
        XCTAssertFalse(CSMDriverMeasurementAccessPolicy.allowsConfiguration(selected))
        XCTAssertFalse(CSMDriverMeasurementAccessPolicy.requiresReadyProducers(.readConsent))
        XCTAssertFalse(CSMDriverMeasurementAccessPolicy.requiresReadyProducers(.revokeConsent))
        XCTAssertTrue(CSMDriverMeasurementAccessPolicy.requiresReadyProducers(.grantConsent))
        XCTAssertTrue(CSMDriverMeasurementAccessPolicy.requiresReadyProducers(.submitBatch))
    }
    func testBundleOptInPreservesOldDefaultsAndRedirectBuilderInput() {
        let ordinary = AppConfiguration.fromInfoDictionary([:])
        XCTAssertNil(ordinary.appScope)
        XCTAssertEqual(ordinary.oidcClientId, "csm-mobile")
        XCTAssertEqual(ordinary.oidcRedirectScheme, "csm")
        let selected = AppConfiguration.fromInfoDictionary(["CSMAppScope": "jizda_app_link", "CSMOIDCClientId": "jizda-mobile", "CSMOIDCRedirectScheme": "jizda-cop"])
        XCTAssertEqual(selected.appScope, "jizda_app_link")
        XCTAssertEqual("\(selected.oidcRedirectScheme)://oauth/callback", "jizda-cop://oauth/callback")
    }
    func testBootstrapInstallationIsOptionalAndLegacyPayloadStaysExact() throws {
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MessagingBootstrapRequest(deviceId: "device"))) as? [String: Any])
        XCTAssertEqual(Set(old.keys), ["deviceId"])
        let id = UUID()
        let selected = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(MessagingBootstrapRequest(deviceId: "device", installationId: id))) as? [String: Any])
        XCTAssertEqual(Set(selected.keys), ["deviceId", "installationId"])
        XCTAssertEqual((selected["installationId"] as? String).flatMap(UUID.init(uuidString:)), id)
        XCTAssertNil(selected["appClientId"])
        XCTAssertNil(selected["subjectId"])
    }
    func testSecureInstallationMigrationIsStableAndFencesAreScoped() async throws {
        let items = LifecycleKeychainItems()
        let first = KeychainCredentialStore(service: "isolated-test", matrixItems: items)
        let second = KeychainCredentialStore(service: "isolated-test", matrixItems: items)
        let legacy = UUID()
        let installed = try await first.loadOrCreateInstallationID(scope: "account-a", legacyCandidate: legacy)
        let reread = try await second.loadOrCreateInstallationID(scope: "account-a", legacyCandidate: UUID())
        XCTAssertEqual(installed, legacy)
        XCTAssertEqual(reread, legacy)
        try await first.saveJizdaAcceptedFence(scope: "issuer-client-host-account-a-installation-a")
        let accepted = try await second.hasJizdaAcceptedFence(scope: "issuer-client-host-account-a-installation-a")
        let otherAccount = try await second.hasJizdaAcceptedFence(scope: "issuer-client-host-account-b-installation-a")
        let otherInstallation = try await second.hasJizdaAcceptedFence(scope: "issuer-client-host-account-a-installation-b")
        XCTAssertTrue(accepted)
        XCTAssertFalse(otherAccount)
        XCTAssertFalse(otherInstallation)
        XCTAssertTrue(items.onlyWhenUnlockedThisDevice)
        XCTAssertEqual(items.storedCount, 2)
    }
    func testCorruptSecureInstallationOrFenceFailsWithoutReplacement() async throws {
        let items = LifecycleKeychainItems()
        items.seed(account: "jizda-installation.account-a", data: Data("not-a-uuid".utf8))
        items.seed(account: "jizda-link-fence.account-a", data: Data("corrupt".utf8))
        let store = KeychainCredentialStore(service: "isolated-test", matrixItems: items)
        do { _ = try await store.loadOrCreateInstallationID(scope: "account-a", legacyCandidate: UUID()); XCTFail("Corrupt installation accepted") } catch { }
        do { _ = try await store.hasJizdaAcceptedFence(scope: "account-a"); XCTFail("Corrupt fence accepted") } catch { }
        do { try await store.saveJizdaAcceptedFence(scope: "account-a"); XCTFail("Corrupt fence replaced") } catch { }
        XCTAssertEqual(items.addCount, 0)
    }
    func testLiveLinkCheckUsesUncachedAuthenticatedRead() async throws {
        LifecycleHTTPProtocol.state.configure(status: 200)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let http = HTTPClient(baseURL: URL(string: "https://cop.test")!, tokenProvider: LifecycleTestToken(), session: session, requiresAuthorization: true)
        let receipt: CSMJizdaLinkReceipt = try await http.getVerifiedUncached("/api/v1/me/app-links/jizda")
        XCTAssertEqual(receipt.status, "linked")
        let request = try XCTUnwrap(LifecycleHTTPProtocol.state.lastRequest)
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
        XCTAssertEqual(request.url?.absoluteString, "https://cop.test/api/v1/me/app-links/jizda")
    }
    func testLiveLinkCheckRejectsWrongStatusOriginAndOversizeResponse() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let http = HTTPClient(baseURL: URL(string: "https://cop.test")!, tokenProvider: LifecycleTestToken(), session: session, requiresAuthorization: true)
        for (status, origin, oversized) in [(202, false, false), (302, false, false), (503, false, false), (200, true, false), (200, false, true)] {
            LifecycleHTTPProtocol.state.configure(status: status, wrongOrigin: origin, oversized: oversized)
            do { let _: CSMJizdaLinkReceipt = try await http.getVerifiedUncached("/api/v1/me/app-links/jizda"); XCTFail("Invalid permission accepted") } catch { }
        }
    }
    func testLiveLinkCheckRejectsUntrustedBaseBeforeHTTP() async throws {
        LifecycleHTTPProtocol.state.configure(status: 200)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LifecycleHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for url in ["http://cop.test", "https://user:password@cop.test", "https://cop.test/path", "https://cop.test?source=unsafe"] {
            let http = HTTPClient(baseURL: URL(string: url)!, tokenProvider: LifecycleTestToken(), session: session, requiresAuthorization: true)
            do { let _: CSMJizdaLinkReceipt = try await http.getVerifiedUncached("/api/v1/me/app-links/jizda"); XCTFail("Untrusted base accepted") } catch { }
        }
        XCTAssertNil(LifecycleHTTPProtocol.state.lastRequest)
    }

    func testSafetyRollbackPreservesRetryAndUnblockButDisablesNewActions() {
        XCTAssertFalse(CSMCommunicationSafetyActionPolicy.permitsReport(reporting: false, pending: false))
        XCTAssertTrue(CSMCommunicationSafetyActionPolicy.permitsReport(reporting: false, pending: true))
        XCTAssertTrue(CSMCommunicationSafetyActionPolicy.permitsReport(reporting: nil, pending: true))
        XCTAssertFalse(CSMCommunicationSafetyActionPolicy.permitsBlock(blocking: false, currentlyBlocked: false))
        XCTAssertTrue(CSMCommunicationSafetyActionPolicy.permitsBlock(blocking: false, currentlyBlocked: true))
        XCTAssertFalse(CSMCommunicationSafetyActionPolicy.permitsBlock(blocking: true, currentlyBlocked: nil))
    }
    func testSafetyContactUsesOnlyApprovedPlainMailAddress() {
        XCTAssertEqual(CSMCommunicationSafetyActionPolicy.contactURL(email: "podpora@zeleznalady.cz")?.absoluteString,
                       "mailto:podpora@zeleznalady.cz")
        for email in [nil, "other@example.test", "podpora@zeleznalady.cz?subject=private", "podpora@zeleznalady.cz\nother@example.test"] {
            XCTAssertNil(CSMCommunicationSafetyActionPolicy.contactURL(email: email))
        }
    }
    func testLifecycleSnapshotBindsOpaqueScopeAndGeneration() {
        let epoch = UUID()
        let first = CSMJizdaLifecycleSnapshot(readiness: .suspended, generation: epoch, scope: "opaque-a")
        XCTAssertEqual(first.scope, "opaque-a")
        XCTAssertFalse(first.permitsProducers)
        XCTAssertNotEqual(first, CSMJizdaLifecycleSnapshot(readiness: .suspended, generation: epoch, scope: "opaque-b"))
        XCTAssertNotEqual(first, CSMJizdaLifecycleSnapshot(readiness: .suspended, generation: UUID(), scope: "opaque-a"))
        XCTAssertNil(CSMJizdaLifecycleSnapshot(readiness: .verificationRequired, generation: epoch).scope)
    }

}

private final class LifecycleKeychainItems: MatrixKeychainItemAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Data] = [:]
    private var accessibleOnly = true
    private var additions = 0
    var addCount: Int { lock.withLock { additions } }
    var storedCount: Int { lock.withLock { stored.count } }
    var onlyWhenUnlockedThisDevice: Bool { lock.withLock { accessibleOnly } }
    func seed(account: String, data: Data) { lock.withLock { stored["isolated-test|\(account)"] = data } }
    private func key(_ query: [String: Any]) -> String { "\(query[kSecAttrService as String] ?? "")|\(query[kSecAttrAccount as String] ?? "")" }
    func read(query: [String: Any]) -> (Int32, Data?) {
        lock.withLock { if let data = stored[key(query)] { return (errSecSuccess, data) }; return (errSecItemNotFound, nil) }
    }
    func add(query: [String: Any]) -> Int32 {
        lock.withLock {
            let key = key(query)
            if stored[key] != nil { return errSecDuplicateItem }
            additions += 1
            accessibleOnly = accessibleOnly && (query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            stored[key] = query[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
}

private struct LifecycleTestToken: AccessTokenProviding {
    func accessToken() async throws -> String? { "synthetic-test-token" }
}
private final class LifecycleHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var wrongOrigin = false
    private var oversized = false
    private var storedRequest: URLRequest?
    var lastRequest: URLRequest? { lock.withLock { storedRequest } }
    func configure(status: Int, wrongOrigin: Bool = false, oversized: Bool = false) {
        lock.withLock { self.status = status; self.wrongOrigin = wrongOrigin; self.oversized = oversized; storedRequest = nil }
    }
    func receive(_ request: URLRequest) -> (Int, Bool, Data) {
        lock.withLock {
            storedRequest = request
            let payload = oversized ? String(repeating: "x", count: 65_537)
                : #"{"contractVersion":"cop-jizda-link-v1","app":"jizda","scope":"jizda_app_link","status":"linked","accountDeleted":false,"localDataDeleted":false}"#
            return (status, wrongOrigin, Data(payload.utf8))
        }
    }
}
private final class LifecycleHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let state = LifecycleHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "cop.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, wrongOrigin, data) = Self.state.receive(request)
        let url = wrongOrigin ? URL(string: "https://other.test")! : request.url!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
