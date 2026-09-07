import Foundation
import XCTest

@testable import CSMCommunicationKit

final class HTTPClientTests: XCTestCase {
    override func tearDown() {
        PressureURLProtocol.reset()
        super.tearDown()
    }

    func testRetriesOnlyFastifyUnderPressureResponses() async throws {
        PressureURLProtocol.configure { requestNumber in
            if requestNumber < 3 {
                return (503, #"{"code":"FST_UNDER_PRESSURE"}"#)
            }
            return (200, #"{"value":"ready"}"#)
        }
        let client = HTTPClient(
            baseURL: URL(string: "https://cop.test")!,
            session: makeSession()
        )

        let response: TestResponse = try await client.get(
            "/api/v1/messaging/calls/call-1",
            transientRetryCount: 3
        )

        XCTAssertEqual(response.value, "ready")
        XCTAssertEqual(PressureURLProtocol.requestCount, 3)
    }

    func testDoesNotRetryUnrelatedServiceUnavailableResponse() async {
        PressureURLProtocol.configure { _ in
            (503, #"{"code":"VOICE_CALLS_DISABLED"}"#)
        }
        let client = HTTPClient(
            baseURL: URL(string: "https://cop.test")!,
            session: makeSession()
        )

        do {
            let _: TestResponse = try await client.get(
                "/api/v1/messaging/calls/call-1",
                transientRetryCount: 3
            )
            XCTFail("Expected the non-transient 503 response to fail.")
        } catch {
            XCTAssertEqual(PressureURLProtocol.requestCount, 1)
        }
    }

    func testExplicitRegistrationTicketOverridesSessionAuthorization() async throws {
        PressureURLProtocol.configure { _ in
            (201, #"{"value":"registered"}"#)
        }
        let client = HTTPClient(
            baseURL: URL(string: "https://msg.test")!,
            tokenProvider: StaticTestTokenProvider(token: "ordinary-oidc-token"),
            session: makeSession(),
            requiresAuthorization: true
        )

        let response: TestResponse = try await client.post(
            "/api/v1/devices",
            body: TestRequest(value: "device"),
            authorizationBearerToken: "csmrt1.payload.signature"
        )

        XCTAssertEqual(response.value, "registered")
        XCTAssertEqual(
            PressureURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer csmrt1.payload.signature"
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PressureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct TestResponse: Decodable, Sendable {
    var value: String
}

private struct TestRequest: Encodable, Sendable {
    var value: String
}

private struct StaticTestTokenProvider: AccessTokenProviding {
    var token: String?

    func accessToken() async throws -> String? {
        token
    }
}

private final class PressureURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseHandler: ((Int) -> (Int, String))?
    nonisolated(unsafe) private static var storedRequestCount = 0
    nonisolated(unsafe) private static var storedLastRequest: URLRequest?

    static var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    static var lastRequest: URLRequest? {
        lock.withLock { storedLastRequest }
    }

    static func configure(_ handler: @escaping (Int) -> (Int, String)) {
        lock.withLock {
            storedRequestCount = 0
            storedLastRequest = nil
            responseHandler = handler
        }
    }

    static func reset() {
        lock.withLock {
            storedRequestCount = 0
            storedLastRequest = nil
            responseHandler = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let result: (Int, String)? = Self.lock.withLock {
            Self.storedRequestCount += 1
            Self.storedLastRequest = request
            return Self.responseHandler?(Self.storedRequestCount)
        }
        guard let result,
              let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: result.0,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(result.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
