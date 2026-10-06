import Foundation
import XCTest
import Security
@preconcurrency import MatrixRustSDK
@testable import CSMCommunicationKit

@MainActor
final class MatrixLocalStoreTests: XCTestCase {
    func testAtomicKeychainCreationAcrossInstancesAndRestart() async throws {
        let service = "cop.matrix-store-tests." + UUID().uuidString
        let items = TestMatrixKeychainItems()
        let stores = (0..<24).map { _ in KeychainCredentialStore(service: service, matrixItems: items) }
        let values = try await withThrowingTaskGroup(of: Data.self) { group in
            for store in stores { group.addTask { try await store.loadOrCreateMatrixStoreKey(account: "isolated", allowCreation: true) } }
            var result: [Data] = []
            for try await value in group { result.append(value) }
            return result
        }
        let winner = try XCTUnwrap(values.first)
        XCTAssertEqual(Set(values).count, 1)
        XCTAssertEqual(Data(base64Encoded: String(decoding: winner, as: UTF8.self))?.count, 32)
        let restarted = KeychainCredentialStore(service: service, matrixItems: items)
        let reopened = try await restarted.loadOrCreateMatrixStoreKey(account: "isolated", allowCreation: false)
        XCTAssertEqual(reopened, winner)
        XCTAssertTrue(items.onlyWhenUnlockedThisDevice)
        XCTAssertEqual(items.storedCount, 1)
    }

    func testDuplicateAddLoadsTheWinnerWithoutReplacingIt() async throws {
        let winner = Data("already-established-key".utf8)
        let items = DuplicateWinningMatrixItems(winner: winner)
        let keys = KeychainCredentialStore(service: "synthetic", matrixItems: items)
        let result = try await keys.loadOrCreateMatrixStoreKey(account: "store", allowCreation: true)
        XCTAssertEqual(result, winner)
        XCTAssertEqual(items.addCount, 1)
        XCTAssertEqual(items.readCount, 2)
    }

    func testSystemKeychainCreateAndReopenWhenRunnerIsEntitled() async throws {
        let service = "cop.matrix-store-tests." + UUID().uuidString
        let first = KeychainCredentialStore(service: service)
        let value: Data
        do { value = try await first.loadOrCreateMatrixStoreKey(account: "isolated", allowCreation: true) }
        catch let error as MatrixLocalStoreError {
            if error.keychainStatus == errSecMissingEntitlement {
                throw XCTSkip("Package runner lacks a Keychain entitlement (OSStatus -34018); real iPhone acceptance is still required")
            }
            throw error
        }
        let reopened = try await KeychainCredentialStore(service: service).loadOrCreateMatrixStoreKey(account: "isolated", allowCreation: false)
        XCTAssertEqual(value, reopened)
        try await first.delete(account: "symmetric-key.isolated")
    }

    func testExistingDataWithMissingKeyFailsAndPreservesAllFiles() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let files = MatrixLocalStoreFiles(rootDirectory: root)
        let subject = "matrix.test|user-a|old-device"
        let crypto = root.appendingPathComponent(MatrixLocalStoreFiles.hash(subject) + "/data", isDirectory: true)
        try FileManager.default.createDirectory(at: crypto, withIntermediateDirectories: true)
        let database = crypto.appendingPathComponent("matrix-sdk-crypto.sqlite3")
        try Data().write(to: database)
        let preserved = root.appendingPathComponent("other-account-and-outbox")
        try Data("encrypted fixture".utf8).write(to: preserved)
        let keys = FixtureStoreKeys(value: nil)
        do {
            _ = try await files.prepare(inspection: files.inspect(subject: subject), subject: subject, keys: keys)
            XCTFail("An existing zero-length DB must never get a replacement key")
        } catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .missingKey) }
        let creationAllowed = await keys.creationPermissions
        XCTAssertEqual(creationAllowed, [false])
        XCTAssertEqual(try Data(contentsOf: database), Data())
        XCTAssertEqual(try Data(contentsOf: preserved), Data("encrypted fixture".utf8))
    }

    func testInvalidExistingKeysAreNeverReplaced() async throws {
        for key in [Data(), Data([0xff, 0xfe])] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let files = MatrixLocalStoreFiles(rootDirectory: root)
            let keys = FixtureStoreKeys(value: key)
            do {
                _ = try await files.prepare(inspection: files.inspect(subject: "a"), subject: "a", keys: keys)
                XCTFail("Invalid existing key must fail closed")
            } catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .invalidKey) }
            let retained = await keys.value
            XCTAssertEqual(retained, key)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(MatrixLocalStoreFiles.hash("a") + "/data").path))
        }
    }

    func testLockedKeychainDoesNotCreateStoreOrOfferRecovery() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let files = MatrixLocalStoreFiles(rootDirectory: root)
        let keys = FixtureStoreKeys(value: nil, failure: .deviceLocked)
        do {
            _ = try await files.prepare(inspection: files.inspect(subject: "locked"), subject: "locked", keys: keys)
            XCTFail("Locked device must fail without a reset")
        } catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .deviceLocked) }
        XCTAssertFalse(MatrixLocalStoreError(failure: .deviceLocked).permitsRecovery)
        XCTAssertFalse(MatrixLocalStoreError(failure: .keychainUnavailable).permitsRecovery)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(MatrixLocalStoreFiles.hash("locked")).path))
    }

    func testStoreRootAndNestedSymlinksAreRejectedWithoutTouchingTarget() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("protected", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let marker = target.appendingPathComponent("encrypted-history")
        try Data("preserved".utf8).write(to: marker)
        let link = root.appendingPathComponent("CSMMatrixRust")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try MatrixLocalStoreFiles(rootDirectory: link).inspect(subject: "a"))
        let real = root.appendingPathComponent("real", isDirectory: true)
        let hashedRoot = real.appendingPathComponent(MatrixLocalStoreFiles.hash("a"), isDirectory: true)
        try FileManager.default.createDirectory(at: hashedRoot, withIntermediateDirectories: true)
        try Data("first-file".utf8).write(to: hashedRoot.appendingPathComponent("a-file"))
        try FileManager.default.createSymbolicLink(at: hashedRoot.appendingPathComponent("z-link"), withDestinationURL: target)
        XCTAssertThrowsError(try MatrixLocalStoreFiles(rootDirectory: real).inspect(subject: "a"))
        XCTAssertEqual(try Data(contentsOf: marker), Data("preserved".utf8))
    }

    func testMatrixDirectoriesAreExcludedFromBackup() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let files = MatrixLocalStoreFiles(rootDirectory: root)
        let inspection = try files.inspect(subject: "backup")
        let prepared = try await files.prepare(inspection: inspection, subject: "backup", keys: FixtureStoreKeys(value: Data("existing-key".utf8)))
        for url in [root, inspection.root, URL(fileURLWithPath: prepared.dataPath), URL(fileURLWithPath: prepared.cachePath)] {
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
    }

    func testInitializationIsSerialAndCancelledWaiterDoesNotReleasePredecessor() async throws {
        let gate = MatrixInitializationGate()
        let probe = GateProbe()
        let started = expectation(description: "first owns gate")
        let first = Task {
            try await gate.withExclusive(key: "same") {
                await probe.enter(); started.fulfill()
                await probe.hold()
                await probe.leave()
            }
        }
        await fulfillment(of: [started], timeout: 3)
        let cancelled = Task {
            try await gate.withExclusive(key: "same") { await probe.enter(); await probe.leave() }
        }
        // Allow enqueue, then cancel a waiter while predecessor still owns the gate.
        for _ in 0..<20 { await Task.yield() }
        cancelled.cancel()
        let last = Task {
            try await gate.withExclusive(key: "same") { await probe.enter(); await probe.leave() }
        }
        let independent = try await gate.withExclusive(key: "other") { "independent" }
        XCTAssertEqual(independent, "independent")
        await probe.release()
        try await first.value
        do { try await cancelled.value; XCTFail("Cancelled waiter must not enter") } catch { XCTAssertTrue(error is CancellationError) }
        try await last.value
        let maximum = await probe.maximum
        let entries = await probe.entries
        XCTAssertEqual(maximum, 1)
        XCTAssertEqual(entries, 2)
    }

    func testPendingAndSelectedDeviceSurviveRestartAndAreAccountScoped() throws {
        let suite = "cop.matrix-routing-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = MatrixDeviceRecoveryRouting(defaults: defaults, scope: "issuer|client|cop|account-a|installation")
        let original = bootstrap(user: "@a:matrix.test")
        let pending = try a.reserve(original: original)
        XCTAssertNotEqual(pending.pendingDeviceID, original.deviceId)
        XCTAssertNil(try a.record()?.selectedDeviceID)
        let restarted = MatrixDeviceRecoveryRouting(defaults: defaults, scope: a.scope)
        XCTAssertEqual(try restarted.reserve(original: original), pending)
        let b = MatrixDeviceRecoveryRouting(defaults: defaults, scope: "issuer|client|cop|account-b|installation")
        let bPending = try b.reserve(original: bootstrap(user: "@b:matrix.test"))
        XCTAssertNotEqual(bPending.pendingDeviceID, pending.pendingDeviceID)
        XCTAssertThrowsError(try a.reserve(original: bootstrap(user: "@wrong:matrix.test")))
        try a.commit(pending)
        XCTAssertEqual(try restarted.record()?.selectedDeviceID, pending.pendingDeviceID)
        // A failed optional token-cache save does not mutate selected routing.
        XCTAssertEqual(try restarted.reserve(original: original).pendingDeviceID, pending.pendingDeviceID)
        XCTAssertEqual(try b.record(), bPending)
        let newInstall = MatrixDeviceRecoveryRouting(defaults: defaults, scope: "issuer|client|cop|account-a|different-installation")
        XCTAssertNil(try newInstall.record())
    }

    func testVerifierRetains401429And503Classification() async throws {
        for status in [401, 429, 503] {
            let session = identitySession(status: status, body: #"{"errcode":"M_UNKNOWN_TOKEN","error":"MUST_NOT_PROPAGATE"}"#)
            do {
                try await MatrixDeviceIdentityVerifier(session: session).verify(identity(), requireUnpublishedKeys: true)
                XCTFail("Must fail")
            } catch {
                guard case let MatrixAPIError.httpError(actual, detail) = error else { return XCTFail("HTTP failure must not become crypto reset") }
                XCTAssertEqual(actual, status)
                XCTAssertFalse(detail.contains("MUST_NOT_PROPAGATE"))
            }
            session.invalidateAndCancel()
        }
    }

    func testVerifierRejectsWrongDevicePublishedKeysAndPartialFailure() async throws {
        let responses = [
            #"{"user_id":"@a:matrix.test","device_id":"other-device"}"#,
            #"{"device_keys":{"@a:matrix.test":{"OLD":{}}}}"#,
            #"{"device_keys":{},"failures":{"matrix.test":{}}}"#,
            #"{"device_keys":{"@a:matrix.test":"invalid"}}"#
        ]
        for (index, response) in responses.enumerated() {
            let session = identitySession(status: 200, body: response, whoamiFirst: index != 0)
            do {
                try await MatrixDeviceIdentityVerifier(session: session).verify(identity(), requireUnpublishedKeys: true)
                XCTFail("Untrusted identity must be rejected")
            } catch { XCTAssertNotNil(error as? MatrixLocalStoreError) }
            session.invalidateAndCancel()
        }
    }

    func testVerifierAllowsOnlyMatchingUnpublishedFreshDevice() async throws {
        let session = identitySession(status: 200, body: #"{"device_keys":{"@a:matrix.test":{}},"failures":{}}"#, whoamiFirst: true)
        try await MatrixDeviceIdentityVerifier(session: session).verify(identity(), requireUnpublishedKeys: true)
        let requests = StoreIdentityURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/_matrix/client/v3/account/whoami")
        XCTAssertEqual(requests[1].httpMethod, "POST")
        let body = try XCTUnwrap(requests[1].httpBody ?? requests[1].httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = stream.read(&bytes, maxLength: bytes.count)
            return count > 0 ? Data(bytes.prefix(count)) : Data()
        })
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let devices = try XCTUnwrap(json["device_keys"] as? [String: [String]])
        XCTAssertEqual(devices, ["@a:matrix.test": ["OLD"]])
        session.invalidateAndCancel()
    }

    func testOfflineWrapperDoesNotHideTypedStoreFailureOrUnavailableLiveClient() async throws {
        let live = ConfigurableStoreMessagingClient()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        let original = bootstrap()
        try await wrapper.configure(with: original)
        await live.failNext(.cipherMismatch)
        var refreshed = original; refreshed.accessToken = "synthetic-refreshed-token"
        do { try await wrapper.configure(with: refreshed); XCTFail("Store failure must not be reported ready") }
        catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .cipherMismatch) }
        let error = await wrapper.latestTransportError(for: nil)
        XCTAssertNotNil(error)
        try await wrapper.configure(with: original)
        await live.failNextTransient(keepUsableSession: false)
        do { try await wrapper.configure(with: refreshed); XCTFail("Cleared live client must not be reported ready") }
        catch { XCTAssertTrue(error is URLError) }
    }

    func testOfflineWrapperKeepsOnlyActuallyUsableSessionDuringTransientFailure() async throws {
        let live = ConfigurableStoreMessagingClient()
        let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
        let original = bootstrap()
        try await wrapper.configure(with: original)
        await live.failNextTransient(keepUsableSession: true)
        var refreshed = original; refreshed.accessToken = "synthetic-refreshed-token"
        try await wrapper.configure(with: refreshed)
    }

    func testStaleTrueAndFalseAvailabilityCannotOverwriteNewerConfiguredSession() async throws {
        for response in [false, true] {
            let barrier = StoreAvailabilityBarrier(response: response)
            let live = RacingStoreMessaging(barrier: barrier)
            let wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: InMemoryMessageOutbox())
            let original = bootstrap()
            try await wrapper.configure(with: original)
            var stale = original; stale.accessToken = "synthetic-stale"
            let staleTask = Task { try await wrapper.configure(with: stale) }
            await barrier.waitUntilEntered()
            var current = original; current.accessToken = "synthetic-current"
            try await wrapper.configure(with: current)
            await barrier.release()
            do { try await staleTask.value; XCTFail("Stale availability must not publish either true or false readiness") }
            catch { XCTAssertTrue(error is CancellationError) }
            let conversations = try await PreviewCopAPIClient().conversations()
            _ = try await wrapper.messages(for: XCTUnwrap(conversations.first))
            let count = await live.configurations
            XCTAssertEqual(count, 3, "A healthy current session must not trigger another configure after stale false")
        }
    }

    func testRecoveryRequiresExplicitConfirmationAndDefaultPolicyIsDisabled() async throws {
        XCTAssertFalse(CSMChatStoreRecoveryPolicy.allowsWithoutBackup)
        let model = CommunicationModel(api: PreviewCopAPIClient(), messaging: PreviewMessagingClient(),
            localAI: DeterministicLocalAIService(), pushNotifications: StoreTestPush(),
            authSession: StoreTestAuth(), securityUnlock: PreviewSecurityUnlock())
        await model.start()
        do { try await model.recoverChatStore(authorization: .confirmedTestHistoryReset, confirmed: false); XCTFail("Never implicitly recover") }
        catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .recoveryRequired) }
    }

    func testActualRustCipherMismatchPreservesOriginalStoreAndReopensWithOriginalKey() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let protected = root.appendingPathComponent("other-account-outbox-history")
        let retained = Data("encrypted test fixture".utf8)
        try retained.write(to: protected)
        // Actual pinned Rust SDK, not a synthesized Swift error. No session,
        // tokens, homeserver login, sync, or network-backed chat are used here.
        var first: Client? = try await rustClient(data: data, cache: cache, passphrase: "original-test-key")
        try await first?.pause(); first = nil
        do {
            _ = try await rustClient(data: data, cache: cache, passphrase: "wrong-test-key")
            XCTFail("Rust must reject the wrong store passphrase")
        } catch {
            let classified = MatrixLocalStoreError.classifyBuilderFailure(error)
            XCTAssertEqual((classified as? MatrixLocalStoreError)?.failure, .cipherMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: protected), retained)
        let reopened = try await rustClient(data: data, cache: cache, passphrase: "original-test-key")
        try await reopened.pause()
    }

    func testActualRustEmptyCryptoDatabaseDoesNotCountAsExistingIdentity() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let files = MatrixLocalStoreFiles(rootDirectory: root.appendingPathComponent("CSMMatrixRust"))
        let subject = "https://matrix.test|@a:matrix.test|OLD"
        let prepared = try await files.prepare(inspection: files.inspect(subject: subject), subject: subject,
            keys: FixtureStoreKeys(value: Data("original-test-key".utf8)))
        var client: Client? = try await rustClient(data: URL(fileURLWithPath: prepared.dataPath), cache: URL(fileURLWithPath: prepared.cachePath), passphrase: "original-test-key")
        try await client?.pause(); client = nil
        let inspection = try files.inspect(subject: subject)
        XCTAssertTrue(inspection.hasStoredData)
        XCTAssertFalse(inspection.hasCryptoDatabase, "A real Rust-created SQLite DB without a stored Olm account is still a fresh identity")
        let session = identitySession(status: 200, body: #"{"device_keys":{"@a:matrix.test":{"OLD":{}}}}"#, whoamiFirst: true)
        let keychain = KeychainCredentialStore(service: "cop.matrix-store-tests." + UUID().uuidString)
        let adapter = MatrixRustE2EEMessagingClient(keychain: keychain,
            fileManager: StoreTestFileManager(applicationSupport: root),
            fixedStorePassphrase: "original-test-key", identityVerifier: MatrixDeviceIdentityVerifier(session: session))
        do { try await adapter.configure(with: bootstrap()); XCTFail("Fresh crypto identity cannot reuse published device") }
        catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .existingDeviceKeys) }
        XCTAssertEqual(try files.inspect(subject: subject).hasCryptoDatabase, false)
        let hasLiveSession = await adapter.hasUsableMessagingSession(for: bootstrap())
        XCTAssertFalse(hasLiveSession)
        session.invalidateAndCancel()
    }

    func testActualRustRestoredOlmAccountIsRecognizedWithoutDecryptingIt() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let files = MatrixLocalStoreFiles(rootDirectory: root)
        let subject = "http://127.0.0.1:1|@a:matrix.test|OLD"
        let prepared = try await files.prepare(inspection: files.inspect(subject: subject), subject: subject,
            keys: FixtureStoreKeys(value: Data("original-test-key".utf8)))
        var client: Client? = try await rustClient(data: URL(fileURLWithPath: prepared.dataPath), cache: URL(fileURLWithPath: prepared.cachePath), passphrase: "original-test-key")
        try await client?.restoreSessionWith(session: MatrixRustSDK.Session(accessToken: "synthetic-never-sent-to-production",
            refreshToken: nil, userId: "@a:matrix.test", deviceId: "OLD", homeserverUrl: "http://127.0.0.1:1",
            oauthData: nil, slidingSyncVersion: .none), roomLoadSettings: .all)
        await client?.encryption().waitForE2eeInitializationTasks()
        let ownKey = await client?.encryption().ed25519Key()
        XCTAssertNotNil(ownKey)
        try await client?.pause(); client = nil
        XCTAssertTrue(try files.inspect(subject: subject).hasCryptoDatabase)
    }

    func testTruncatedCryptoStoreNeverBypassesPublishedDeviceCheck() async throws {
        for bytes in [Data(), Data("truncated encrypted database".utf8)] {
            let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
            let files = MatrixLocalStoreFiles(rootDirectory: root.appendingPathComponent("CSMMatrixRust"))
            let subject = "https://matrix.test|@a:matrix.test|OLD"
            let data = try files.inspect(subject: subject).root.appendingPathComponent("data")
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let database = data.appendingPathComponent("matrix-sdk-crypto.sqlite3")
            try bytes.write(to: database)
            let session = identitySession(status: 200, body: #"{"device_keys":{"@a:matrix.test":{"OLD":{}}}}"#, whoamiFirst: true)
            let adapter = MatrixRustE2EEMessagingClient(keychain: KeychainCredentialStore(service: "cop.matrix-store-tests." + UUID().uuidString),
                fileManager: StoreTestFileManager(applicationSupport: root), fixedStorePassphrase: "original-test-key",
                identityVerifier: MatrixDeviceIdentityVerifier(session: session))
            do { try await adapter.configure(with: bootstrap()); XCTFail("Never replace crypto state on published device") }
            catch { XCTAssertEqual((error as? MatrixLocalStoreError)?.failure, .existingDeviceKeys) }
            XCTAssertEqual(try Data(contentsOf: database), bytes)
            session.invalidateAndCancel()
        }
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cop-matrix-store-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func bootstrap(user: String = "@a:matrix.test") -> MessagingBootstrap {
        MessagingBootstrap(accessToken: "synthetic-token", chatAvailable: true, contractVersion: "test",
            deviceId: "OLD", e2eeRequired: true, enabled: true, expiresAt: nil,
            homeserverBaseUrl: URL(string: "https://matrix.test")!, providerId: "matrix", serverName: "matrix.test",
            status: "online", tokenAvailable: true, userId: user, warnings: [])
    }
    private func identity() -> MatrixDeviceIdentityContext {
        MatrixDeviceIdentityContext(homeserver: URL(string: "https://matrix.test")!, userID: "@a:matrix.test", deviceID: "OLD", accessToken: "synthetic-token")
    }
    private func identitySession(status: Int, body: String, whoamiFirst: Bool = false) -> URLSession {
        StoreIdentityURLProtocol.configure(status: status, body: body, whoamiFirst: whoamiFirst)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StoreIdentityURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    private func rustClient(data: URL, cache: URL, passphrase: String) async throws -> Client {
        try await ClientBuilder().homeserverUrl(url: "http://127.0.0.1:1")
            .requestConfig(config: RequestConfig(retryLimit: 0, timeout: 500, maxConcurrentRequests: nil, maxRetryTime: 500))
            .sqliteStore(config: SqliteStoreBuilder(dataPath: data.path, cachePath: cache.path).passphrase(passphrase: passphrase))
            .autoEnableBackups(autoEnableBackups: false).autoEnableCrossSigning(autoEnableCrossSigning: false)
            .slidingSyncVersionBuilder(versionBuilder: .none).build()
    }
}

private actor FixtureStoreKeys: MatrixStoreKeyAccessing {
    let value: Data?
    let failure: CSMChatLocalStoreFailure?
    private(set) var creationPermissions: [Bool] = []
    init(value: Data?, failure: CSMChatLocalStoreFailure? = nil) { self.value = value; self.failure = failure }
    func loadOrCreateMatrixStoreKey(account: String, allowCreation: Bool) throws -> Data {
        creationPermissions.append(allowCreation)
        if let failure { throw MatrixLocalStoreError(failure: failure) }
        guard let value else { throw MatrixLocalStoreError(failure: .missingKey) }
        return value
    }
}
private actor GateProbe {
    private var active = 0
    private(set) var maximum = 0
    private(set) var entries = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func enter() { active += 1; entries += 1; maximum = max(maximum, active) }
    func leave() { active -= 1 }
    func hold() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private final class StoreTestFileManager: FileManager, @unchecked Sendable {
    let applicationSupport: URL
    init(applicationSupport: URL) { self.applicationSupport = applicationSupport; super.init() }
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] { [applicationSupport] }
}
private final class StoreIdentityURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var response: (Int, String, Bool) = (503, "{}", false)
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] { lock.withLock { recorded } }
    static func configure(status: Int, body: String, whoamiFirst: Bool) { lock.withLock { response = (status, body, whoamiFirst); recorded = [] } }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "matrix.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body, whoamiFirst) = Self.lock.withLock { Self.recorded.append(request); return Self.response }
        let effective = whoamiFirst && request.url?.path.hasSuffix("/whoami") == true
            ? #"{"user_id":"@a:matrix.test","device_id":"OLD"}"# : body
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(effective.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private actor ConfigurableStoreMessagingClient: MessagingClientProtocol, MessagingSessionAvailability {
    private var configured: MessagingBootstrap?
    private var failure: (any Error)?
    private var keepsSession = false
    func failNext(_ reason: CSMChatLocalStoreFailure) { failure = MatrixLocalStoreError(failure: reason); keepsSession = false }
    func failNextTransient(keepUsableSession: Bool) { failure = URLError(.notConnectedToInternet); keepsSession = keepUsableSession }
    func configure(with bootstrap: MessagingBootstrap) throws {
        if let failure { self.failure = nil; if !keepsSession { configured = nil }; throw failure }
        configured = bootstrap
    }
    func hasUsableMessagingSession(for bootstrap: MessagingBootstrap) -> Bool {
        configured?.userId == bootstrap.userId && configured?.deviceId == bootstrap.deviceId
    }
    func messages(for conversation: Conversation) throws -> [ChatMessage] { guard configured != nil else { throw MatrixAPIError.missingBootstrap }; return [] }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { throw MatrixAPIError.missingBootstrap }
}
@MainActor private final class StoreTestAuth: AuthSessionManaging {
    func canUseExistingSession() async -> Bool { true }
    func signIn() async throws {}
    func signOut() async throws {}
}
@MainActor private final class StoreTestPush: PushNotificationManaging {
    var currentSnapshot: MobilePushSnapshot { .unavailable }
    func prepareForRemoteNotifications() async -> MobilePushSnapshot { .unavailable }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}

private final class TestMatrixKeychainItems: MatrixKeychainItemAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Data] = [:]
    private var accessibleOnly = true
    var onlyWhenUnlockedThisDevice: Bool { lock.withLock { accessibleOnly } }
    var storedCount: Int { lock.withLock { stored.count } }
    private func key(_ query: [String: Any]) -> String { "\(query[kSecAttrService as String] ?? "")|\(query[kSecAttrAccount as String] ?? "")" }
    func read(query: [String: Any]) -> (Int32, Data?) {
        lock.withLock {
            if let value = stored[key(query)] { return (errSecSuccess, value) }
            return (errSecItemNotFound, nil)
        }
    }
    func add(query: [String: Any]) -> Int32 {
        lock.withLock {
            let account = key(query)
            if stored[account] != nil { return errSecDuplicateItem }
            accessibleOnly = accessibleOnly && (query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
            stored[account] = query[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
}
private final class DuplicateWinningMatrixItems: MatrixKeychainItemAccessing, @unchecked Sendable {
    let winner: Data
    private let lock = NSLock()
    private var added = false
    private(set) var addCount = 0
    private(set) var readCount = 0
    init(winner: Data) { self.winner = winner }
    func read(query: [String: Any]) -> (Int32, Data?) {
        lock.withLock { readCount += 1; return added ? (errSecSuccess, winner) : (errSecItemNotFound, nil) }
    }
    func add(query: [String: Any]) -> Int32 {
        lock.withLock { addCount += 1; added = true; return errSecDuplicateItem }
    }
}

private actor StoreAvailabilityBarrier {
    let response: Bool
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    init(response: Bool) { self.response = response }
    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func enterAndWait() async -> Bool {
        entered = true; entryWaiter?.resume(); entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return response
    }
    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}
private actor RacingStoreMessaging: MessagingClientProtocol, MessagingSessionAvailability {
    let barrier: StoreAvailabilityBarrier
    private(set) var configurations = 0
    init(barrier: StoreAvailabilityBarrier) { self.barrier = barrier }
    func configure(with bootstrap: MessagingBootstrap) throws {
        configurations += 1
        if configurations == 2 { throw URLError(.notConnectedToInternet) }
    }
    func hasUsableMessagingSession(for bootstrap: MessagingBootstrap) async -> Bool { await barrier.enterAndWait() }
    func messages(for conversation: Conversation) -> [ChatMessage] { [] }
    func sendMessage(_ body: String, to conversation: Conversation) throws -> ChatMessage { throw MatrixAPIError.missingBootstrap }
}
