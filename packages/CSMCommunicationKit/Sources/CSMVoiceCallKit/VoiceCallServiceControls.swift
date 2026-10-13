import AVFAudio
@preconcurrency import CallKit
import CSMCommunicationKit
import Foundation
import LiveKit
@preconcurrency import PushKit

@MainActor
final class VoiceCallSystemBinding {
  let id = UUID()
  let epoch: UUID
  let provider: CXProvider?
  let controller: CXCallController?
  let reporter: any VoiceCallIncomingReporting
  private(set) var registry: PKPushRegistry?
  private weak var retiredRegistry: PKPushRegistry?
  private(set) var retired = false
  private var pendingReports: [UUID: Int] = [:]
  var hasPendingReports: Bool { !pendingReports.isEmpty }
  func reportIsPending(_ uuid: UUID) -> Bool { pendingReports[uuid] != nil }
  func beginReport(_ uuid: UUID) { pendingReports[uuid, default: 0] += 1 }
  func finishReport(_ uuid: UUID) {
    guard let count = pendingReports[uuid] else { return }
    if count == 1 { pendingReports.removeValue(forKey: uuid) } else { pendingReports[uuid] = count - 1 }
  }
  var hasRegistry: Bool { registry != nil || retiredRegistry != nil }

  init(epoch: UUID, provider: CXProvider?, controller: CXCallController?,
       registry: PKPushRegistry?, reporter: any VoiceCallIncomingReporting) {
    self.epoch = epoch; self.provider = provider; self.controller = controller
    self.registry = registry; self.reporter = reporter
  }
  func retire() {
    registry?.desiredPushTypes = []
    retiredRegistry = registry
    registry = nil
    retired = true
  }
}

/// Internal control seams exercise the same native state machine without APNs,
/// microphone permission or real server credentials in tests.
@MainActor
struct VoiceCallServiceControls {
  var snapshot: () -> CSMHostCommunicationSnapshot
  var endpointID: () -> String
  var permission: () async -> Bool
  var start: (String, String, [String]?, VoiceCallOwner) async throws -> CSMVoiceCallSession
  var fetch: (String, VoiceCallOwner) async throws -> CSMVoiceCallSession
  var list: (VoiceCallOwner) async throws -> [CSMVoiceCall]
  var transition: (String, CSMVoiceCallAction, Int?, String?, VoiceCallOwner) async throws -> CSMVoiceCallSession
  var initializeAudio: () -> Void
  var stopAudio: () -> Void
  var makeSystem: (VoiceCallService, UUID) -> VoiceCallSystemBinding
  var activateSystemAudio: () throws -> Void = { try AudioManager.shared.setEngineAvailability(.default) }
  var observeHardware = true

  static var live: Self {
    .init(
      snapshot: { CSMCommunicationRuntime.shared.hostCommunicationSnapshot },
      endpointID: { CSMCommunicationRuntime.shared.voiceCallEndpointID },
      permission: { await AVAudioApplication.requestRecordPermission() },
      start: { room, title, participants, owner in
        try await CSMCommunicationRuntime.shared.startVoiceCall(roomID: room, title: title,
          participantSubjectIDs: participants, expectedScope: owner.scope, expectedGeneration: owner.generation)
      },
      fetch: { id, owner in
        try await CSMCommunicationRuntime.shared.voiceCall(callID: id,
          expectedScope: owner.scope, expectedGeneration: owner.generation)
      },
      list: { owner in
        try await CSMCommunicationRuntime.shared.activeVoiceCalls(
          expectedScope: owner.scope, expectedGeneration: owner.generation)
      },
      transition: { id, action, revision, reason, owner in
        try await CSMCommunicationRuntime.shared.transitionVoiceCall(callID: id, action: action,
          expectedRevision: revision, reason: reason, expectedScope: owner.scope, expectedGeneration: owner.generation)
      },
      initializeAudio: {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try? AudioManager.shared.setEngineAvailability(.none)
      },
      stopAudio: { try? AudioManager.shared.setEngineAvailability(.none) },
      makeSystem: { service, epoch in
        let configuration = CXProviderConfiguration()
        configuration.includesCallsInRecents = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        configuration.supportsVideo = false
        let provider = CXProvider(configuration: configuration)
        provider.setDelegate(service, queue: .main)
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = service
        registry.desiredPushTypes = [.voIP]
        return VoiceCallSystemBinding(epoch: epoch, provider: provider, controller: CXCallController(),
          registry: registry, reporter: VoiceCallProviderReporter(provider: provider))
      }
    )
  }
}
