import CSMCommunicationKit
import Foundation

/// A local producer fence. It never confirms remote call or OAuth revocation.
public struct VoiceCallHostState: Equatable, Sendable {
  public let scope: String?
  public let generation: UUID?
  public let suspended: Bool
  public let serverAssistanceRequired: Bool
}

public enum VoiceCallSuspensionResult: Equatable, Sendable {
  case notInitialized
  case ownerMismatch
  case automaticPolicy
  case suspended(VoiceCallHostState)
}

public enum VoiceCallHostLifecycleError: LocalizedError {
  case ownerChanged
  case systemCleanupPending
  public var errorDescription: String? {
    switch self {
    case .ownerChanged: "Hlasové spojení není pro tento účet zapnuté."
    case .systemCleanupPending: "Dokončuje se předchozí systémový hovor. Zkuste hlasové spojení znovu za chvíli."
    }
  }
}

/// Captured before permission, network or media awaits. Never diagnostic output.
struct VoiceCallOwner: Equatable, Sendable {
  let scope: String?
  let generation: UUID?
  let epoch: UUID
  let endpointID: String
}

@MainActor
final class VoiceCallHostLifecycle {
  let policy: CSMCommunicationActivationPolicy
  private(set) var epoch = UUID()
  private(set) var owner: VoiceCallOwner?
  private(set) var suspended: Bool
  private var serverAssistanceScopes: Set<String> = []

  init(policy: CSMCommunicationActivationPolicy) {
    self.policy = policy
    suspended = policy != .automatic
  }

  var state: VoiceCallHostState {
    .init(scope: owner?.scope, generation: owner?.generation,
          suspended: suspended,
          serverAssistanceRequired: owner?.scope.map { serverAssistanceScopes.contains($0) } ?? false)
  }

  func resume(snapshot: CSMHostCommunicationSnapshot, expectedScope: String,
              expectedGeneration: UUID, endpointID: String) throws {
    guard policy == .explicitHostConsent, snapshot.policy == .explicitHostConsent,
          snapshot.enabled, !expectedScope.isEmpty, snapshot.scope == expectedScope,
          snapshot.generation == expectedGeneration else { throw VoiceCallHostLifecycleError.ownerChanged }
    if !suspended, owner?.scope == expectedScope, owner?.generation == expectedGeneration { return }
    epoch = UUID()
    owner = .init(scope: expectedScope, generation: expectedGeneration, epoch: epoch, endpointID: endpointID)
    suspended = false
    // A fresh local activation is not an acknowledgement of old remote cleanup.
  }

  func matches(scope: String, generation: UUID) -> Bool {
    owner?.scope == scope && owner?.generation == generation
  }

  func suspend(needsServerAssistance: Bool) {
    epoch = UUID()
    suspended = true
    if needsServerAssistance, let scope = owner?.scope { serverAssistanceScopes.insert(scope) }
  }

  func permits(_ captured: VoiceCallOwner, snapshot: CSMHostCommunicationSnapshot?) -> Bool {
    guard !suspended, captured.epoch == epoch else { return false }
    if policy == .automatic { return true }
    guard policy == .explicitHostConsent, owner == captured, let snapshot else { return false }
    return snapshot.policy == .explicitHostConsent && snapshot.enabled &&
      snapshot.scope == captured.scope && snapshot.generation == captured.generation
  }
}
