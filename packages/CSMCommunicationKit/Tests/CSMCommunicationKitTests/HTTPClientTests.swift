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

    func testPostForwardsStableIdempotencyHeader() async throws {
        PressureURLProtocol.configure { _ in
            (201, #"{"value":"created"}"#)
        }
        let client = HTTPClient(
            baseURL: URL(string: "https://cop.test")!,
            session: makeSession()
        )
        let key = "e5ea4b90-709a-4eb0-a1ab-0a949f12a9e1"

        let response: TestResponse = try await client.post(
            "/api/v1/community/reports",
            body: TestRequest(value: "traffic_accident"),
            headers: ["X-Idempotency-Key": key]
        )

        XCTAssertEqual(response.value, "created")
        XCTAssertEqual(
            PressureURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-Idempotency-Key"),
            key
        )
    }

    func testDriverFeedUsesOnlyCOPAndForwardsSpatialQuery() async throws {
        PressureURLProtocol.configure { _ in (200, #"{"items":[]}"#) }
        let api = ProductionCopAPIClient(http: HTTPClient(baseURL: URL(string: "https://cop.test")!, session: makeSession()))
        let query = try XCTUnwrap(DriverReportQuery.nearby(latitude: 50.08, longitude: 14.42, radiusMeters: 10_000).first)
        let reports = try await api.communityReports(query: query)
        XCTAssertTrue(reports.isEmpty)
        let request = try XCTUnwrap(PressureURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.host, "cop.test")
        XCTAssertEqual(request.url?.path, "/api/v1/community/reports")
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "bbox" })?.value, query.queryItems.first?.value)
        XCTAssertEqual(PressureURLProtocol.requestCount, 1)
    }

    func testRoutingUsesAuthenticatedCOPOnlyAndDoesNotRetryOrAdjustTime() async throws {
        PressureURLProtocol.configure { _ in (200, DriverRoutingTests.fixture) }
        let api = ProductionCopAPIClient(http: HTTPClient(
            baseURL: URL(string: "https://cop.test")!,
            tokenProvider: StaticTestTokenProvider(token: "test-user-token"),
            session: makeSession(), requiresAuthorization: true
        ))
        let body = CSMDriverRouteRequest(from: .init(latitude: 50, longitude: 14), to: .init(latitude: 51, longitude: 15), alternatives: 3)
        let response = try await api.drivingRoutes(body)
        XCTAssertEqual(try response.navigationRoutes().first?.durationSeconds, 2400)
        let request = try XCTUnwrap(PressureURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://cop.test/api/v1/routing/route")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-user-token")
        XCTAssertEqual(PressureURLProtocol.requestCount, 1)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(body)) as? [String: Any])
        XCTAssertEqual(encoded["profileId"] as? String, "car")
        XCTAssertEqual(encoded["includeSteps"] as? Bool, true)
        XCTAssertEqual(encoded["alternatives"] as? Int, 3)
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
