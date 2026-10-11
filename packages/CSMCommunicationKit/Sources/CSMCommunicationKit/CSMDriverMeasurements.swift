import CryptoKit
import Foundation

public enum CSMDriverMeasurementOperation: Sendable {
    case readConsent, grantConsent, revokeConsent, submitBatch
}
public extension Notification.Name {
    static let csmDriverMeasurementSessionChanged = Notification.Name("CSMDriverMeasurementSessionChanged")
}
public struct CSMDriverMeasurementHTTPResult: Sendable {
    public let data: Data
    public let statusCode: Int
    public let retryAfter: String?
}

enum CSMDriverMeasurementAccessPolicy {
    static func allowsConfiguration(_ configuration: AppConfiguration) -> Bool {
        let dedicated = CSMJizdaLifecyclePolicy(appScope: configuration.appScope,
            clientID: configuration.oidcClientId, redirectScheme: configuration.oidcRedirectScheme)
        let ordinary = configuration.oidcClientId == "csm-mobile" && !dedicated.required
        return !configuration.usePreviewServices && (ordinary || dedicated.configured) &&
            configuration.copBaseURL.scheme == "https" && configuration.copBaseURL.host?.isEmpty == false &&
            configuration.copBaseURL.user == nil &&
            configuration.copBaseURL.password == nil && configuration.copBaseURL.query == nil &&
            configuration.copBaseURL.fragment == nil && ["", "/"].contains(configuration.copBaseURL.path)
    }
    static func requiresReadyProducers(_ operation: CSMDriverMeasurementOperation) -> Bool {
        operation == .grantConsent || operation == .submitBatch
    }
}

/// Purpose-specific transport only. Neither token nor arbitrary URL is exposed.
public extension CSMCommunicationRuntime {
    func driverMeasurementSessionScope() -> String? {
        guard model.authState == .signedIn, let actor = model.actor else { return nil }
        return SHA256.hash(data: Data(actor.subjectId.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func driverMeasurementRequest(_ operation: CSMDriverMeasurementOperation,
                                  batchJSON: Data? = nil, expectedScope: String) async throws -> CSMDriverMeasurementHTTPResult {
        guard CSMDriverMeasurementBatchPolicy.matchesSession(current: driverMeasurementSessionScope(), expected: expectedScope) else {
            throw CSMServiceError.authenticationRequired("Relace měření se změnila.")
        }
        let epoch = model.jizdaLifecycleSnapshot.generation
        let configuration = AppConfiguration.fromBundle()
        guard CSMDriverMeasurementAccessPolicy.allowsConfiguration(configuration) else {
            throw CSMServiceError.disabled("Měření vyžaduje ověřenou konfiguraci COP.")
        }
        let createsMeasurement = CSMDriverMeasurementAccessPolicy.requiresReadyProducers(operation)
        if createsMeasurement, !model.permitsCommunicationProducers(epoch: epoch) {
            throw CSMServiceError.unavailable("Propojení Jízdy není ověřené; měření zůstává vypnuté.")
        }
        let suffix: String, method: String, body: Data?
        switch operation {
        case .readConsent: suffix = "consent"; method = "GET"; body = nil
        case .grantConsent:
            suffix = "consent"; method = "POST"
            body = Data(#"{"contractVersion":"cop-driver-measurements-v1","version":"traffic-quality-v1","granted":true}"#.utf8)
        case .revokeConsent: suffix = "consent"; method = "DELETE"; body = nil
        case .submitBatch:
            guard let batchJSON, batchJSON.count <= 1_048_576,
                  CSMDriverMeasurementBatchPolicy.accepts(batchJSON) else {
                throw CSMServiceError.invalidState("Neplatná dávka měření.")
            }
            suffix = "batches"; method = "POST"; body = batchJSON
        }
        if operation != .submitBatch, batchJSON != nil { throw CSMServiceError.invalidState("Neočekávané tělo.") }
        let lifecycle = DeviceOIDCSession.shared.lifecycle(issuer: configuration.oidcIssuer,
            clientId: configuration.oidcClientId)
        guard let token = try await lifecycle.accessToken(), !token.isEmpty,
              epoch == model.jizdaLifecycleSnapshot.generation,
              driverMeasurementSessionScope() == expectedScope else {
            throw CSMServiceError.authenticationRequired("Přihlášení měření vypršelo.")
        }
        if createsMeasurement, !model.permitsCommunicationProducers(epoch: epoch) {
            throw CSMServiceError.unavailable("Propojení Jízdy není ověřené; měření zůstává vypnuté.")
        }
        let url = configuration.copBaseURL.appendingPathComponent("api/v1/driver-measurements/v1/" + suffix)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: DriverMeasurementNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard epoch == model.jizdaLifecycleSnapshot.generation, driverMeasurementSessionScope() == expectedScope,
              let http = response as? HTTPURLResponse, http.url == url, data.count <= 1_048_576 else {
            throw CSMServiceError.authenticationRequired("Relace měření se změnila.")
        }
        if createsMeasurement, !model.permitsCommunicationProducers(epoch: epoch) {
            throw CSMServiceError.unavailable("Propojení Jízdy není ověřené; měření zůstává vypnuté.")
        }
        return .init(data: data, statusCode: http.statusCode, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
    }
}
private final class DriverMeasurementNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
