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

private enum VoiceCallPushTokenStore {
  private static let account = "pushkit.voip"
  private static let service = "cz.zeleznalady.csm.messenger.push-tokens"

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
  case ended = "chat.voice_call.ended"
  case incoming = "chat.voice_call.incoming"
}

struct VoiceCallPushPayload: Equatable, Sendable {
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

private final class CallCompletionBox: @unchecked Sendable {
  let completion: () -> Void

  init(_ completion: @escaping () -> Void) {
    self.completion = completion
  }
}

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
final class VoiceCallService:
  NSObject, @preconcurrency CXProviderDelegate, @preconcurrency PKPushRegistryDelegate
{
  static let shared = VoiceCallService()

  private struct CallContext {
    var call: CSMVoiceCall
    var registeredWithCallKit: Bool
    var answered: Bool
    var muted: Bool
    var participants: [VoiceCallParticipant]
  }

  let presentation = VoiceCallPresentationState()

  private let provider: CXProvider
  private let callController = CXCallController()
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm.messenger",
    category: "native-voice-call"
  )
  private var registry: PKPushRegistry!
  private var calls: [UUID: CallContext] = [:]
  private var activeRoom: Room?
  private var activeRoomCallUUID: UUID?
  private var audioActivated = false
  private var roomConnected = false
  private var microphonePublished = false
  private var statePollingTask: Task<Void, Never>?
  private var connectionTimeoutTask: Task<Void, Never>?
  private var pushTokenState: VoiceCallPushTokenState
  private var tokenContinuation: CheckedContinuation<String, any Error>?
  private var tokenTimeoutTask: Task<Void, Never>?
  private var tokenRegistrationRecoveryTask: Task<Void, Never>?
  private var tokenRegistrationRecoveryAttempted = false
  private var proximityMonitoringEnabled = false
  private var foregroundReconciliationTask: Task<Void, Never>?

  private lazy var roomObserver = LiveKitCallObserver { [weak self] event in
    Task { @MainActor in
      self?.handleLiveKitEvent(event)
    }
  }

  private override init() {
    let configuration = CXProviderConfiguration()
    configuration.includesCallsInRecents = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.supportsVideo = false
    pushTokenState = VoiceCallPushTokenState(
      cachedToken: VoiceCallPushTokenStore.load()
    )
    provider = CXProvider(configuration: configuration)
    super.init()

    AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
    try? AudioManager.shared.setEngineAvailability(.none)

    provider.setDelegate(self, queue: .main)
    registry = PKPushRegistry(queue: .main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
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
    CallDiagnosticStore.record("voice.native.initialized")
    if pushTokenState.cachedToken != nil {
      CallDiagnosticStore.record("pushkit.token.cached-awaiting-confirmation")
    }
  }

  func prepareForApplicationLaunch() {
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    synchronizeCurrentPushToken()
    recoverPushRegistrationIfNeeded()
    CallDiagnosticStore.record("voice.native.launch-prepared")
  }

  func currentPushToken() async throws -> String {
    synchronizeCurrentPushToken()
    if let pushToken = pushTokenState.tokenForServerRegistration {
      return pushToken
    }
    guard tokenContinuation == nil else {
      throw PushRegistrationError.registrationPending
    }
    return try await withCheckedThrowingContinuation { continuation in
      tokenContinuation = continuation
      tokenTimeoutTask?.cancel()
      tokenTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(12))
        guard !Task.isCancelled, let self, let continuation = self.tokenContinuation else {
          return
        }
        self.tokenContinuation = nil
        self.tokenTimeoutTask = nil
        continuation.resume(throwing: PushRegistrationError.registrationFailed)
      }
    }
  }

  func currentPushTokenIfAvailable() async -> String? {
    synchronizeCurrentPushToken()
    return pushTokenState.tokenForServerRegistration
  }

  func applicationDidBecomeActive() {
    synchronizeCurrentPushToken()
    recoverPushRegistrationIfNeeded()
    foregroundReconciliationTask?.cancel()
    foregroundReconciliationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled, let self else { return }
      self.synchronizeCurrentPushToken()
      await CSMCommunicationNotifications.prepareDeviceRegistration(
        voipDeviceTokenProvider: self.currentPushTokenIfAvailable
      )
      guard !Task.isCancelled else { return }
      await self.reconcileActiveIncomingCalls()
    }
  }

  func startVoiceCall(
    roomID: String,
    title: String,
    participantSubjectIDs: [String]?,
    registerWithSystemCallUI: Bool = true
  ) {
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
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        guard await AVAudioApplication.requestRecordPermission() else {
          throw CSMVoiceCallControlError.mediaUnavailable
        }
        let session = try await CSMCommunicationRuntime.shared.startVoiceCall(
          roomID: normalizedRoomID,
          title: normalizedTitle,
          participantSubjectIDs: participantSubjectIDs
        )
        try self.install(
          session: session,
          title: normalizedTitle,
          registeredWithCallKit: false,
          answered: false
        )
        guard let uuid = UUID(uuidString: session.call.callId) else {
          throw CSMVoiceCallControlError.mediaUnavailable
        }
        if registerWithSystemCallUI {
          self.requestStartCall(uuid: uuid, title: normalizedTitle)
        } else {
          await self.connectMedia(session: session, uuid: uuid)
        }
      } catch {
        self.failVisibleCall(error)
      }
    }
  }

  func answerActiveCall() {
    guard let call = presentation.activeCall, call.direction == .incoming else { return }
    requestCallKitAction(CXAnswerCallAction(call: call.id))
  }

  func endActiveCall() {
    guard let call = presentation.activeCall else { return }
    requestCallKitAction(CXEndCallAction(call: call.id))
  }

  func toggleMute() {
    guard let call = presentation.activeCall else { return }
    requestCallKitAction(
      CXSetMutedCallAction(call: call.id, muted: !presentation.isMuted)
    )
  }

  func toggleSpeaker() {
    guard presentation.activeCall != nil else { return }
    do {
      let session = AVAudioSession.sharedInstance()
      let enableSpeaker = !presentation.isSpeakerEnabled
      try session.overrideOutputAudioPort(enableSpeaker ? .speaker : .none)
      updateAudioRoute(using: session)
    } catch {
      logger.error("Audio route change failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    acceptPushToken(token, source: "callback")
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    pushTokenState.invalidate()
    VoiceCallPushTokenStore.remove()
    tokenTimeoutTask?.cancel()
    tokenTimeoutTask = nil
    tokenContinuation?.resume(throwing: PushRegistrationError.registrationFailed)
    tokenContinuation = nil
    CSMCommunicationNotifications.recordVoIPDeviceTokenUpdate()
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    receive(payload: payload.dictionaryPayload, completion: completion)
  }

  private func receive(payload: [AnyHashable: Any], completion: @escaping () -> Void) {
    CallDiagnosticStore.record("pushkit.incoming.received")
    guard let push = VoiceCallPushPayload(dictionary: payload) else {
      CallDiagnosticStore.record("pushkit.rejected", result: "invalid-payload")
      completion()
      return
    }

    if calls[push.uuid] != nil {
      CallDiagnosticStore.record("pushkit.duplicate.ignored")
      completion()
      return
    }

    if push.event == .ended {
      CallDiagnosticStore.record("pushkit.call.ended")
      let hadLocalCall = calls[push.uuid] != nil
      provider.reportCall(
        with: push.uuid,
        endedAt: Date(),
        reason: .remoteEnded
      )
      tearDown(uuid: push.uuid, reportServer: false)
      if !hadLocalCall {
        notifyCallTimelineChanged(roomID: push.roomID)
      }
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
      call: call,
      registeredWithCallKit: true,
      answered: false,
      muted: false,
      participants: []
    )
    publish(push.uuid)
    startStatePolling(uuid: push.uuid)

    let update = CXCallUpdate()
    update.localizedCallerName = push.callerDisplayName
    update.remoteHandle = CXHandle(type: .generic, value: push.callerDisplayName)
    update.hasVideo = false
    let completionBox = CallCompletionBox(completion)
    Task { @MainActor [weak self] in
      defer { completionBox.completion() }
      guard let self else { return }
      do {
        try await provider.reportNewIncomingCall(with: push.uuid, update: update)
        CallDiagnosticStore.record(
          "callkit.incoming.reported",
          result: "success"
        )
      } catch {
        logger.error(
          "CallKit rejected incoming call: \(error.localizedDescription, privacy: .public)"
        )
        tearDown(uuid: push.uuid, reportServer: true, action: .decline)
        CallDiagnosticStore.record(
          "callkit.incoming.reported",
          result: "failed"
        )
      }
    }
  }

  private func synchronizeCurrentPushToken() {
    guard let data = registry.pushToken(for: .voIP) else { return }
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
    guard pushTokenState.needsRegistrationRecovery,
      !tokenRegistrationRecoveryAttempted
    else { return }
    tokenRegistrationRecoveryAttempted = true
    tokenRegistrationRecoveryTask?.cancel()
    tokenRegistrationRecoveryTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled, let self else { return }
      self.synchronizeCurrentPushToken()
      guard self.pushTokenState.needsRegistrationRecovery else { return }
      CallDiagnosticStore.record("pushkit.registration.recovery.started")
      self.registry.desiredPushTypes = []
      await Task.yield()
      self.registry.desiredPushTypes = [.voIP]
      try? await Task.sleep(for: .seconds(12))
      guard !Task.isCancelled else { return }
      self.synchronizeCurrentPushToken()
      if self.pushTokenState.needsRegistrationRecovery {
        CallDiagnosticStore.record("pushkit.registration.recovery.timed-out")
      }
      self.tokenRegistrationRecoveryTask = nil
    }
  }

  private func acceptPushToken(_ token: String, source: String) {
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

  private func reconcileActiveIncomingCalls() async {
    do {
      let activeCalls = try await CSMCommunicationRuntime.shared.activeVoiceCalls()
      for call in activeCalls where call.direction == .incoming && !call.phase.isTerminal {
        guard let uuid = UUID(uuidString: call.callId), calls[uuid] == nil else { continue }
        calls[uuid] = CallContext(
          call: call,
          registeredWithCallKit: true,
          answered: false,
          muted: false,
          participants: []
        )
        publish(uuid)
        startStatePolling(uuid: uuid)
        let update = CXCallUpdate()
        update.localizedCallerName = call.title
        update.remoteHandle = CXHandle(type: .generic, value: call.title)
        update.hasVideo = false
        do {
          try await provider.reportNewIncomingCall(with: uuid, update: update)
          CallDiagnosticStore.record(
            "callkit.incoming.reconciled",
            result: "success"
          )
        } catch {
          CallDiagnosticStore.record(
            "callkit.incoming.reconciled",
            result: "failed"
          )
          logger.error(
            "Reconciled incoming call was rejected: \(error.localizedDescription, privacy: .public)"
          )
          tearDown(uuid: uuid, reportServer: true, action: .decline)
        }
      }
    } catch {
      CallDiagnosticStore.record(
        "voice.active-reconciliation.failed",
        result: error.localizedDescription
      )
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    let active = Array(calls.keys)
    for uuid in active {
      tearDown(uuid: uuid, reportServer: true, action: .end)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard var context = calls[action.callUUID] else {
      action.fail()
      return
    }
    do {
      try configureAudioSession(action: "start")
      context.registeredWithCallKit = true
      calls[action.callUUID] = context
      action.fulfill()
      provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
      publish(action.callUUID)
      guard let session = mediaSession(for: context.call) else {
        throw CSMVoiceCallControlError.mediaUnavailable
      }
      Task { @MainActor [weak self] in
        await self?.connectMedia(session: session, uuid: action.callUUID)
      }
    } catch {
      action.fail()
      fail(uuid: action.callUUID, error: error)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard var context = calls[action.callUUID],
      context.call.direction == .incoming,
      !context.answered
    else {
      action.fail()
      return
    }
    do {
      try configureAudioSession(action: "answer")
      context.answered = true
      calls[action.callUUID] = context
      publish(action.callUUID)
      action.fulfill()
      Task { @MainActor [weak self] in
        await self?.acceptAndConnect(uuid: action.callUUID)
      }
    } catch {
      action.fail()
      fail(uuid: action.callUUID, error: error)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard var context = calls[action.callUUID] else {
      action.fail()
      return
    }
    context.muted = action.isMuted
    calls[action.callUUID] = context
    presentation.setMuted(action.isMuted)
    action.fulfill()
    Task { @MainActor [weak self] in
      guard let room = self?.activeRoom else { return }
      _ = try? await room.localParticipant.setMicrophone(enabled: !action.isMuted)
    }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let context = calls[action.callUUID] else {
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

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    action.fail()
    if let callAction = action as? CXCallAction {
      fail(
        uuid: callAction.callUUID,
        error: CSMVoiceCallControlError.mediaUnavailable
      )
    }
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    do {
      // CallKit has already activated this session. Mutating its category here
      // can synchronously block the main thread on iOS 27. The category is
      // prepared before fulfilling the start/answer action instead.
      try AudioManager.shared.setEngineAvailability(.default)
      audioActivated = true
      presentation.setAudioActive(true)
      updateAudioRoute(using: audioSession)
      updateProximityPolicy()
      Task { @MainActor [weak self] in
        await self?.publishMicrophoneIfReady()
      }
    } catch {
      if let uuid = activeRoomCallUUID {
        fail(uuid: uuid, error: error)
      }
    }
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    audioActivated = false
    presentation.setAudioActive(false)
    try? AudioManager.shared.setEngineAvailability(.none)
    updateProximityPolicy()
  }

  private func requestStartCall(uuid: UUID, title: String) {
    let handle = CXHandle(type: .generic, value: title)
    let action = CXStartCallAction(call: uuid, handle: handle)
    action.isVideo = false
    requestCallKitAction(action)
  }

  private func requestCallKitAction(_ action: CXAction) {
    callController.request(CXTransaction(action: action)) { [weak self] error in
      guard let error else { return }
      Task { @MainActor in
        self?.logger.error(
          "CallKit transaction failed: \(error.localizedDescription, privacy: .public)"
        )
        if let callAction = action as? CXCallAction {
          self?.fail(uuid: callAction.callUUID, error: error)
        }
      }
    }
  }

  private func install(
    session: CSMVoiceCallSession,
    title: String,
    registeredWithCallKit: Bool,
    answered: Bool
  ) throws {
    guard let uuid = UUID(uuidString: session.call.callId), calls[uuid] == nil else {
      throw CSMVoiceCallControlError.mediaUnavailable
    }
    let call = replacingTitle(session.call, title: title)
    calls[uuid] = CallContext(
      call: call,
      registeredWithCallKit: registeredWithCallKit,
      answered: answered,
      muted: false,
      participants: []
    )
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

  private func acceptAndConnect(uuid: UUID) async {
    guard let context = calls[uuid] else { return }
    do {
      guard await AVAudioApplication.requestRecordPermission() else {
        throw CSMVoiceCallControlError.mediaUnavailable
      }
      let accepted = try await CSMCommunicationRuntime.shared.transitionVoiceCall(
        callID: context.call.callId,
        action: .accept,
        expectedRevision: context.call.revision
      )
      apply(accepted, uuid: uuid)
      await connectMedia(session: accepted, uuid: uuid)
    } catch {
      fail(uuid: uuid, error: error)
    }
  }

  private func connectMedia(session: CSMVoiceCallSession, uuid: UUID) async {
    guard calls[uuid] != nil else { return }
    guard let media = session.media else {
      fail(uuid: uuid, error: CSMVoiceCallControlError.mediaUnavailable)
      return
    }
    cachedMedia[session.call.callId] = media
    activeRoomCallUUID = uuid
    roomConnected = false
    microphonePublished = false

    let room = Room(delegate: roomObserver)
    activeRoom = room
    scheduleConnectionTimeout(uuid: uuid)
    do {
      try await room.connect(url: media.serverUrl.absoluteString, token: media.token)
      guard activeRoomCallUUID == uuid, calls[uuid] != nil else {
        await room.disconnect()
        return
      }
      roomConnected = true
      await publishMicrophoneIfReady()
      if !room.remoteParticipants.isEmpty {
        markMediaConnected(uuid: uuid)
      }
    } catch {
      fail(uuid: uuid, error: error)
    }
  }

  private func publishMicrophoneIfReady() async {
    guard audioActivated, roomConnected, !microphonePublished,
      let uuid = activeRoomCallUUID,
      let context = calls[uuid],
      let room = activeRoom
    else { return }
    do {
      try await room.localParticipant.setMicrophone(enabled: !context.muted)
      microphonePublished = true
    } catch {
      fail(uuid: uuid, error: error)
    }
  }

  private func handleLiveKitEvent(_ event: LiveKitCallEvent) {
    guard let uuid = activeRoomCallUUID, var context = calls[uuid] else { return }
    switch event {
    case .connected:
      roomConnected = true
      Task { @MainActor [weak self] in
        await self?.publishMicrophoneIfReady()
      }
    case .participantConnected(let id, let name):
      context.participants.removeAll { $0.userID == id }
      context.participants.append(
        VoiceCallParticipant(userID: id, displayName: name, connected: true)
      )
      calls[uuid] = context
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

  private func markMediaConnected(uuid: UUID) {
    guard var context = calls[uuid], context.call.phase != .connected else { return }
    connectionTimeoutTask?.cancel()
    context.call = replacingPhase(context.call, phase: .connected, connectedAt: Date())
    calls[uuid] = context
    publish(uuid)
    if context.call.direction == .outgoing {
      provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }
    Task { @MainActor [weak self] in
      guard let self, let latest = self.calls[uuid] else { return }
      do {
        let session = try await CSMCommunicationRuntime.shared.transitionVoiceCall(
          callID: latest.call.callId,
          action: .mediaConnected,
          expectedRevision: latest.call.revision
        )
        self.apply(session, uuid: uuid)
      } catch {
        self.logger.notice(
          "Media-connected state will be reconciled by polling: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  private func startStatePolling(uuid: UUID) {
    statePollingTask?.cancel()
    statePollingTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled, let self, let context = self.calls[uuid] else { return }
        do {
          let session = try await CSMCommunicationRuntime.shared.voiceCall(
            callID: context.call.callId
          )
          self.apply(session, uuid: uuid)
          if session.call.phase.isTerminal { return }
        } catch {
          self.logger.debug(
            "Call state poll failed: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }

  private func apply(_ session: CSMVoiceCallSession, uuid: UUID) {
    guard var context = calls[uuid] else { return }
    context.call = session.call
    calls[uuid] = context
    if let media = session.media {
      cachedMedia[session.call.callId] = media
    }
    if session.call.phase.isTerminal {
      provider.reportCall(
        with: uuid,
        endedAt: session.call.endedAt ?? Date(),
        reason: callKitEndReason(session.call.phase)
      )
      tearDown(uuid: uuid, reportServer: false)
      return
    }
    publish(uuid)
    if (
      session.call.phase == .accepted || session.call.phase == .connectingMedia
    ),
      activeRoomCallUUID == uuid,
      activeRoom?.remoteParticipants.isEmpty == false
    {
      markMediaConnected(uuid: uuid)
    }
  }

  private func publish(_ uuid: UUID) {
    guard let context = calls[uuid] else { return }
    let phase: VoiceCallPhase = switch context.call.phase {
    case .created, .ringing:
      context.call.direction == .incoming && !context.answered ? .ringing : .connecting
    case .accepted, .connectingMedia:
      .connecting
    case .connected:
      .connected
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
        title: context.call.title,
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
    CallDiagnosticStore.record("voice.start.failed", result: error.localizedDescription)
    logger.error("Voice call start failed: \(error.localizedDescription, privacy: .public)")
    presentation.setError(
      (error as? LocalizedError)?.errorDescription
        ?? "Hovor se nepodařilo zahájit. Zkontrolujte připojení a zkuste to znovu."
    )
  }

  private func fail(uuid: UUID, error: Error) {
    CallDiagnosticStore.record("voice.call.failed", result: error.localizedDescription)
    guard let context = calls[uuid] else { return }
    var failed = context
    failed.call = replacingPhase(context.call, phase: .failed, connectedAt: nil)
    calls[uuid] = failed
    publish(uuid)
    provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
    Task { @MainActor [weak self] in
      _ = try? await CSMCommunicationRuntime.shared.transitionVoiceCall(
        callID: context.call.callId,
        action: .mediaFailed,
        expectedRevision: context.call.revision,
        reason: "native_media_failed"
      )
      try? await Task.sleep(for: .seconds(1))
      self?.tearDown(uuid: uuid, reportServer: false)
    }
  }

  private func tearDown(
    uuid: UUID,
    reportServer: Bool,
    action: CSMVoiceCallAction = .end
  ) {
    guard let context = calls.removeValue(forKey: uuid) else { return }
    statePollingTask?.cancel()
    statePollingTask = nil
    connectionTimeoutTask?.cancel()
    connectionTimeoutTask = nil
    cachedMedia.removeValue(forKey: context.call.callId)

    if activeRoomCallUUID == uuid {
      let room = activeRoom
      activeRoom = nil
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

    if reportServer {
      Task { @MainActor [weak self] in
        _ = try? await CSMCommunicationRuntime.shared.transitionVoiceCall(
          callID: context.call.callId,
          action: action,
          expectedRevision: context.call.revision,
          reason: nil
        )
        self?.notifyCallTimelineChanged(roomID: context.call.roomId)
      }
    } else {
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

  private func scheduleConnectionTimeout(uuid: UUID) {
    connectionTimeoutTask?.cancel()
    connectionTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(45))
      guard !Task.isCancelled, let self,
        self.calls[uuid]?.call.phase != .connected
      else { return }
      self.fail(uuid: uuid, error: CSMVoiceCallControlError.mediaUnavailable)
    }
  }

  private func configureAudioSession(action: String) throws {
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
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    CallDiagnosticStore.record("audio.configuration.prepared", result: action)
  }

  @objc private func proximityStateDidChange() {
    presentation.setProximityCovered(
      proximityMonitoringEnabled && UIDevice.current.proximityState
    )
  }

  @objc private func audioRouteDidChange() {
    updateAudioRoute(using: AVAudioSession.sharedInstance())
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
