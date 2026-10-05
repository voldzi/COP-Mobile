import Foundation

/// One refresh owner for each configured device session, including API, chat,
/// routing, measurements and mobility. Never creates per-request refresh owners.
final class DeviceOIDCSession: @unchecked Sendable {
    static let shared = DeviceOIDCSession()
    private let lock = NSLock()
    private var lifecycles: [String: OIDCTokenLifecycle] = [:]

    func lifecycle(issuer: URL, clientId: String) -> OIDCTokenLifecycle {
        lock.withLock {
            let key = issuer.absoluteString + "\0" + clientId
            if let existing = lifecycles[key] { return existing }
            let value = OIDCTokenLifecycle(issuer: issuer, clientId: clientId,
                credentialStore: KeychainCredentialStore())
            lifecycles[key] = value
            return value
        }
    }
}
