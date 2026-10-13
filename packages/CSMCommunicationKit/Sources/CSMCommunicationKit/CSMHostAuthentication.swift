import Foundation

/// A fresh, read-only witness of COP identity and required local unlock.
/// It grants no communication, sharing or server permission. Matrix, push and
/// producer readiness are independent; reread this value after every await.
public struct CSMHostAuthenticationSnapshot: Equatable, Sendable {
    public let scope: String?
    public let generation: UUID
    public let identityReady: Bool
    public let isVerifyingIdentity: Bool
}

public extension Notification.Name {
    /// Payloadless wakeup only. Read the runtime snapshot; do not infer readiness
    /// from the notification, its delivery order or an earlier captured value.
    static let csmHostAuthenticationChanged = Notification.Name("cz.zeleznalady.csm.hostAuthenticationChanged")
}

public extension CSMCommunicationRuntime {
    /// Does not restore a session, construct a service or start a producer.
    var hostAuthenticationSnapshot: CSMHostAuthenticationSnapshot {
        let ready = model.hostAuthenticationIdentityReady
        return .init(scope: ready ? mobilitySessionScope() : nil,
                     generation: model.jizdaLifecycleSnapshot.generation,
                     identityReady: ready,
                     isVerifyingIdentity: model.hostAuthenticationIsVerifyingIdentity)
    }
}
