import Foundation

public enum CSMJizdaLifecycleReadiness: String, Equatable, Sendable {
    case notRequired, verificationRequired, checking, transportPreparing, transportUnavailable, ready, suspended, unavailable, configurationInvalid
    public var permitsProducers: Bool { self == .notRequired || self == .ready }
}

/// Process-local epoch and optional opaque session scope; no raw identity or content.
public struct CSMJizdaLifecycleSnapshot: Equatable, Sendable {
    public let readiness: CSMJizdaLifecycleReadiness
    public let generation: UUID
    public let scope: String?
    public var permitsProducers: Bool { readiness.permitsProducers }
    init(readiness: CSMJizdaLifecycleReadiness, generation: UUID, scope: String? = nil) {
        self.readiness = readiness; self.generation = generation; self.scope = scope
    }
}

public extension Notification.Name {
    /// Read the current snapshot after receiving this event; never reuse an old epoch.
    static let csmJizdaLifecycleReadinessChanged = Notification.Name("cz.zeleznalady.csm.jizdaLifecycleReadinessChanged")
}

struct CSMJizdaLifecyclePolicy: Equatable, Sendable {
    let required: Bool
    let configured: Bool
    private(set) var generation = UUID()
    private(set) var readiness: CSMJizdaLifecycleReadiness
    private(set) var acceptedFence = false
    init(appScope: String?, clientID: String, redirectScheme: String) {
        required = appScope == "jizda_app_link" || clientID == "jizda-mobile"
        configured = appScope == "jizda_app_link" && clientID == "jizda-mobile" && redirectScheme == "jizda-cop"
        readiness = !required ? .notRequired : (configured ? .verificationRequired : .configurationInvalid)
    }
    var snapshot: CSMJizdaLifecycleSnapshot { .init(readiness: readiness, generation: generation) }
    mutating func resetAccount() {
        generation = UUID(); acceptedFence = false
        readiness = !required ? .notRequired : (configured ? .verificationRequired : .configurationInvalid)
    }
    mutating func beginVerification() -> UUID {
        if required && configured && !acceptedFence { readiness = .checking }
        return generation
    }
    @discardableResult mutating func verified(status: String, persistedFence: Bool, epoch: UUID) -> Bool {
        guard epoch == generation, required, configured else { return false }
        if persistedFence || status != "linked" { acceptedFence = true }
        readiness = acceptedFence ? .suspended : .ready
        return true
    }
    var permitsTransportPreparation: Bool {
        configured && !acceptedFence && [.ready, .transportPreparing, .transportUnavailable].contains(readiness)
    }
    @discardableResult mutating func beginTransportPreparation(epoch: UUID) -> Bool {
        guard epoch == generation, permitsTransportPreparation else { return false }
        readiness = .transportPreparing
        return true
    }
    @discardableResult mutating func finishTransportPreparation(epoch: UUID, succeeded: Bool) -> Bool {
        guard epoch == generation, permitsTransportPreparation else { return false }
        readiness = succeeded ? .ready : .transportUnavailable
        return true
    }
    @discardableResult mutating func failed(epoch: UUID) -> Bool {
        guard epoch == generation, required, configured else { return false }
        readiness = acceptedFence ? .suspended : .unavailable
        return true
    }
    @discardableResult mutating func acceptFence(epoch: UUID) -> Bool {
        guard epoch == generation else { return false }
        acceptedFence = true; readiness = .suspended
        return true
    }
}

protocol CSMJizdaLifecyclePersisting: Actor {
    func loadOrCreateInstallationID(scope: String, legacyCandidate: UUID?) throws -> UUID
    func hasJizdaAcceptedFence(scope: String) throws -> Bool
    func saveJizdaAcceptedFence(scope: String) throws
}
