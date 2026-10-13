import AVFAudio
@preconcurrency import CallKit
import CSMCommunicationKit
import Foundation
import LiveKit
import Observation
import OSLog
@preconcurrency import PushKit
import Security
import UIKit

private enum VoiceCallPushRegistrationError: Error {
  case registrationFailed
  case registrationPending
}

private enum VoiceCallPushTokenStore {
  private static let account = "pushkit.voip"
  private static var service: String {
    "\(Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm").push-tokens"
  }

  static func load() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else { return nil }
    return value
  }

  static func save(_ token: String) {
    guard let data = token.data(using: .utf8) else { return }
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
    guard status == errSecItemNotFound else { return }
    var query = baseQuery
    attributes.forEach { query[$0.key] = $0.value }
    _ = SecItemAdd(query as CFDictionary, nil)
  }

  static func remove() {
    _ = SecItemDelete(baseQuery as CFDictionary)
  }

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

/// A Keychain token is only a recovery hint. PushKit must confirm the token for
/// every process lifetime before it is sent to COP, otherwise an in-place app or
/// OS update can silently re-register an obsolete APNs address.
struct VoiceCallPushTokenState: Equatable {
  private(set) var cachedToken: String?
  private(set) var isConfirmedForCurrentProcess = false

  init(cachedToken: String?) {
    self.cachedToken = cachedToken
  }

  var needsRegistrationRecovery: Bool {
    !isConfirmedForCurrentProcess
  }

  var tokenForServerRegistration: String? {
    isConfirmedForCurrentProcess ? cachedToken : nil
  }

  mutating func confirm(_ token: String) -> Bool {
    let shouldRefreshServer =
      !isConfirmedForCurrentProcess || cachedToken != token
    cachedToken = token
    isConfirmedForCurrentProcess = true
    return shouldRefreshServer
  }

  mutating func invalidate() {
    cachedToken = nil
    isConfirmedForCurrentProcess = false
  }
}

struct VoiceCallAudioSessionPolicy {
  static func needsConfiguration(
    category: AVAudioSession.Category,
    mode: AVAudioSession.Mode,
    options: AVAudioSession.CategoryOptions,
    isActive: Bool
  ) -> Bool {
    guard !isActive else { return false }
    return category != .playAndRecord
      || mode != .voiceChat
      || !options.contains(.allowBluetoothHFP)
  }
}

/// Ringing is governed by the server invitation expiry, not the media timeout.
struct VoiceCallConnectionPolicy {
  enum Stage: String, Sendable { case connectingRoom, waitingForAnswer, connectingAcceptedMedia, waitingForServerAck, connected, terminal }
  static func stage(serverPhase: CSMVoiceCallPhase, roomConnected: Bool, peerPresent: Bool,
                    answered: Bool, incoming: Bool, audioActivated: Bool, microphonePublished: Bool) -> Stage {
    if serverPhase.isTerminal { return .terminal }
    if incoming && !answered && (serverPhase == .created || serverPhase == .ringing) { return .waitingForAnswer }
    if !roomConnected { return .connectingRoom }
    if serverPhase == .created || serverPhase == .ringing { return .waitingForAnswer }
    if peerPresent && (!incoming || answered) && audioActivated && microphonePublished {
      return serverPhase == .connected ? .connected : .waitingForServerAck
    }
    return .connectingAcceptedMedia
  }
  static func requiresMediaDeadline(_ stage: Stage) -> Bool {
    stage == .connectingRoom || stage == .connectingAcceptedMedia || stage == .waitingForServerAck
  }
}

/// One absolute budget across bounded setup stages. Changing peer/audio state
/// cannot cancel the timer or restart its budget while server ACK is unavailable.
@MainActor
final class VoiceCallConnectionDeadline {
  private let duration: Duration
  private var owner: UUID?
  private var task: Task<Void, Never>?
  init(duration: Duration = .seconds(45)) { self.duration = duration }
  func cancel() { task?.cancel(); task = nil; owner = nil }
  func update(uuid: UUID, stage: VoiceCallConnectionPolicy.Stage,
              currentStage: @escaping @MainActor () -> VoiceCallConnectionPolicy.Stage?,
              timedOut: @escaping @MainActor () -> Void) {
    guard VoiceCallConnectionPolicy.requiresMediaDeadline(stage) else { cancel(); return }
    guard owner != uuid else { return }
    cancel(); owner = uuid
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: duration)
      guard !Task.isCancelled, owner == uuid else { return }
      owner = nil; task = nil
      guard let current = currentStage(), VoiceCallConnectionPolicy.requiresMediaDeadline(current) else { return }
      timedOut()
    }
  }
}

enum CallDiagnosticStore {
  private static let fileName = "COPCallDiagnostics.json"
  private static let maximumEntries = 96

  static func record(_ event: String, result: String? = nil) {
    guard
      let directory = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let url = directory.appending(path: fileName)
      var entries: [[String: String]] = []
      if let data = try? Data(contentsOf: url),
        let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
      {
        entries = decoded
      }
      var entry = [
        "event": event,
        "occurredAt": ISO8601DateFormatter().string(from: Date()),
      ]
      if let result {
        entry["result"] = String(result.prefix(240))
      }
      entries.append(entry)
      if entries.count > maximumEntries {
        entries.removeFirst(entries.count - maximumEntries)
      }
      try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
        .write(to: url, options: .atomic)
    } catch {
      // Diagnostics are deliberately best-effort and never affect a call.
    }
  }
}

enum VoiceCallDirection: String, Equatable, Sendable {
  case incoming
  case outgoing
}

enum VoiceCallPhase: String, Equatable, Sendable {
  case ringing
  case connecting
  case connected
  case ended
  case failed
}

enum VoiceCallKind: String, Equatable, Sendable {
  case direct
}

enum VoiceCallPushEvent: String, Equatable, Sendable {
  case answeredElsewhere = "chat.voice_call.answered_elsewhere"
  case ended = "chat.voice_call.ended"
  case incoming = "chat.voice_call.incoming"
}

struct VoiceCallPushPayload: Equatable, Sendable {
  let acceptedEndpointID: String?
  let callID: String
  let callerDisplayName: String
  let event: VoiceCallPushEvent
  let roomID: String
  let uuid: UUID

  init?(dictionary: [AnyHashable: Any]) {
    guard
      let eventValue = Self.string(dictionary["type"]),
      let event = VoiceCallPushEvent(rawValue: eventValue),
      let callID = Self.string(dictionary["callId"]),
      let uuid = UUID(uuidString: callID),
      let roomID = Self.string(dictionary["roomId"])
    else { return nil }

    acceptedEndpointID = Self.string(dictionary["acceptedEndpointId"])
    self.callID = callID
    callerDisplayName = Self.string(dictionary["senderDisplayName"]) ?? "COP kontakt"
    self.event = event
    self.roomID = roomID
    self.uuid = uuid
  }

  private static func string(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}

struct VoiceCallParticipant: Equatable, Identifiable, Sendable {
  let userID: String
  let displayName: String
  let connected: Bool

  var id: String { userID }
}

struct VoiceCallPresentation: Equatable, Identifiable, Sendable {
  let id: UUID
  let callID: String
  let roomID: String
  let title: String
  let avatarDataURL: String?
  let direction: VoiceCallDirection
  let eligibleParticipants: [VoiceCallParticipant]
  let kind: VoiceCallKind
  let participants: [VoiceCallParticipant]
  let phase: VoiceCallPhase
  let connectedAt: Date?
}

@MainActor
@Observable
final class VoiceCallPresentationState {
  private(set) var activeCall: VoiceCallPresentation?
  private(set) var isAudioActive = false
  private(set) var isMuted = false
  private(set) var isProximityCovered = false
  private(set) var isSpeakerEnabled = false
  private(set) var lastErrorMessage: String?
  private(set) var routeLabel = "Telefon"

  fileprivate func present(_ call: VoiceCallPresentation, muted: Bool) {
    activeCall = call
    isMuted = muted
  }

  fileprivate func setAudioActive(_ active: Bool) {
    isAudioActive = active
  }

  fileprivate func setMuted(_ muted: Bool) {
    isMuted = muted
  }

  fileprivate func setProximityCovered(_ covered: Bool) {
    isProximityCovered = covered
  }

  fileprivate func setRoute(label: String, speaker: Bool) {
    routeLabel = label
    isSpeakerEnabled = speaker
  }

  func clearError() {
    lastErrorMessage = nil
  }

  fileprivate func setError(_ message: String) {
    lastErrorMessage = message
  }

  fileprivate func clear() {
    activeCall = nil
    isAudioActive = false
    isMuted = false
    isProximityCovered = false
    isSpeakerEnabled = false
    routeLabel = "Telefon"
  }
}

private enum LiveKitCallEvent: Sendable {
  case connected
  case disconnected(String?)
  case participantConnected(id: String, name: String)
  case participantDisconnected(id: String)
}

private final class VoiceCallRoomBinding: @unchecked Sendable { weak var room: Room? }

private final class LiveKitCallObserver: NSObject, RoomDelegate, @unchecked Sendable {
  let handler: @Sendable (LiveKitCallEvent) -> Void

  init(handler: @escaping @Sendable (LiveKitCallEvent) -> Void) {
    self.handler = handler
  }

  func roomDidConnect(_ room: Room) {
    handler(.connected)
  }

  func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
    handler(.disconnected(error?.localizedDescription))
  }

  func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
    handler(
      .participantConnected(
        id: participant.identity?.stringValue ?? participant.sid?.stringValue ?? "remote",
        name: participant.name ?? participant.identity?.stringValue ?? "Účastník"
      )
    )
  }

  func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
    handler(
      .participantDisconnected(
        id: participant.identity?.stringValue ?? participant.sid?.stringValue ?? "remote"
      )
    )
  }
}

@MainActor
public final class VoiceCallService:
  NSObject, @preconcurrency CXProviderDelegate, @preconcurrency PKPushRegistryDelegate
{
  private static var existingInstance: VoiceCallService?
  public static var shared: VoiceCallService {
    if let existingInstance { return existingInstance }
    let service = VoiceCallService()
    existingInstance = service
    return service
  }
  /// Reading this property never constructs the voice, audio or push service.
  public static var existingHostState: VoiceCallHostState? { existingInstance?.hostState }
  public var hostState: VoiceCallHostState { lifecycle.state }

  /// Call with the account snapshot captured before withdrawing communication.
  /// This is exclusively local; remote cleanup needs server assistance.
  public static func suspendExisting(expectedScope: String, expectedGeneration: UUID) -> VoiceCallSuspensionResult {
    guard let existingInstance else { return .notInitialized }
    return existingInstance.suspend(expectedScope: expectedScope, expectedGeneration: expectedGeneration)
  }

  @discardableResult
  public func resumeForHostCommunication(expectedScope: String, expectedGeneration: UUID) throws -> VoiceCallHostState {
    let snapshot = controls.snapshot()
    guard snapshot.enabled, snapshot.scope == expectedScope, snapshot.generation == expectedGeneration,
      snapshot.policy == .explicitHostConsent else { throw VoiceCallHostLifecycleError.ownerChanged }
    if !lifecycle.suspended, !lifecycle.matches(scope: expectedScope, generation: expectedGeneration) {
      suspendLocally()
    }
    pruneRetiredSystemBindings()
    // One current provider and at most one report-only retiring provider. Never
    // allocate an unbounded series while the OS holds a report completion.
    if presentationMode == .system, activeSystemBinding == nil, systemBindings.count >= 2 {
      throw VoiceCallHostLifecycleError.systemCleanupPending
    }
    try lifecycle.resume(snapshot: snapshot, expectedScope: expectedScope,
      expectedGeneration: expectedGeneration, endpointID: controls.endpointID())
    activateNativeResources()
    return hostState
  }
  public let presentationMode: VoiceCallPresentationMode

  public static func recordDiagnostic(_ event: String, result: String? = nil) {
    CallDiagnosticStore.record(event, result: result)
  }

  private struct CallContext {
    let owner: VoiceCallOwner
    var call: CSMVoiceCall
    var avatarDataURL: String?
    var registeredWithCallKit: Bool
    var answered: Bool
    var muted: Bool
    var participants: [VoiceCallParticipant]
    var incomingPushTitle: String? = nil
    var mediaTransitionInFlight = false
    var reportedConnected = false
    var diagnosticCorrelation = String(UUID().uuidString.prefix(8))
    var lastMediaDiagnostic: String? = nil
  }

  let presentation = VoiceCallPresentationState()

  public var hasActiveCall: Bool { presentation.activeCall != nil }
  public var lastErrorMessage: String? { presentation.lastErrorMessage }

  public func clearCallError() {
    presentation.clearError()
  }

  private var provider: CXProvider?
  private var callController: CXCallController?
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "cz.voldzi.copmobile",
    category: "native-voice-call"
  )
  private var registry: PKPushRegistry?
  private var calls: [UUID: CallContext] = [:]
  private var activeRoom: Room?
  private var callStartInFlight = false
  private var activeRoomCallUUID: UUID?
  private var audioActivated = false
  private var roomConnected = false
  private var microphonePublished = false
  private var statePollingTask: Task<Void, Never>?
  private let connectionDeadline = VoiceCallConnectionDeadline()
  private var pushTokenState: VoiceCallPushTokenState
  private var tokenContinuation: CheckedContinuation<String, any Error>?
  private var tokenTimeoutTask: Task<Void, Never>?
  private var tokenRegistrationRecoveryTask: Task<Void, Never>?
  private var tokenRegistrationRecoveryAttempted = false
  private var proximityMonitoringEnabled = false
  private var foregroundReconciliationTask: Task<Void, Never>?
  private let lifecycle: VoiceCallHostLifecycle
  private let controls: VoiceCallServiceControls
  private var hardwareObserversInstalled = false
  private var audioConfiguredEpoch: UUID?
  private var activeSystemBinding: VoiceCallSystemBinding?
  private var systemBindings: [UUID: VoiceCallSystemBinding] = [:]
  private var providerBindings: [ObjectIdentifier: VoiceCallSystemBinding] = [:]
  private var registryBindings: [ObjectIdentifier: VoiceCallSystemBinding] = [:]
  private var activeRoomObserver: LiveKitCallObserver?
  private var startAttemptTask: Task<Void, Never>?
  private var startAttemptID: UUID?

  private override convenience init() {
    let value = Bundle.main.object(forInfoDictionaryKey: "CSMCommunicationActivationPolicy")
    let policy: CSMCommunicationActivationPolicy = value == nil || value as? String == "automatic"
      ? .automatic : value as? String == "explicit_host_consent" ? .explicitHostConsent : .invalid
    self.init(presentationMode: VoiceCallDistributionPolicy.currentMode, activationPolicy: policy, controls: .live)
  }

  init(presentationMode: VoiceCallPresentationMode, activationPolicy: CSMCommunicationActivationPolicy,
       controls: VoiceCallServiceControls) {
    self.presentationMode = presentationMode
    self.controls = controls
    lifecycle = VoiceCallHostLifecycle(policy: activationPolicy)
    if activationPolicy == .explicitHostConsent {
      let snapshot = controls.snapshot()
      if snapshot.enabled, let scope = snapshot.scope {
        try? lifecycle.resume(snapshot: snapshot, expectedScope: scope,
          expectedGeneration: snapshot.generation, endpointID: controls.endpointID())
      }
    }
    pushTokenState = VoiceCallPushTokenState(
      cachedToken: presentationMode == .system && !lifecycle.suspended ? VoiceCallPushTokenStore.load() : nil
    )
    super.init()
    if activationPolicy != .automatic {
      NotificationCenter.default.addObserver(self, selector: #selector(hostCommunicationChanged),
        name: .csmHostCommunicationConsentChanged, object: nil)
      NotificationCenter.default.addObserver(self, selector: #selector(hostCommunicationChanged),
        name: .csmJizdaLifecycleReadinessChanged, object: nil)
    }
    if presentationMode == .inApp {
      VoiceCallPushTokenStore.remove()
      CallDiagnosticStore.record("voice.in-app.no-callkit-pushkit")
    }
    if !lifecycle.suspended { activateNativeResources() }
  }

  private func activateNativeResources() {
    guard !lifecycle.suspended else { return }
    pruneRetiredSystemBindings()
    if audioConfiguredEpoch != lifecycle.epoch {
      controls.initializeAudio()
      audioConfiguredEpoch = lifecycle.epoch
    }
    if presentationMode == .system, activeSystemBinding == nil {
      let binding = controls.makeSystem(self, lifecycle.epoch)
      activeSystemBinding = binding
      systemBindings[binding.id] = binding
      provider = binding.provider; callController = binding.controller; registry = binding.registry
      if let provider { providerBindings[ObjectIdentifier(provider)] = binding }
      if let registry { registryBindings[ObjectIdentifier(registry)] = binding }
    }
    guard controls.observeHardware, !hardwareObserversInstalled else { return }
    hardwareObserversInstalled = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(proximityStateDidChange),
      name: UIDevice.proximityStateDidChangeNotification,
      object: UIDevice.current
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioRouteDidChange),
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance()
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(audioSessionWasInterrupted(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    CallDiagnosticStore.record("voice.native.initialized")
    if pushTokenState.cachedToken != nil {
      CallDiagnosticStore.record("pushkit.token.cached-awaiting-confirmation")
    }
  }

  @discardableResult
  func suspend(expectedScope: String, expectedGeneration: UUID) -> VoiceCallSuspensionResult {
    guard lifecycle.policy != .automatic else { return .automaticPolicy }
    guard lifecycle.matches(scope: expectedScope, generation: expectedGeneration) else { return .ownerMismatch }
    if !lifecycle.suspended { suspendLocally() }
    return .suspended(hostState)
  }

  private func suspendLocally() {
    lifecycle.suspend(needsServerAssistance: !calls.isEmpty || callStartInFlight)
    startAttemptTask?.cancel(); startAttemptTask = nil; startAttemptID = nil; callStartInFlight = false
    statePollingTask?.cancel(); statePollingTask = nil
    foregroundReconciliationTask?.cancel(); foregroundReconciliationTask = nil
    tokenTimeoutTask?.cancel(); tokenTimeoutTask = nil
    tokenRegistrationRecoveryTask?.cancel(); tokenRegistrationRecoveryTask = nil
    tokenContinuation?.resume(throwing: VoiceCallPushRegistrationError.registrationFailed)
    tokenContinuation = nil
    pushTokenState.invalidate(); VoiceCallPushTokenStore.remove()
    tokenRegistrationRecoveryAttempted = false
    let endingBinding = activeSystemBinding
    endingBinding?.retire()
    activeSystemBinding = nil; provider = nil; registry = nil; callController = nil
    // Stop only this app's engine. CallKit remains the system audio owner.
    if audioActivated { controls.stopAudio() }
    for uuid in Array(calls.keys) {
      if endingBinding?.reportIsPending(uuid) == false {
        endingBinding?.reporter.reportEnded(uuid: uuid)
      }
      tearDown(uuid: uuid, reportServer: false, notifyTimeline: false)
    }
    audioActivated = false; presentation.setAudioActive(false)
    cachedMedia.removeAll(); presentation.clear(); connectionDeadline.cancel()
  }

  @objc private func hostCommunicationChanged() {
    guard lifecycle.policy != .automatic, let owner = lifecycle.owner else { return }
    let snapshot = controls.snapshot()
    if !snapshot.enabled || snapshot.scope != owner.scope || snapshot.generation != owner.generation {
      if !lifecycle.suspended { suspendLocally() }
    }
  }

  private func capturedOwner() -> VoiceCallOwner? {
    if lifecycle.policy == .automatic {
      return .init(scope: nil, generation: nil, epoch: lifecycle.epoch, endpointID: controls.endpointID())
    }
    guard let owner = lifecycle.owner, permits(owner) else { return nil }
    return owner
  }
  private func permits(_ owner: VoiceCallOwner) -> Bool {
    lifecycle.permits(owner, snapshot: lifecycle.policy == .automatic ? nil : controls.snapshot())
  }
  private func isCurrent(_ binding: VoiceCallSystemBinding) -> Bool {
    activeSystemBinding === binding && !binding.retired && binding.epoch == lifecycle.epoch && !lifecycle.suspended &&
      (lifecycle.policy == .automatic || capturedOwner() != nil)
  }
  private func pruneRetiredSystemBindings() {
    let expired = systemBindings.filter { $0.value.retired && !$0.value.hasRegistry && !$0.value.hasPendingReports }
    for (id, binding) in expired {
      systemBindings.removeValue(forKey: id)
      providerBindings = providerBindings.filter { $0.value !== binding }
      registryBindings = registryBindings.filter { $0.value !== binding }
      binding.provider?.setDelegate(nil, queue: .main)
      binding.provider?.invalidate()
    }
  }

  public func prepareForApplicationLaunch() {
    guard capturedOwner() != nil, presentationMode == .system, let registry else {
      CallDiagnosticStore.record("voice.in-app.launch-prepared")
      return
    }
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    synchronizeCurrentPushToken()
    recoverPushRegistrationIfNeeded()
    CallDiagnosticStore.record("voice.native.launch-prepared")
  }

  public func currentPushToken() async throws -> String {
    guard let owner = capturedOwner(), presentationMode == .system else {
      throw VoiceCallPushRegistrationError.registrationFailed
    }
    synchronizeCurrentPushToken()
    if let pushToken = pushTokenState.tokenForServerRegistration {
      return pushToken
    }
    guard tokenContinuation == nil else {
      throw VoiceCallPushRegistrationError.registrationPending
    }
    let token: String = try await withCheckedThrowingContinuation { continuation in
      tokenContinuation = continuation
      tokenTimeoutTask?.cancel()
      tokenTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(12))
        guard !Task.isCancelled, let self, let continuation = self.tokenContinuation else {
          return
        }
        self.tokenContinuation = nil
        self.tokenTimeoutTask = nil
        continuation.resume(throwing: VoiceCallPushRegistrationError.registrationFailed)
      }
    }
    guard permits(owner) else { throw VoiceCallPushRegistrationError.registrationFailed }
    return token
  }

  public func currentPushTokenIfAvailable() async -> String? {
    guard capturedOwner() != nil, presentationMode == .system else { return nil }
    synchronizeCurrentPushToken()
    return pushTokenState.tokenForServerRegistration
  }

  public func applicationDidBecomeActive() {
    guard let owner = capturedOwner() else { return }
    if presentationMode == .inApp { resumeInAppAudioIfNeeded() }
    if presentationMode == .system {
      synchronizeCurrentPushToken()
      recoverPushRegistrationIfNeeded()
    }
    foregroundReconciliationTask?.cancel()
    foregroundReconciliationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled, let self, self.permits(owner) else { return }
      if self.presentationMode == .system { self.synchronizeCurrentPushToken() }
      await CSMCommunicationNotifications.prepareDeviceRegistration(
        voipDeviceTokenProvider: self.currentPushTokenIfAvailable
      )
      guard !Task.isCancelled, self.permits(owner) else { return }
      await self.reconcileActiveIncomingCalls()
    }
  }

  public func incomingUserNotificationReceived() {
    guard let owner = capturedOwner(), presentationMode == .inApp else { return }
    Task { @MainActor [weak self] in
      guard let self, self.permits(owner) else { return }
      await self.reconcileActiveIncomingCalls()
    }
  }

  public func startVoiceCall(
    roomID: String,
    title: String,
    participantSubjectIDs: [String]?,
    avatarDataURL: String? = nil,
    registerWithSystemCallUI: Bool = true
  ) {
    guard let owner = capturedOwner() else { return }
    presentation.clearError()
    guard !callStartInFlight else { return }
    guard presentation.activeCall == nil else {
      presentation.setError("Jiný hovor už probíhá.")
      return
    }
    let normalizedRoomID = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRoomID.isEmpty, !normalizedTitle.isEmpty else {
      presentation.setError("Konverzace zatím není připravena pro hovor.")
      return
    }
    callStartInFlight = true
    let attemptID = UUID()
    startAttemptID = attemptID
    startAttemptTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        if self.startAttemptID == attemptID {
          self.callStartInFlight = false; self.startAttemptID = nil; self.startAttemptTask = nil
        }
      }
      do {
        let permission = await self.controls.permission()
        guard !Task.isCancelled, self.permits(owner) else { return }
        guard permission else {
          throw CSMVoiceCallControlError.mediaUnavailable
        }
        let session = try await self.controls.start(normalizedRoomID, normalizedTitle, participantSubjectIDs, owner)
        guard !Task.isCancelled, self.permits(owner) else { return }
        try self.install(
          session: session,
          owner: owner,
          title: normalizedTitle,
          avatarDataURL: avatarDataURL,
          registeredWithCallKit: false,
          answered: false
        )
        guard let uuid = UUID(uuidString: session.call.callId) else {
          throw CSMVoiceCallControlError.mediaUnavailable
        }
        if registerWithSystemCallUI && self.presentationMode == .system {
          self.requestStartCall(uuid: uuid, title: normalizedTitle)
        } else {
          try self.activateInAppAudio(action: "start")
          await self.connectMedia(session: session, uuid: uuid, expectedOwner: owner)
        }
      } catch {
        guard !Task.isCancelled, self.permits(owner) else { return }
        self.failVisibleCall(error)
      }
    }
  }

  func answerActiveCall() {
    guard let call = presentation.activeCall, call.direction == .incoming,
      let owner = calls[call.id]?.owner, permits(owner) else { return }
    if presentationMode == .system {
      requestCallKitAction(CXAnswerCallAction(call: call.id))
    } else {
      Task { @MainActor [weak self] in await self?.acceptAndConnect(uuid: call.id, expectedOwner: owner) }
    }
  }

  func endActiveCall() {
    guard let call = presentation.activeCall, let owner = calls[call.id]?.owner, permits(owner) else { return }
    if presentationMode == .system {
      requestCallKitAction(CXEndCallAction(call: call.id))
    } else if let context = calls[call.id] {
      let action: CSMVoiceCallAction =
        context.call.direction == .incoming && !context.answered ? .decline
        : context.call.phase == .ringing && context.call.direction == .outgoing ? .cancel : .end
      tearDown(uuid: call.id, reportServer: true, action: action)
    }
  }

  func toggleMute() {
    guard let call = presentation.activeCall, let owner = calls[call.id]?.owner, permits(owner) else { return }
    if presentationMode == .system {
      requestCallKitAction(CXSetMutedCallAction(call: call.id, muted: !presentation.isMuted))
    } else if var context = calls[call.id] {
      context.muted.toggle()
      calls[call.id] = context
      presentation.setMuted(context.muted)
      let muted = context.muted
      Task { @MainActor [weak self] in
        guard let self, self.permits(owner), self.activeRoomCallUUID == call.id,
          let room = self.activeRoom else { return }
        _ = try? await room.localParticipant.setMicrophone(enabled: !muted)
        if !self.permits(owner) || self.activeRoom !== room {
          _ = try? await room.localParticipant.setMicrophone(enabled: false)
        }
      }
    }
  }

  func toggleSpeaker() {
    guard let call = presentation.activeCall, let owner = calls[call.id]?.owner, permits(owner) else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      let enableSpeaker = !presentation.isSpeakerEnabled
      try session.overrideOutputAudioPort(enableSpeaker ? .speaker : .none)
      updateAudioRoute(using: session)
    } catch {
      logger.error("Audio route change failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  public func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP, let binding = registryBindings[ObjectIdentifier(registry)], isCurrent(binding) else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    acceptPushToken(token, source: "callback")
  }

  public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP, let binding = registryBindings[ObjectIdentifier(registry)], isCurrent(binding) else { return }
    pushTokenState.invalidate()
    VoiceCallPushTokenStore.remove()
    tokenTimeoutTask?.cancel()
    tokenTimeoutTask = nil
    tokenContinuation?.resume(throwing: VoiceCallPushRegistrationError.registrationFailed)
    tokenContinuation = nil
    CSMCommunicationNotifications.recordVoIPDeviceTokenUpdate()
  }

  public func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    guard let binding = registryBindings[ObjectIdentifier(registry)] else { completion(); return }
    receive(payload: payload.dictionaryPayload, binding: binding, completion: completion)
  }

  func receive(payload: [AnyHashable: Any], binding: VoiceCallSystemBinding, completion: @escaping () -> Void) {
    guard presentationMode == .system else {
      completion()
      return
    }
    CallDiagnosticStore.record("pushkit.incoming.received")
    guard let push = VoiceCallPushPayload(dictionary: payload) else {
      CallDiagnosticStore.record("pushkit.rejected", result: "invalid-payload")
      completion()
      return
    }
    guard isCurrent(binding), let owner = capturedOwner() else {
      if push.event == .incoming { binding.beginReport(push.uuid) }
      VoiceCallLatePushReporting.receive(push, reporter: binding.reporter) { [weak self] in
        if push.event == .incoming { binding.finishReport(push.uuid) }
        completion()
        self?.pruneRetiredSystemBindings()
      }
      return
    }
    let provider = binding.provider

    if push.event == .ended || push.event == .answeredElsewhere {
      let isWinningEndpoint =
        push.event == .answeredElsewhere
        && push.acceptedEndpointID == owner.endpointID
      if !isWinningEndpoint {
        let hadLocalCall = calls[push.uuid] != nil
        CallDiagnosticStore.record(
          push.event == .answeredElsewhere ? "pushkit.call.answered-elsewhere" : "pushkit.call.ended"
        )
        provider?.reportCall(
          with: push.uuid,
          endedAt: Date(),
          reason: push.event == .answeredElsewhere ? .answeredElsewhere : .remoteEnded
        )
        tearDown(uuid: push.uuid, reportServer: false)
        if !hadLocalCall {
          notifyCallTimelineChanged(roomID: push.roomID)
        }
      }
      completion()
      return
    }

    if calls[push.uuid] != nil {
      CallDiagnosticStore.record("pushkit.duplicate.ignored")
      completion()
      return
    }

    CallDiagnosticStore.record("pushkit.call.incoming")
    let now = Date()
    let call = CSMVoiceCall(
      callId: push.callID,
      connectedAt: nil,
      createdAt: now,
      direction: .incoming,
      endedAt: nil,
      endReason: nil,
      expiresAt: now.addingTimeInterval(90),
      initiatorSubjectId: "remote",
      kind: .direct,
      participantSubjectIds: [],
      phase: .ringing,
      revision: 1,
      roomId: push.roomID,
      title: push.callerDisplayName,
      updatedAt: now
    )
    calls[push.uuid] = CallContext(
      owner: owner,
      call: call,
      avatarDataURL: nil,
      registeredWithCallKit: true,
      answered: false,
      muted: false,
      participants: [],
      incomingPushTitle: push.callerDisplayName
    )
    publish(push.uuid)
    startStatePolling(uuid: push.uuid)

    reportIncoming(push, binding: binding, owner: owner, completion: completion)
  }

  private func reportIncoming(_ push: VoiceCallPushPayload, binding: VoiceCallSystemBinding,
                              owner: VoiceCallOwner, completion: @escaping () -> Void) {
    reportIncoming(uuid: push.uuid, title: push.callerDisplayName, binding: binding, owner: owner) { _ in
      completion()
    }
  }

  private func reportIncoming(uuid: UUID, title: String, binding: VoiceCallSystemBinding,
                              owner: VoiceCallOwner, completion: @escaping (Bool) -> Void) {
    var result = false
    let once = VoiceCallOnceCompletion { completion(result) }
    binding.beginReport(uuid)
    binding.reporter.reportIncoming(uuid: uuid, title: title) { [weak self] succeeded in
      guard once.isPending else { return }
      result = succeeded
      binding.finishReport(uuid)
      defer { once.finish(); self?.pruneRetiredSystemBindings() }
      guard let self else { if succeeded { binding.reporter.reportEnded(uuid: uuid) }; return }
      guard self.isCurrent(binding), self.permits(owner) else {
        if succeeded { binding.reporter.reportEnded(uuid: uuid) }
        self.tearDown(uuid: uuid, reportServer: false, notifyTimeline: false, expectedOwner: owner)
        return
      }
      if !succeeded { self.tearDown(uuid: uuid, reportServer: true, action: .decline) }
      CallDiagnosticStore.record("callkit.incoming.reported", result: succeeded ? "success" : "failed")
    }
  }

  private func synchronizeCurrentPushToken() {
    guard capturedOwner() != nil, presentationMode == .system, let data = registry?.pushToken(for: .voIP) else { return }
    let token = data.map { String(format: "%02x", $0) }.joined()
    guard !token.isEmpty else { return }
    acceptPushToken(token, source: "registry")
  }

  /// PushKit normally returns its cached token after assigning
  /// `desiredPushTypes`. After an in-place development install the cache can be
  /// empty while the server still holds the previous token. In that one state
  /// perform a single process-scoped unregister/register cycle so PushKit
  /// issues current credentials instead of leaving incoming calls unreachable.
  private func recoverPushRegistrationIfNeeded() {
    guard let owner = capturedOwner(), let binding = activeSystemBinding,
      pushTokenState.needsRegistrationRecovery,
      !tokenRegistrationRecoveryAttempted
    else { return }
    tokenRegistrationRecoveryAttempted = true
    tokenRegistrationRecoveryTask?.cancel()
    tokenRegistrationRecoveryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let self, self.permits(owner), self.isCurrent(binding) else { return }
      self.synchronizeCurrentPushToken()
      guard self.presentationMode == .system, self.pushTokenState.needsRegistrationRecovery,
        let registry = self.registry else { return }
      CallDiagnosticStore.record("pushkit.registration.recovery.started")
      registry.desiredPushTypes = []
      await Task.yield()
      guard !Task.isCancelled, self.permits(owner), self.isCurrent(binding), self.registry === registry else { return }
      registry.desiredPushTypes = [.voIP]
      try? await Task.sleep(for: .seconds(12))
      guard !Task.isCancelled, self.permits(owner), self.isCurrent(binding) else { return }
      self.synchronizeCurrentPushToken()
      if self.pushTokenState.needsRegistrationRecovery {
        CallDiagnosticStore.record("pushkit.registration.recovery.timed-out")
      }
      self.tokenRegistrationRecoveryTask = nil
    }
  }

  private func acceptPushToken(_ token: String, source: String) {
    guard capturedOwner() != nil else { return }
    let shouldRefreshServer = pushTokenState.confirm(token)
    VoiceCallPushTokenStore.save(token)
    tokenTimeoutTask?.cancel()
    tokenTimeoutTask = nil
    tokenContinuation?.resume(returning: token)
    tokenContinuation = nil
    if shouldRefreshServer {
      CallDiagnosticStore.record("pushkit.token.confirmed", result: source)
      CSMCommunicationNotifications.recordVoIPDeviceTokenUpdate()
    }
    tokenRegistrationRecoveryTask?.cancel()
    tokenRegistrationRecoveryTask = nil
  }

  func reconcileActiveIncomingCalls() async {
    guard let owner = capturedOwner() else { return }
    do {
      let activeCalls = try await controls.list(owner)
      guard !Task.isCancelled, permits(owner) else { return }
      for call in activeCalls where call.direction == .incoming && !call.phase.isTerminal {
        guard let uuid = UUID(uuidString: call.callId), calls[uuid] == nil else { continue }
        calls[uuid] = CallContext(
          owner: owner,
          call: call,
          avatarDataURL: nil,
          registeredWithCallKit: presentationMode == .system,
          answered: false,
          muted: false,
          participants: []
        )
        publish(uuid)
        startStatePolling(uuid: uuid)
        guard let binding = activeSystemBinding, isCurrent(binding) else { continue }
        // The OS report may outlive OFF. Retain this exact epoch/provider until
        // its one completion, using the same pending accounting as PushKit.
        let succeeded = await withCheckedContinuation { continuation in
          reportIncoming(uuid: uuid, title: call.presentationTitle, binding: binding, owner: owner) {
            continuation.resume(returning: $0)
          }
        }
        guard !Task.isCancelled, permits(owner), isCurrent(binding) else { return }
        CallDiagnosticStore.record("callkit.incoming.reconciled", result: succeeded ? "success" : "failed")
      }
    } catch {
      guard !Task.isCancelled, permits(owner) else { return }
      CallDiagnosticStore.record(
        "voice.active-reconciliation.failed",
        result: error.localizedDescription
      )
    }
  }

  public func providerDidReset(_ provider: CXProvider) {
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding) else { return }
    let active = Array(calls.keys)
    for uuid in active {
      tearDown(uuid: uuid, reportServer: lifecycle.policy == .automatic, action: .end,
        notifyTimeline: lifecycle.policy == .automatic)
    }
  }

  public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding),
      var context = calls[action.callUUID], permits(context.owner) else {
      action.fail()
      return
    }
    prepareAudioSession(action: "start")
    context.registeredWithCallKit = true
    calls[action.callUUID] = context
    action.fulfill()
    provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
    publish(action.callUUID)
    guard let session = mediaSession(for: context.call) else {
      fail(uuid: action.callUUID, error: CSMVoiceCallControlError.mediaUnavailable)
      return
    }
    Task { @MainActor [weak self] in
      await self?.connectMedia(session: session, uuid: action.callUUID, expectedOwner: context.owner)
    }
  }

  public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding),
      var context = calls[action.callUUID], permits(context.owner),
      context.call.direction == .incoming,
      !context.answered
    else {
      action.fail()
      return
    }
    prepareAudioSession(action: "answer")
    context.answered = true
    calls[action.callUUID] = context
    publish(action.callUUID)
    action.fulfill()
    Task { @MainActor [weak self] in
      await self?.acceptAndConnect(uuid: action.callUUID, expectedOwner: context.owner)
    }
  }

  public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding),
      var context = calls[action.callUUID], permits(context.owner) else {
      action.fail()
      return
    }
    context.muted = action.isMuted
    calls[action.callUUID] = context
    presentation.setMuted(action.isMuted)
    action.fulfill()
    Task { @MainActor [weak self] in
      guard let self, self.permits(context.owner), self.activeRoomCallUUID == action.callUUID,
        let room = self.activeRoom else { return }
      _ = try? await room.localParticipant.setMicrophone(enabled: !action.isMuted)
      if !self.permits(context.owner) || self.activeRoom !== room {
        _ = try? await room.localParticipant.setMicrophone(enabled: false)
      }
    }
  }

  public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding),
      let context = calls[action.callUUID], permits(context.owner) else {
      action.fulfill()
      return
    }
    let serverAction: CSMVoiceCallAction =
      context.call.direction == .incoming && !context.answered ? .decline
      : context.call.phase == .ringing && context.call.direction == .outgoing ? .cancel
      : .end
    action.fulfill()
    tearDown(uuid: action.callUUID, reportServer: true, action: serverAction)
  }

  public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    action.fail()
    guard let binding = providerBindings[ObjectIdentifier(provider)], isCurrent(binding) else { return }
    if let callAction = action as? CXCallAction {
      fail(
        uuid: callAction.callUUID,
        error: CSMVoiceCallControlError.mediaUnavailable
      )
    }
  }

  public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    guard let binding = providerBindings[ObjectIdentifier(provider)] else { return }
    systemAudioDidActivate(binding: binding, audioSession: audioSession)
  }

  func systemAudioDidActivate(binding: VoiceCallSystemBinding, audioSession: AVAudioSession) {
    guard isCurrent(binding) else { return }
    do {
      // CallKit has already activated this session. Mutating its category here
      // can synchronously block the main thread on iOS 27. The category is
      // prepared before fulfilling the start/answer action instead.
      try controls.activateSystemAudio()
      audioActivated = true
      if let uuid = activeRoomCallUUID { refreshConnectionDeadline(uuid: uuid) }
      presentation.setAudioActive(true)
      updateAudioRoute(using: audioSession)
      updateProximityPolicy()
      Task { @MainActor [weak self] in
        guard let self, self.isCurrent(binding) else { return }
        await self.publishMicrophoneIfReady()
      }
    } catch {
      if let uuid = activeRoomCallUUID {
        fail(uuid: uuid, error: error)
      }
    }
  }

  public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    guard let binding = providerBindings[ObjectIdentifier(provider)] else { return }
    systemAudioDidDeactivate(binding: binding)
  }

  func systemAudioDidDeactivate(binding: VoiceCallSystemBinding) {
    guard isCurrent(binding) else { return }
    audioActivated = false
    if let uuid = activeRoomCallUUID { refreshConnectionDeadline(uuid: uuid) }
    presentation.setAudioActive(false)
    controls.stopAudio()
    updateProximityPolicy()
  }

  private func requestStartCall(uuid: UUID, title: String) {
    let handle = CXHandle(type: .generic, value: title)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = false
    requestCallKitAction(action)
  }

  private func requestCallKitAction(_ action: CXAction) {
    guard let callAction = action as? CXCallAction, let owner = calls[callAction.callUUID]?.owner,
      permits(owner), presentationMode == .system, let callController else { return }
    callController.request(CXTransaction(action: action)) { [weak self] error in
      guard let error else { return }
      Task { @MainActor in
        guard let self, self.permits(owner), self.calls[callAction.callUUID]?.owner == owner else { return }
        self.logger.error(
          "CallKit transaction failed: \(error.localizedDescription, privacy: .public)"
        )
        if let callAction = action as? CXCallAction {
          self.fail(uuid: callAction.callUUID, error: error)
        }
      }
    }
  }

  private func install(
    session: CSMVoiceCallSession,
    owner: VoiceCallOwner,
    title: String,
    avatarDataURL: String?,
    registeredWithCallKit: Bool,
    answered: Bool
  ) throws {
    guard permits(owner), let uuid = UUID(uuidString: session.call.callId), calls[uuid] == nil else {
      throw CSMVoiceCallControlError.mediaUnavailable
    }
    let call = replacingTitle(session.call, title: title)
    calls[uuid] = CallContext(
      owner: owner,
      call: call,
      avatarDataURL: avatarDataURL,
      registeredWithCallKit: registeredWithCallKit,
      answered: answered,
      muted: false,
      participants: []
    )
    presentation.clearError()
    publish(uuid)
    startStatePolling(uuid: uuid)
    if let media = session.media {
      cachedMedia[call.callId] = media
    }
  }

  private var cachedMedia: [String: CSMVoiceCallMediaCredentials] = [:]

  private func mediaSession(for call: CSMVoiceCall) -> CSMVoiceCallSession? {
    guard let media = cachedMedia[call.callId] else { return nil }
    return CSMVoiceCallSession(
      contractVersion: "cop-voice-call-v1",
      call: call,
      media: media
    )
  }

  private func acceptAndConnect(uuid: UUID, expectedOwner: VoiceCallOwner) async {
    guard let context = calls[uuid], context.owner == expectedOwner, permits(context.owner) else { return }
    do {
      let permission = await controls.permission()
      guard !Task.isCancelled, permits(context.owner), calls[uuid]?.owner == context.owner else { return }
      guard permission else {
        throw CSMVoiceCallControlError.mediaUnavailable
      }
      if presentationMode == .inApp { try activateInAppAudio(action: "answer") }
      let accepted = try await controls.transition(context.call.callId, .accept, context.call.revision, nil, context.owner)
      guard !Task.isCancelled, permits(context.owner), calls[uuid]?.owner == context.owner else { return }
      if var current = calls[uuid] {
        current.answered = true
        calls[uuid] = current
      }
      apply(accepted, uuid: uuid)
      await connectMedia(session: accepted, uuid: uuid, expectedOwner: context.owner)
    } catch {
      guard !Task.isCancelled, permits(context.owner), calls[uuid]?.owner == context.owner else { return }
      // Another app or device of the same account may have won the atomic
      // accept. Reconcile before reporting a media failure; a losing endpoint
      // must never terminate the call that is already active elsewhere.
      if let session = try? await controls.fetch(context.call.callId, context.owner),
        permits(context.owner), calls[uuid]?.owner == context.owner,
        answeredElsewhere(session.call, owner: context.owner) {
        provider?.reportCall(with: uuid, endedAt: Date(), reason: .answeredElsewhere)
        tearDown(uuid: uuid, reportServer: false)
        return
      }
      guard permits(context.owner), calls[uuid]?.owner == context.owner else { return }
      fail(uuid: uuid, error: error)
    }
  }

  private func connectMedia(session: CSMVoiceCallSession, uuid: UUID, expectedOwner: VoiceCallOwner) async {
    guard let context = calls[uuid], context.owner == expectedOwner, permits(context.owner) else { return }
    let owner = context.owner
    guard let media = session.media else {
      fail(uuid: uuid, error: CSMVoiceCallControlError.mediaUnavailable)
      return
    }
    cachedMedia[session.call.callId] = media
    activeRoomCallUUID = uuid
    roomConnected = false
    microphonePublished = false

    let roomBinding = VoiceCallRoomBinding()
    let observer = LiveKitCallObserver { [weak self, roomBinding] event in
      Task { @MainActor in
        guard let room = roomBinding.room else { return }
        self?.handleLiveKitEvent(event, uuid: uuid, room: room, owner: owner)
      }
    }
    let room = Room(
      delegate: observer,
      roomOptions: RoomOptions(
        encryptionOptions: .sharedKey(media.e2eeKey)
      )
    )
    roomBinding.room = room
    activeRoomObserver = observer
    activeRoom = room
    refreshConnectionDeadline(uuid: uuid)
    do {
      try await room.connect(url: media.serverUrl.absoluteString, token: media.token)
      guard !Task.isCancelled, permits(owner), activeRoom === room,
        activeRoomCallUUID == uuid, calls[uuid]?.owner == owner else {
        await room.disconnect()
        return
      }
      roomConnected = true
      refreshConnectionDeadline(uuid: uuid)
      presentation.clearError()
      await publishMicrophoneIfReady()
      guard permits(owner), activeRoom === room, calls[uuid]?.owner == owner else { return }
      if !room.remoteParticipants.isEmpty {
        markMediaConnected(uuid: uuid)
      }
    } catch {
      guard permits(owner), calls[uuid]?.owner == owner else { return }
      fail(uuid: uuid, error: error)
    }
  }

  private func publishMicrophoneIfReady() async {
    guard audioActivated, roomConnected, !microphonePublished,
      let uuid = activeRoomCallUUID,
      let context = calls[uuid], permits(context.owner),
      let room = activeRoom
    else { return }
    do {
      try await room.localParticipant.setMicrophone(enabled: !context.muted)
      guard permits(context.owner), activeRoom === room, activeRoomCallUUID == uuid,
        calls[uuid]?.owner == context.owner else {
        _ = try? await room.localParticipant.setMicrophone(enabled: false)
        return
      }
      microphonePublished = true
      refreshConnectionDeadline(uuid: uuid)
      markMediaConnected(uuid: uuid)
    } catch {
      guard permits(context.owner), activeRoom === room, calls[uuid]?.owner == context.owner else { return }
      fail(uuid: uuid, error: error)
    }
  }

  private func handleLiveKitEvent(_ event: LiveKitCallEvent, uuid: UUID, room: Room, owner: VoiceCallOwner) {
    guard permits(owner), activeRoom === room, activeRoomCallUUID == uuid,
      var context = calls[uuid], context.owner == owner else { return }
    switch event {
    case .connected:
      roomConnected = true
      refreshConnectionDeadline(uuid: uuid)
      Task { @MainActor [weak self] in
        guard let self, self.permits(owner), self.activeRoom === room,
          self.activeRoomCallUUID == uuid else { return }
        await self.publishMicrophoneIfReady()
      }
    case .participantConnected(let id, let name):
      context.participants.removeAll { $0.userID == id }
      context.participants.append(
        VoiceCallParticipant(userID: id, displayName: name, connected: true)
      )
      calls[uuid] = context
      refreshConnectionDeadline(uuid: uuid)
      markMediaConnected(uuid: uuid)
    case .participantDisconnected(let id):
      context.participants = context.participants.map {
        $0.userID == id
          ? VoiceCallParticipant(
            userID: $0.userID,
            displayName: $0.displayName,
            connected: false
          )
          : $0
      }
      calls[uuid] = context
      refreshConnectionDeadline(uuid: uuid)
      publish(uuid)
    case .disconnected(let detail):
      guard context.call.phase != .ended else { return }
      fail(
        uuid: uuid,
        error: NSError(
          domain: "COPVoiceCall",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: detail ?? "Hovorové spojení bylo přerušeno."]
        )
      )
    }
  }

  private func connectionStage(uuid: UUID) -> VoiceCallConnectionPolicy.Stage? {
    guard let context = calls[uuid] else { return nil }
    return VoiceCallConnectionPolicy.stage(serverPhase: context.call.phase,
      roomConnected: activeRoomCallUUID == uuid && roomConnected,
      peerPresent: activeRoomCallUUID == uuid && activeRoom?.remoteParticipants.isEmpty == false,
      answered: context.answered, incoming: context.call.direction == .incoming,
      audioActivated: audioActivated, microphonePublished: microphonePublished)
  }

  private func markMediaConnected(uuid: UUID) {
    guard var context = calls[uuid], permits(context.owner), let stage = connectionStage(uuid: uuid),
      stage == .connected || stage == .waitingForServerAck else { return }
    refreshConnectionDeadline(uuid: uuid)
    if context.call.phase == .connected {
      guard !context.reportedConnected else { return }
      context.reportedConnected = true
      calls[uuid] = context
      publish(uuid)
      if context.call.direction == .outgoing {
        provider?.reportOutgoingCall(with: uuid, connectedAt: context.call.connectedAt ?? Date())
      }
      return
    }
    guard !context.mediaTransitionInFlight else { return }
    context.mediaTransitionInFlight = true
    calls[uuid] = context
    Task { @MainActor [weak self] in
      guard let self, let latest = self.calls[uuid], latest.owner == context.owner,
        self.permits(latest.owner) else { return }
      do {
        let session = try await self.controls.transition(latest.call.callId, .mediaConnected,
          latest.call.revision, nil, latest.owner)
        guard self.permits(latest.owner), var current = self.calls[uuid], current.owner == latest.owner else { return }
        current.mediaTransitionInFlight = false
        self.calls[uuid] = current
        self.apply(session, uuid: uuid)
        self.markMediaConnected(uuid: uuid)
      } catch {
        guard self.permits(latest.owner), var current = self.calls[uuid], current.owner == latest.owner else { return }
        current.mediaTransitionInFlight = false
        self.calls[uuid] = current
        self.recordConnectionDiagnostic(uuid: uuid, event: "voice.media.server_ack_pending")
      }
    }
  }

  private func startStatePolling(uuid: UUID) {
    statePollingTask?.cancel()
    statePollingTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self, let context = self.calls[uuid], self.permits(context.owner) else { return }
        do {
          let session = try await self.controls.fetch(context.call.callId, context.owner)
          guard !Task.isCancelled, self.permits(context.owner), self.calls[uuid]?.owner == context.owner else { return }
          self.apply(session, uuid: uuid)
          if session.call.phase.isTerminal { return }
        } catch {
          guard !Task.isCancelled, self.permits(context.owner), self.calls[uuid]?.owner == context.owner else { return }
          self.logger.debug(
            "Call state poll failed: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }

  private func apply(_ session: CSMVoiceCallSession, uuid: UUID) {
    guard var context = calls[uuid], permits(context.owner) else { return }
    if !context.answered && answeredElsewhere(session.call, owner: context.owner) {
      provider?.reportCall(with: uuid, endedAt: Date(), reason: .answeredElsewhere)
      tearDown(uuid: uuid, reportServer: false)
      return
    }
    context.call = session.call
    context.incomingPushTitle = nil
    calls[uuid] = context
    if let media = session.media {
      cachedMedia[session.call.callId] = media
    }
    if session.call.phase.isTerminal {
      provider?.reportCall(
        with: uuid,
        endedAt: session.call.endedAt ?? Date(),
        reason: callKitEndReason(session.call.phase)
      )
      tearDown(uuid: uuid, reportServer: false)
      return
    }
    refreshConnectionDeadline(uuid: uuid)
    publish(uuid)
    if (
      session.call.phase == .accepted || session.call.phase == .connectingMedia || session.call.phase == .connected
    ),
      activeRoomCallUUID == uuid,
      activeRoom?.remoteParticipants.isEmpty == false
    {
      markMediaConnected(uuid: uuid)
    }
  }


  private func answeredElsewhere(_ call: CSMVoiceCall, owner: VoiceCallOwner) -> Bool {
    guard call.direction == .incoming,
      let acceptedEndpointID = call.acceptedByEndpointId
    else { return false }
    let localEndpointID = owner.endpointID
    return acceptedEndpointID != localEndpointID
      && (call.phase == .accepted || call.phase == .connectingMedia || call.phase == .connected)
  }

  private func publish(_ uuid: UUID) {
    guard let context = calls[uuid], permits(context.owner) else { return }
    let phase: VoiceCallPhase = switch context.call.phase {
    case .created, .ringing:
      context.call.direction == .incoming && !context.answered ? .ringing : .connecting
    case .accepted, .connectingMedia:
      .connecting
    case .connected:
      connectionStage(uuid: uuid) == .connected ? .connected : .connecting
    case .declined, .missed, .cancelled, .ended:
      .ended
    case .failed:
      .failed
    }
    let direction: VoiceCallDirection =
      context.call.direction == .incoming ? .incoming : .outgoing
    presentation.present(
      VoiceCallPresentation(
        id: uuid,
        callID: context.call.callId,
        roomID: context.call.roomId,
        title: context.incomingPushTitle ?? context.call.presentationTitle,
        avatarDataURL: context.avatarDataURL,
        direction: direction,
        eligibleParticipants: [],
        kind: .direct,
        participants: context.participants,
        phase: phase,
        connectedAt: context.call.connectedAt
      ),
      muted: context.muted
    )
    updateProximityPolicy()
  }

  private func failVisibleCall(_ error: Error) {
    CallDiagnosticStore.record("voice.start.failed", result: "transport_or_media_error")
    logger.error("Voice call start failed: \(error.localizedDescription, privacy: .public)")
    presentation.setError(
      (error as? LocalizedError)?.errorDescription
        ?? "Hovor se nepodařilo zahájit. Zkontrolujte připojení a zkuste to znovu."
    )
  }

  private func fail(uuid: UUID, error: Error) {
    recordConnectionDiagnostic(uuid: uuid, event: "voice.call.failed")
    guard let context = calls[uuid], permits(context.owner) else { return }
    var failed = context
    failed.call = replacingPhase(context.call, phase: .failed, connectedAt: nil)
    calls[uuid] = failed
    publish(uuid)
    provider?.reportCall(with: uuid, endedAt: Date(), reason: .failed)
    Task { @MainActor [weak self] in
      guard let self, self.permits(context.owner) else { return }
      _ = try? await self.controls.transition(context.call.callId, .mediaFailed,
        context.call.revision, "native_media_failed", context.owner)
      try? await Task.sleep(for: .seconds(1))
      guard self.permits(context.owner) else { return }
      self.tearDown(uuid: uuid, reportServer: false, expectedOwner: context.owner)
    }
  }

  private func tearDown(
    uuid: UUID,
    reportServer: Bool,
    action: CSMVoiceCallAction = .end,
    notifyTimeline: Bool = true,
    expectedOwner: VoiceCallOwner? = nil
  ) {
    guard let context = calls[uuid], expectedOwner == nil || expectedOwner == context.owner else { return }
    calls.removeValue(forKey: uuid)
    statePollingTask?.cancel()
    statePollingTask = nil
    connectionDeadline.cancel()
    cachedMedia.removeValue(forKey: context.call.callId)

    if activeRoomCallUUID == uuid {
      let room = activeRoom
      activeRoom = nil
      activeRoomObserver = nil
      activeRoomCallUUID = nil
      roomConnected = false
      microphonePublished = false
      Task {
        await room?.disconnect()
      }
    }
    if presentation.activeCall?.id == uuid {
      presentation.clear()
    }
    setProximityMonitoring(false)
    if presentationMode == .inApp && audioActivated {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      try? AudioManager.shared.setEngineAvailability(.none)
      audioActivated = false
      presentation.setAudioActive(false)
    }

    if reportServer {
      Task { @MainActor [weak self] in
        guard let self, self.permits(context.owner) else { return }
        _ = try? await self.controls.transition(context.call.callId, action,
          context.call.revision, nil, context.owner)
        guard self.permits(context.owner), notifyTimeline else { return }
        self.notifyCallTimelineChanged(roomID: context.call.roomId)
      }
    } else if notifyTimeline {
      notifyCallTimelineChanged(roomID: context.call.roomId)
    }
  }

  private func notifyCallTimelineChanged(roomID: String) {
    NotificationCenter.default.post(
      name: .csmVoiceCallTimelineChanged,
      object: nil,
      userInfo: ["roomId": roomID]
    )
  }

  private func recordConnectionDiagnostic(uuid: UUID, event: String) {
    guard var context = calls[uuid], let stage = connectionStage(uuid: uuid) else { return }
    let result = "c=\(context.diagnosticCorrelation);direction=\(context.call.direction.rawValue);server=\(context.call.phase.rawValue);stage=\(stage.rawValue);room=\(roomConnected);peer=\(activeRoom?.remoteParticipants.isEmpty == false);answered=\(context.answered);audio=\(audioActivated);mic=\(microphonePublished)"
    if event == "voice.media.state", context.lastMediaDiagnostic == result { return }
    context.lastMediaDiagnostic = result
    calls[uuid] = context
    CallDiagnosticStore.record(event, result: result)
  }

  private func refreshConnectionDeadline(uuid: UUID) {
    guard let stage = connectionStage(uuid: uuid) else { return }
    recordConnectionDiagnostic(uuid: uuid, event: "voice.media.state")
    connectionDeadline.update(uuid: uuid, stage: stage,
      currentStage: { [weak self] in self?.connectionStage(uuid: uuid) },
      timedOut: { [weak self] in
        guard let self else { return }
        self.recordConnectionDiagnostic(uuid: uuid, event: "voice.media.timeout")
        self.fail(uuid: uuid, error: CSMVoiceCallControlError.mediaUnavailable)
      })
  }

  private func prepareAudioSession(action: String) {
    let session = AVAudioSession.sharedInstance()
    guard VoiceCallAudioSessionPolicy.needsConfiguration(
      category: session.category,
      mode: session.mode,
      options: session.categoryOptions,
      isActive: audioActivated
    ) else {
      CallDiagnosticStore.record("audio.configuration.reused", result: action)
      return
    }
    do {
      try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
      CallDiagnosticStore.record("audio.configuration.prepared", result: action)
    } catch {
      // CallKit owns activation. A WebKit or another audio client can make
      // this optional pre-configuration fail transiently; the call must still
      // proceed and use the session delivered by provider(_:didActivate:).
      CallDiagnosticStore.record(
        "audio.configuration.deferred",
        result: "\(action):\(error.localizedDescription)"
      )
      logger.warning(
        "Audio session preparation deferred for \(action, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func activateInAppAudio(action: String) throws {
    guard capturedOwner() != nil else { throw VoiceCallHostLifecycleError.ownerChanged }
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    try session.setActive(true)
    do {
      try AudioManager.shared.setEngineAvailability(.default)
    } catch {
      try? session.setActive(false, options: .notifyOthersOnDeactivation)
      throw error
    }
    audioActivated = true
    if let uuid = activeRoomCallUUID { refreshConnectionDeadline(uuid: uuid) }
    presentation.setAudioActive(true)
    updateAudioRoute(using: session)
    updateProximityPolicy()
    CallDiagnosticStore.record("audio.in-app.activated", result: action)
  }

  @objc private func proximityStateDidChange() {
    presentation.setProximityCovered(
      proximityMonitoringEnabled && UIDevice.current.proximityState
    )
  }

  @objc private func audioRouteDidChange() {
    guard !lifecycle.suspended else { return }
    updateAudioRoute(using: AVAudioSession.sharedInstance())
  }

  @objc private func audioSessionWasInterrupted(_ notification: Notification) {
    guard capturedOwner() != nil, presentationMode == .inApp, let value = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
      let type = AVAudioSession.InterruptionType(rawValue: value), activeRoomCallUUID != nil
    else { return }
    switch type {
    case .began:
      audioActivated = false
      presentation.setAudioActive(false)
      try? AudioManager.shared.setEngineAvailability(.none)
      microphonePublished = false
      if let uuid = activeRoomCallUUID { refreshConnectionDeadline(uuid: uuid) }
      setProximityMonitoring(false)
      CallDiagnosticStore.record("audio.in-app.interrupted")
    case .ended:
      let optionsValue = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) { resumeInAppAudioIfNeeded() }
    @unknown default:
      break
    }
  }

  private func resumeInAppAudioIfNeeded() {
    guard let owner = capturedOwner(), presentationMode == .inApp, !audioActivated,
      let uuid = activeRoomCallUUID else { return }
    do {
      try activateInAppAudio(action: "resume")
      Task { @MainActor [weak self] in
        guard let self, self.permits(owner), self.activeRoomCallUUID == uuid else { return }
        await self.publishMicrophoneIfReady()
      }
    } catch {
      CallDiagnosticStore.record("audio.in-app.resume-failed", result: error.localizedDescription)
      logger.warning("In-app audio resume failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func updateProximityPolicy() {
    let enabled =
      presentation.isAudioActive
      && presentation.activeCall?.phase == .connected
      && !presentation.isSpeakerEnabled
    setProximityMonitoring(enabled)
  }

  private func setProximityMonitoring(_ enabled: Bool) {
    guard proximityMonitoringEnabled != enabled else { return }
    proximityMonitoringEnabled = enabled
    UIDevice.current.isProximityMonitoringEnabled = enabled
    presentation.setProximityCovered(enabled && UIDevice.current.proximityState)
  }

  private func updateAudioRoute(using session: AVAudioSession) {
    let output = session.currentRoute.outputs.first
    let speaker = output?.portType == .builtInSpeaker
    let label: String = switch output?.portType {
    case .builtInSpeaker:
      "Reproduktor"
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
      output?.portName ?? "Bluetooth"
    case .headphones, .headsetMic:
      "Sluchátka"
    default:
      "Telefon"
    }
    presentation.setRoute(label: label, speaker: speaker)
    updateProximityPolicy()
  }

  private func callKitEndReason(_ phase: CSMVoiceCallPhase) -> CXCallEndedReason {
    switch phase {
    case .missed:
      .unanswered
    case .declined:
      .declinedElsewhere
    case .failed:
      .failed
    default:
      .remoteEnded
    }
  }

  private func replacingPhase(
    _ call: CSMVoiceCall,
    phase: CSMVoiceCallPhase,
    connectedAt: Date?
  ) -> CSMVoiceCall {
    CSMVoiceCall(
      acceptedByEndpointId: call.acceptedByEndpointId,
      peer: call.peer,
      callId: call.callId,
      connectedAt: connectedAt,
      createdAt: call.createdAt,
      direction: call.direction,
      endedAt: phase.isTerminal ? Date() : nil,
      endReason: call.endReason,
      expiresAt: call.expiresAt,
      initiatorSubjectId: call.initiatorSubjectId,
      kind: call.kind,
      participantSubjectIds: call.participantSubjectIds,
      phase: phase,
      revision: call.revision,
      roomId: call.roomId,
      title: call.title,
      updatedAt: Date()
    )
  }

  private func replacingTitle(_ call: CSMVoiceCall, title: String) -> CSMVoiceCall {
    CSMVoiceCall(
      acceptedByEndpointId: call.acceptedByEndpointId,
      peer: call.peer,
      callId: call.callId,
      connectedAt: call.connectedAt,
      createdAt: call.createdAt,
      direction: call.direction,
      endedAt: call.endedAt,
      endReason: call.endReason,
      expiresAt: call.expiresAt,
      initiatorSubjectId: call.initiatorSubjectId,
      kind: call.kind,
      participantSubjectIds: call.participantSubjectIds,
      phase: call.phase,
      revision: call.revision,
      roomId: call.roomId,
      title: title,
      updatedAt: call.updatedAt
    )
  }

}
