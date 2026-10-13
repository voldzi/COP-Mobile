import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class ScopedVoiceHTTPTests: XCTestCase {
    private let issuer = URL(string: "https://identity.test/realms/cop")!

    override func tearDown() { VoiceHTTPStub.reset(); super.tearDown() }

    func testAllFourPathsRejectAccountSwitchDuringRealTokenAcquisition() async throws {
        for operation in VoiceOperation.allCases {
            VoiceHTTPStub.configure(response: try responseData())
            let store = VoiceCredentials(tokens: token("actor-a")), lifecycle = lifecycle(store)
            let pause = VoiceTokenPause(), provider = PausedVoiceTokens(lifecycle: lifecycle, pause: pause)
            let state = VoiceFenceState(), scope = state.capture(issuer: issuer.absoluteString)
            let api = api(provider)
            let request = Task { try await operation.perform(api, scope: scope) }
            try await waitUntil { await pause.entered }
            // Expired B must be rejected before even starting B's refresh.
            try await lifecycle.saveTokens(token("actor-b", fresh: false))
            state.subject = "actor-b"; state.generation = UUID()
            await pause.release()
            do { try await request.value; XCTFail("Stale A request must fail") } catch { }
            XCTAssertEqual(VoiceHTTPStub.records.count, 0)
            let unscoped = await provider.unscopedCount
            XCTAssertEqual(unscoped, 0)
        }
    }

    func testLifecycleRevisionChangesWhileActualCredentialReadIsPaused() async throws {
        VoiceHTTPStub.configure(response: try responseData())
        let gate = VoiceBlockingRead(), store = VoiceCredentials(tokens: token("actor-a"), gate: gate)
        let lifecycle = lifecycle(store), state = VoiceFenceState(), scope = state.capture(issuer: issuer.absoluteString)
        let api = api(lifecycle)
        let request = Task { try await VoiceOperation.start.perform(api, scope: scope) }
        defer { gate.release() }
        try await waitUntil { gate.entered }
        let replacement = token("actor-b")
        let saving = Task { try await lifecycle.saveTokens(replacement) }
        try await waitUntil { await lifecycle.sessionRevision() == 1 }
        state.subject = "actor-b"; state.generation = UUID()
        gate.release()
        try await saving.value
        do { try await request.value; XCTFail("Changed credential revision must fail") } catch { }
        XCTAssertEqual(VoiceHTTPStub.records.count, 0)
    }

    func testWithdrawalAndSameActorNewGenerationPreventEveryFurtherRetry() async throws {
        for withdrawal in [true, false] {
            let gate = VoiceBlockingRead()
            VoiceHTTPStub.configure(response: try responseData(), firstPressure: gate)
            let lifecycle = lifecycle(VoiceCredentials(tokens: token("actor-a")))
            let state = VoiceFenceState(), scope = state.capture(issuer: issuer.absoluteString), api = api(lifecycle)
            let request = Task { try await VoiceOperation.start.perform(api, scope: scope) }
            defer { gate.release() }
            try await waitUntil { gate.entered }
            if withdrawal { state.enabled = false }
            else { state.generation = UUID() }
            gate.release()
            do { try await request.value; XCTFail("Old retry must not dispatch") } catch { }
            XCTAssertEqual(VoiceHTTPStub.records.count, 1)
            XCTAssertEqual(VoiceHTTPStub.records.first?.authorization, "Bearer " + token("actor-a").accessToken)
        }
    }

    func testHealthyScopedCallsFreezeActorAndForwardExactPathsAndBodies() async throws {
        let expectedToken = token("actor-a")
        let lifecycle = lifecycle(VoiceCredentials(tokens: expectedToken))
        let state = VoiceFenceState(), scope = state.capture(issuer: issuer.absoluteString), api = api(lifecycle)
        for operation in VoiceOperation.allCases {
            VoiceHTTPStub.configure(response: try responseData())
            try await operation.perform(api, scope: scope)
            let record = try XCTUnwrap(VoiceHTTPStub.records.first)
            XCTAssertEqual(VoiceHTTPStub.records.count, 1)
            XCTAssertEqual(record.authorization, "Bearer " + expectedToken.accessToken)
            XCTAssertEqual(record.url.host, "cop.test")
            XCTAssertEqual(record.url.path, operation.path)
            XCTAssertEqual(record.method, operation.method)
            if operation == .start {
                let body = try CSMJSONCoding.decoder.decode(CSMVoiceCallStartRequest.self, from: try XCTUnwrap(record.body))
                XCTAssertEqual(body.roomId, "synthetic-room-a")
                XCTAssertEqual(body.participantSubjectIds, ["synthetic-peer"])
                XCTAssertEqual(body.title, "Synthetic title")
            } else if operation == .transition {
                let body = try CSMJSONCoding.decoder.decode(CSMVoiceCallActionRequest.self, from: try XCTUnwrap(record.body))
                XCTAssertEqual(body.endpointId, "synthetic-owned-endpoint-a")
                XCTAssertEqual(body.action, .accept); XCTAssertEqual(body.expectedRevision, 7)
            } else { XCTAssertNil(record.body) }
        }
    }

    func testUnsupportedProviderAdapterAndWrongIssuerFailClosedWhileLegacyRemainsExact() async throws {
        VoiceHTTPStub.configure(response: try responseData())
        let state = VoiceFenceState(), scope = state.capture(issuer: issuer.absoluteString)
        let unsupported = api(LegacyVoiceTokens())
        do { try await VoiceOperation.start.perform(unsupported, scope: scope); XCTFail("Unsupported provider must fail") } catch { }
        do { _ = try await PreviewCopAPIClient().startVoiceCall(.init(participantSubjectIds: nil, roomId: "synthetic", title: nil), voiceScope: scope); XCTFail("Unsupported adapter must fail") } catch { }
        let wrong = api(lifecycle(VoiceCredentials(tokens: token("actor-a", issuer: "https://wrong.test"))))
        do { try await VoiceOperation.start.perform(wrong, scope: scope); XCTFail("Wrong issuer must fail") } catch { }
        XCTAssertEqual(VoiceHTTPStub.records.count, 0)
        // The legacy API still accepts its existing unscoped provider and bearer.
        _ = try await unsupported.startVoiceCall(.init(participantSubjectIds: nil, roomId: "legacy-room", title: nil))
        XCTAssertEqual(VoiceHTTPStub.records.count, 1)
        XCTAssertEqual(VoiceHTTPStub.records.first?.authorization, "Bearer synthetic-legacy-token")
    }

    private func token(_ subject: String, fresh: Bool = true, issuer: String? = nil) -> TokenPair {
        let claims = try! JSONSerialization.data(withJSONObject: ["iss": issuer ?? self.issuer.absoluteString, "sub": subject], options: [.sortedKeys])
        let payload = claims.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        // subjectId=nil matches the actual initial code-exchange provenance.
        return .init(accessToken: "synthetic." + payload + ".synthetic", refreshToken: "synthetic-refresh",
            expiresAt: fresh ? .distantFuture : .distantPast, subjectId: nil)
    }
    private func lifecycle(_ store: VoiceCredentials) -> OIDCTokenLifecycle {
        .init(issuer: issuer, clientId: "synthetic-client", credentialStore: store, session: session())
    }
    private func api(_ provider: any AccessTokenProviding) -> ProductionCopAPIClient {
        .init(http: .init(baseURL: URL(string: "https://cop.test")!, tokenProvider: provider, session: session(), requiresAuthorization: true))
    }
    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [VoiceHTTPStub.self]
        return URLSession(configuration: configuration)
    }
    private func responseData() throws -> Data {
        let call = CSMVoiceCall(callId: "synthetic-call-a", connectedAt: nil, createdAt: .now, direction: .outgoing,
            endedAt: nil, endReason: nil, expiresAt: .now.addingTimeInterval(60), initiatorSubjectId: "actor-a",
            kind: .direct, participantSubjectIds: ["synthetic-peer"], phase: .ringing, revision: 7,
            roomId: "synthetic-room-a", title: "Synthetic title", updatedAt: .now)
        return try CSMJSONCoding.encoder.encode(CSMVoiceCallSession(contractVersion: "synthetic-v1", call: call, media: nil))
    }
    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            guard Date() < deadline else { throw URLError(.timedOut) }
            await Task.yield()
        }
    }
}

private enum VoiceOperation: CaseIterable {
    case start, list, lookup, transition
    var path: String {
        switch self {
        case .start, .list: "/api/v1/messaging/calls"
        case .lookup: "/api/v1/messaging/calls/synthetic-call-a"
        case .transition: "/api/v1/messaging/calls/synthetic-call-a/actions"
        }
    }
    var method: String { self == .start || self == .transition ? "POST" : "GET" }
    func perform(_ api: ProductionCopAPIClient, scope: VoiceOutboundScope) async throws {
        switch self {
        case .start: _ = try await api.startVoiceCall(.init(participantSubjectIds: ["synthetic-peer"], roomId: "synthetic-room-a", title: "Synthetic title"), voiceScope: scope)
        case .list: _ = try await api.voiceCalls(roomId: nil, activeOnly: true, limit: 20, voiceScope: scope)
        case .lookup: _ = try await api.voiceCall(callId: "synthetic-call-a", voiceScope: scope)
        case .transition: _ = try await api.transitionVoiceCall(callId: "synthetic-call-a", request: .init(action: .accept, endpointId: "synthetic-owned-endpoint-a", expectedRevision: 7, reason: nil), voiceScope: scope)
        }
    }
}

@MainActor private final class VoiceFenceState {
    var subject = "actor-a", generation = UUID(), enabled = true
    func capture(issuer: String) -> VoiceOutboundScope {
        let subject = subject, generation = generation
        return .init(issuer: issuer, subject: subject, sdkScope: "synthetic-scope-" + subject, generation: generation,
            validateCurrent: { [self] in
                guard enabled, self.subject == subject, self.generation == generation else { throw CancellationError() }
            })
    }
}

private actor VoiceCredentials: TokenCredentialStoring {
    var tokens: TokenPair?, gate: VoiceBlockingRead?
    init(tokens: TokenPair, gate: VoiceBlockingRead? = nil) { self.tokens = tokens; self.gate = gate }
    func loadTokens(account: String) throws -> TokenPair? { let pause = gate; gate = nil; pause?.block(); return tokens }
    func saveTokens(_ tokens: TokenPair, account: String) throws { self.tokens = tokens }
    func delete(account: String) throws { tokens = nil }
}
private actor VoiceTokenPause {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private actor PausedVoiceTokens: ScopedVoiceAccessTokenProviding {
    let lifecycle: OIDCTokenLifecycle, pause: VoiceTokenPause
    private(set) var unscopedCount = 0
    init(lifecycle: OIDCTokenLifecycle, pause: VoiceTokenPause) { self.lifecycle = lifecycle; self.pause = pause }
    func accessToken() async throws -> String? { unscopedCount += 1; return try await lifecycle.accessToken() }
    func accessToken(for scope: VoiceOutboundScope) async throws -> String? {
        await pause.wait(); return try await lifecycle.accessToken(for: scope)
    }
}
private struct LegacyVoiceTokens: AccessTokenProviding {
    func accessToken() async throws -> String? { "synthetic-legacy-token" }
}
private final class VoiceBlockingRead: @unchecked Sendable {
    private let condition = NSCondition()
    private var started = false, released = false
    var entered: Bool { condition.lock(); defer { condition.unlock() }; return started }
    func block() {
        condition.lock(); defer { condition.unlock() }; started = true
        let deadline = Date().addingTimeInterval(5)
        while !released { if !condition.wait(until: deadline) { break } }
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
private final class VoiceHTTPStub: URLProtocol, @unchecked Sendable {
    struct Record: Sendable { let url: URL; let method: String?; let authorization: String?; let body: Data? }
    private struct State { var records: [Record] = []; var response = Data(); var gate: VoiceBlockingRead? }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()
    static var records: [Record] { lock.withLock { state.records } }
    static func reset() { lock.withLock { state = State() } }
    static func configure(response: Data, firstPressure: VoiceBlockingRead? = nil) { lock.withLock { state = State(response: response, gate: firstPressure) } }
    override class func canInit(with request: URLRequest) -> Bool { ["cop.test", "identity.test"].contains(request.url?.host ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024), bytes = Data()
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n)) }
            body = bytes
        }
        let (number, response, gate) = Self.lock.withLock {
            Self.state.records.append(.init(url: request.url!, method: request.httpMethod, authorization: request.value(forHTTPHeaderField: "Authorization"), body: body))
            return (Self.state.records.count, Self.state.response, Self.state.gate)
        }
        if number == 1 { gate?.block() }
        let pressure = number == 1 && gate != nil
        let data = pressure ? Data(#"{"code":"FST_UNDER_PRESSURE"}"#.utf8) : request.httpMethod == "GET" && request.url?.path == "/api/v1/messaging/calls" ? Data(#"{"calls":[],"contractVersion":"synthetic-v1"}"#.utf8) : response
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: pressure ? 503 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
