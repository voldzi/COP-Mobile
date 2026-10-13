import CryptoKit
import Foundation

/// Private cleanup material for one already registered bundle pusher. Never
/// exposed to hosts, defaults, notifications, diagnostics or the device bridge.
struct HostPusherCleanupTarget: Codable, Equatable, Sendable {
    let pushKey: String
    let appID: String
    let homeserverURL: URL
    let accessToken: String
    var id: String { SHA256.hash(data: Data((appID + "\0" + pushKey).utf8)).map { String(format: "%02x", $0) }.joined() }
    var isValid: Bool {
        !pushKey.isEmpty && pushKey.utf8.count <= 2048 && !appID.isEmpty && appID.utf8.count <= 255 &&
            !accessToken.isEmpty && accessToken.utf8.count <= 65536 && homeserverURL.scheme == "https" &&
            homeserverURL.host?.isEmpty == false && homeserverURL.user == nil && homeserverURL.password == nil &&
            homeserverURL.query == nil && homeserverURL.fragment == nil && ["", "/"].contains(homeserverURL.path)
    }
}

protocol HostPusherCleanupStoring: Sendable {
    func targets(scope: String) async throws -> [HostPusherCleanupTarget]
    func save(_ target: HostPusherCleanupTarget, scope: String) async throws
    func remove(_ target: HostPusherCleanupTarget, scope: String) async throws
}

protocol HostPusherCleanupRemoving: Sendable {
    func remove(_ target: HostPusherCleanupTarget) async throws
}

/// A single exact authenticated removal. It does not create a Rust/Matrix client,
/// resume sync, enqueue messages, refresh credentials or provision a device.
struct HostPusherCleanupHTTP: HostPusherCleanupRemoving {
    let transport: any MatrixHTTPTransport
    init(transport: any MatrixHTTPTransport = HostPusherCleanupTransport()) { self.transport = transport }
    func remove(_ target: HostPusherCleanupTarget) async throws {
        guard target.isValid else { throw CSMCOPSessionError(.invalidResponse) }
        let url = target.homeserverURL.appendingPathComponent("_matrix/client/v3/pushers/set")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer " + target.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["app_id": target.appID, "pushkey": target.pushKey, "kind": NSNull()])
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url, http.statusCode == 200,
              data.count <= 65536 else { throw CSMServiceError.unavailable("Odregistraci oznámení nyní nelze potvrdit.") }
    }
}

private struct HostPusherCleanupTransport: MatrixHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: HostPusherCleanupNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }
}
private final class HostPusherCleanupNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
