import Foundation

protocol AccessTokenProviding: Sendable {
    func accessToken() async throws -> String?
}

struct KeychainAccessTokenProvider: AccessTokenProviding {
    var store: KeychainCredentialStore

    func accessToken() async throws -> String? {
        guard let tokens = try await store.loadTokens(), tokens.isAccessTokenFresh else {
            return nil
        }
        return tokens.accessToken
    }
}

struct HTTPClient: Sendable {
    var baseURL: URL
    var tokenProvider: (any AccessTokenProviding)?
    var session: URLSession
    var requiresAuthorization: Bool

    init(
        baseURL: URL,
        tokenProvider: (any AccessTokenProviding)? = nil,
        session: URLSession = .shared,
        requiresAuthorization: Bool = false
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
        self.requiresAuthorization = requiresAuthorization
    }

    func get<Response: Decodable & Sendable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        transientRetryCount: Int = 0
    ) async throws -> Response {
        let request = try await request(path, method: "GET", queryItems: queryItems)
        return try await send(request, transientRetryCount: transientRetryCount)
    }

    func getData(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        accept: String = "*/*"
    ) async throws -> Data {
        var request = try await request(path, method: "GET", queryItems: queryItems)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return try await sendData(request)
    }

    func post<RequestBody: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: RequestBody,
        transientRetryCount: Int = 0,
        authorizationBearerToken: String? = nil
    ) async throws -> Response {
        var request = try await request(path, method: "POST")
        request.httpBody = try CSMJSONCoding.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authorizationBearerToken {
            let token = authorizationBearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else {
                throw CSMServiceError.authenticationRequired("Chybí autorizační ticket registrace zařízení.")
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request, transientRetryCount: transientRetryCount)
    }

    func post<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        let request = try await request(path, method: "POST")
        return try await send(request)
    }

    func post(_ path: String) async throws {
        let request = try await request(path, method: "POST")
        try await sendWithoutResponse(request)
    }

    func put<RequestBody: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: RequestBody
    ) async throws -> Response {
        var request = try await request(path, method: "PUT")
        request.httpBody = try CSMJSONCoding.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func patch<RequestBody: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: RequestBody
    ) async throws -> Response {
        var request = try await request(path, method: "PATCH")
        request.httpBody = try CSMJSONCoding.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request)
    }

    func delete(_ path: String) async throws {
        let request = try await request(path, method: "DELETE")
        try await sendWithoutResponse(request)
    }

    func postData(
        _ path: String,
        data: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) async throws {
        var request = try await request(path, method: "POST")
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        try await sendWithoutResponse(request)
    }

    func putData(
        to uploadURL: URL,
        data: Data,
        contentType: String,
        headers: [String: String] = [:]
    ) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.timeoutInterval = 120
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        try await sendWithoutResponse(request)
    }

    func resolvedURL(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw CSMServiceError.invalidState("Invalid base URL.")
        }
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let joinedPath = [basePath, requestPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedPath = "/" + joinedPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw CSMServiceError.invalidState("Invalid request URL.")
        }
        return url
    }

    private func request(
        _ path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> URLRequest {
        let url = try resolvedURL(path, queryItems: queryItems)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-correlation-id")

        let rawToken = try await tokenProvider?.accessToken()
        let token = rawToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if requiresAuthorization {
            throw CSMServiceError.authenticationRequired(
                CSMLocalization.text(
                    "auth.error.fresh_token_required",
                    fallback: "Přihlášení vypršelo. Přihlaste se znovu."
                )
            )
        }
        return request
    }

    private func send<Response: Decodable & Sendable>(
        _ request: URLRequest,
        transientRetryCount: Int = 0
    ) async throws -> Response {
        let maximumRetries = max(0, min(transientRetryCount, 4))
        for attempt in 0...maximumRetries {
            let (data, response) = try await session.data(for: request)
            do {
                let httpResponse = try validate(response, data: data)
                if data.isEmpty, Response.self is EmptyHTTPResponse.Type {
                    return EmptyHTTPResponse(statusCode: httpResponse.statusCode) as! Response
                }
                return try CSMJSONCoding.decoder.decode(Response.self, from: data)
            } catch let failure as HTTPResponseFailure where failure.isTransientPressure && attempt < maximumRetries {
                try await Task.sleep(for: .milliseconds(250 * (1 << attempt)))
            }
        }
        throw CSMServiceError.unavailable("COP API request failed after retry.")
    }

    private func sendWithoutResponse(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        _ = try validate(response, data: Data())
    }

    private func sendData(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        _ = try validate(response, data: data)
        return data
    }

    private func validate(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CSMServiceError.unavailable("Missing HTTP response.")
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw HTTPResponseFailure(
                statusCode: httpResponse.statusCode,
                code: Self.errorCode(in: data)
            )
        }
        return httpResponse
    }

    private static func errorCode(in data: Data) -> String? {
        guard
            !data.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let code = object["code"] as? String {
            return code
        }
        return (object["error"] as? [String: Any])?["code"] as? String
    }
}

private struct HTTPResponseFailure: LocalizedError, Sendable {
    let statusCode: Int
    let code: String?

    var isTransientPressure: Bool {
        statusCode == 503 && code == "FST_UNDER_PRESSURE"
    }

    var errorDescription: String? {
        "COP API returned HTTP \(statusCode)\(code.map { " (\($0))" } ?? "")."
    }
}

struct EmptyHTTPResponse: Decodable, Sendable {
    var statusCode: Int

    init(statusCode: Int) {
        self.statusCode = statusCode
    }
}
