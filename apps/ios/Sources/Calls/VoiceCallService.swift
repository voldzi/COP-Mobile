import AVFAudio
@preconcurrency import CallKit
import CryptoKit
import Foundation
import Observation
@preconcurrency import PushKit
import UIKit

extension Notification.Name {
  static let copWebMediaInvalidationRequired = Notification.Name(
    "cz.zeleznalady.cop.webMediaInvalidationRequired")
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

  var keepsPresentationVisible: Bool {
    self != .ended && self != .failed
  }
}

enum VoiceCallKind: String, Equatable, Sendable {
  case direct
  case group
}

struct VoiceCallParticipant: Equatable, Identifiable, Sendable {
  let userID: String
  let displayName: String
  let connected: Bool

  var id: String { userID }
}

private enum VoiceCallOwnership {
  case pushAwaitingWebMedia
  case webMedia
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

  fileprivate func clear() {
    activeCall = nil
    isAudioActive = false
    isMuted = false
    isProximityCovered = false
    isSpeakerEnabled = false
    routeLabel = "Telefon"
  }
}

private enum AudioSessionTransitionError: LocalizedError {
  case activationRejected
  case deactivationRejected

  var errorDescription: String? {
    switch self {
    case .activationRejected:
      "Audio session activation was rejected."
    case .deactivationRejected:
      "Audio session deactivation was rejected."
    }
  }
}

private actor AudioSessionActivationCoordinator {
  private var transitionInProgress = false
  private var transitionWaiters: [CheckedContinuation<Void, Never>] = []

  func activate() async throws {
    await acquireTransition()
    defer { releaseTransition() }

    if #available(iOS 27.0, *) {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        AVAudioSession.sharedInstance().activate(options: []) { activated, error in
          if let error {
            continuation.resume(throwing: error)
          } else if activated {
            continuation.resume()
          } else {
            continuation.resume(throwing: AudioSessionTransitionError.activationRejected)
          }
        }
      }
    } else {
      try await Task.detached(priority: .userInitiated) {
        try AVAudioSession.sharedInstance().setActive(true)
      }.value
    }
  }

  func deactivate() async {
    await acquireTransition()
    defer { releaseTransition() }

    if #available(iOS 27.0, *) {
      try? await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        AVAudioSession.sharedInstance().deactivate(
          options: [.notifyOthersOnDeactivation]
        ) { deactivated, error in
          if let error {
            continuation.resume(throwing: error)
          } else if deactivated {
            continuation.resume()
          } else {
            continuation.resume(throwing: AudioSessionTransitionError.deactivationRejected)
          }
        }
      }
    } else {
      try? await Task.detached(priority: .utility) {
        try AVAudioSession.sharedInstance().setActive(
          false,
          options: .notifyOthersOnDeactivation
        )
      }.value
    }
  }

  private func acquireTransition() async {
    guard transitionInProgress else {
      transitionInProgress = true
      return
    }

    await withCheckedContinuation { continuation in
      transitionWaiters.append(continuation)
    }
  }

  private func releaseTransition() {
    guard !transitionWaiters.isEmpty else {
      transitionInProgress = false
      return
    }

    transitionWaiters.removeFirst().resume()
  }
}

@MainActor
final class VoiceCallService:
  NSObject, @preconcurrency CXProviderDelegate, @preconcurrency PKPushRegistryDelegate
{
  static let shared = VoiceCallService()
  private static let actionRetryInterval = Duration.seconds(1)
  private static let callKitClaimPollCount = 100
  private static let callKitAudioActivationPollCount = 200
  private static let callKitPollInterval = Duration.milliseconds(50)

  private enum ReliableActionKind {
    case answer
    case end
    case mute
    case addParticipants
    case reject
    case resetEnd

    var eventType: String {
      switch self {
      case .answer: "calls.answerRequested"
      case .end, .resetEnd: "calls.endRequested"
      case .mute: "calls.muteRequested"
      case .addParticipants: "calls.addParticipantsRequested"
      case .reject: "calls.rejectRequested"
      }
    }

    var acknowledgementTimeout: TimeInterval {
      // A cold start on an older device can need materially longer to restore
      // the persistent WKWebView Matrix session. The CallKit answer action is
      // fulfilled before this bridge operation, so the longer bounded timeout
      // does not hold the system CallKit transaction open.
      switch self {
      case .answer:
        35
      default:
        12
      }
    }
  }

  private struct PendingCallAction {
    let actionID: String
    let callID: String
    let roomID: String
    let callUUID: UUID
    let deadline: Date
    let kind: ReliableActionKind
    let callKitAction: CXAction?
    let muted: Bool?
    let participantUserIDs: [String]?
  }

  private struct CallContext {
    let callID: String
    let roomID: String
    var title: String
    var direction: VoiceCallDirection
    var eligibleParticipants: [VoiceCallParticipant]
    var kind: VoiceCallKind
    var participants: [VoiceCallParticipant]
    var phase: VoiceCallPhase
    var answered: Bool
    var muted: Bool
    var connectedAt: Date?
    var registeredWithCallKit: Bool
    var ownership: VoiceCallOwnership
  }

  private final class CompletionBox: @unchecked Sendable {
    let completion: () -> Void

    init(_ completion: @escaping () -> Void) {
      self.completion = completion
    }
  }

  let presentation = VoiceCallPresentationState()

  private let provider: CXProvider
  private let callController = CXCallController()
  private var registry: PKPushRegistry!
  private var calls: [UUID: CallContext] = [:]
  private var pendingCallActions: [String: PendingCallAction] = [:]
  private var pendingCallActionTasks: [String: Task<Void, Never>] = [:]
  private var pushToken: String?
  private var tokenContinuation: CheckedContinuation<String, any Error>?
  private var proximityMonitoringEnabled = false
  private let audioSessionActivationCoordinator = AudioSessionActivationCoordinator()
  var eventReceiver: ((String, [String: Any]) -> Void)?

  private override init() {
    let configuration = CXProviderConfiguration()
    configuration.includesCallsInRecents = false
    configuration.maximumCallGroups = 1
    configuration.maximumCallsPerCallGroup = 1
    configuration.supportedHandleTypes = [.generic]
    configuration.supportsVideo = false
    provider = CXProvider(configuration: configuration)
    super.init()
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
  }

  func currentPushToken() async throws -> String {
    if let pushToken { return pushToken }
    guard tokenContinuation == nil else { throw PushRegistrationError.registrationPending }
    return try await withCheckedThrowingContinuation { continuation in
      tokenContinuation = continuation
    }
  }

  /// Used by foreground WebKit media capture. CallKit-owned calls only configure
  /// the session here and wait for `provider(_:didActivate:)` before using it.
  func prepareForegroundAudio() async throws {
    let session = AVAudioSession.sharedInstance()
    try configureAudioSession(session)
    if await waitForCallKitOwnership() {
      guard await waitForCallKitAudioActivation() else {
        throw AudioSessionTransitionError.activationRejected
      }
      updateAudioRoute(using: session)
      return
    }
    try await audioSessionActivationCoordinator.activate()
    updateAudioRoute(using: session)
  }

  private func waitForCallKitOwnership() async -> Bool {
    for _ in 0..<Self.callKitClaimPollCount {
      if calls.values.contains(where: {
        $0.registeredWithCallKit && $0.phase.keepsPresentationVisible
      }) {
        return true
      }
      try? await Task.sleep(for: Self.callKitPollInterval)
    }
    return false
  }

  private func waitForCallKitAudioActivation() async -> Bool {
    for _ in 0..<Self.callKitAudioActivationPollCount {
      if presentation.isAudioActive {
        return true
      }
      try? await Task.sleep(for: Self.callKitPollInterval)
    }
    return false
  }

  func requestMicrophoneAndPrepare(_ completion: @escaping @MainActor (Bool) -> Void) {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      Task { @MainActor in
        completion((try? await prepareForegroundAudio()) != nil)
      }
    case .denied:
      completion(false)
    case .undetermined:
      AVAudioApplication.requestRecordPermission { granted in
        Task { @MainActor in
          guard granted else {
            completion(false)
            return
          }
          completion((try? await self.prepareForegroundAudio()) != nil)
        }
      }
    @unknown default:
      completion(false)
    }
  }

  /// Mirrors the call snapshot owned by the current web Matrix engine into the
  /// native CallKit and SwiftUI presentation layer. This is intentionally a
  /// narrow compatibility seam until the media engine becomes native-owned.
  @discardableResult
  func updateFromWeb(
    callID: String,
    roomID: String,
    title: String?,
    direction: String,
    phase: String
  ) -> Bool {
    updateFromWeb(
      callId: callID,
      roomId: roomID,
      title: title ?? "COP kontakt",
      direction: direction,
      phase: phase,
      kind: .direct,
      participants: [],
      eligibleParticipants: []
    )
  }

  @discardableResult
  func updateFromWeb(
    callId: String,
    roomId: String,
    title: String,
    direction: String,
    phase: String,
    kind: VoiceCallKind = .direct,
    participants: [VoiceCallParticipant] = [],
    eligibleParticipants: [VoiceCallParticipant] = []
  ) -> Bool {
    guard let normalizedCallID = boundedString(callId),
      let normalizedRoomID = boundedString(roomId),
      let parsedDirection = VoiceCallDirection(rawValue: direction),
      let parsedPhase = VoiceCallPhase(rawValue: phase)
    else { return false }

    let normalizedTitle = boundedString(title) ?? "COP kontakt"
    let uuid = callUUID(callID: normalizedCallID, roomID: normalizedRoomID)
    if let activeCall = presentation.activeCall,
      activeCall.id != uuid,
      parsedPhase.keepsPresentationVisible
    {
      return false
    }
    if let existing = calls[uuid] {
      guard existing.direction == parsedDirection,
        Self.allowsTransition(from: existing.phase, to: parsedPhase)
      else { return false }
    } else {
      guard Self.allowsInitialPhase(parsedPhase, direction: parsedDirection) else { return false }
    }
    var call =
      calls[uuid]
      ?? CallContext(
        callID: normalizedCallID,
        roomID: normalizedRoomID,
        title: normalizedTitle,
        direction: parsedDirection,
        eligibleParticipants: eligibleParticipants,
        kind: kind,
        participants: participants,
        phase: parsedPhase,
        answered: parsedPhase == .connected,
        muted: false,
        connectedAt: parsedPhase == .connected ? Date() : nil,
        registeredWithCallKit: false,
        ownership: .webMedia
      )
    call.title = normalizedTitle
    call.direction = parsedDirection
    call.eligibleParticipants = eligibleParticipants
    call.kind = kind
    call.participants = participants
    call.phase = parsedPhase
    call.ownership = .webMedia
    if parsedPhase == .connected {
      call.answered = true
      call.connectedAt = call.connectedAt ?? Date()
    }
    calls[uuid] = call

    if !call.registeredWithCallKit, parsedPhase.keepsPresentationVisible {
      registerWithCallKit(uuid: uuid, call: call)
      call.registeredWithCallKit = true
      calls[uuid] = call
    }

    switch parsedPhase {
    case .connecting where parsedDirection == .outgoing:
      provider.reportOutgoingCall(with: uuid, startedConnectingAt: Date())
    case .connected where parsedDirection == .outgoing:
      provider.reportOutgoingCall(with: uuid, connectedAt: call.connectedAt)
    case .ended:
      provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      removeCall(uuid)
      deactivateAudioSession()
      return true
    case .failed:
      provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
      removeCall(uuid)
      deactivateAudioSession()
      return true
    default:
      break
    }

    publish(uuid)
    return true
  }

  func webMediaEngineDidBecomeUnavailable() {
    guard let call = presentation.activeCall,
      calls[call.id]?.ownership == .webMedia
    else { return }
    provider.reportCall(with: call.id, endedAt: Date(), reason: .failed)
    removeCall(call.id)
    deactivateAudioSession()
  }

  @discardableResult
  func acknowledgeAction(
    actionID: String,
    callID: String,
    roomID: String,
    outcome: String
  ) -> Bool {
    guard UUID(uuidString: actionID) != nil,
      let pending = pendingCallActions[actionID.lowercased()],
      pending.callID == callID,
      pending.roomID == roomID,
      outcome == "succeeded" || outcome == "failed"
    else { return false }

    let normalizedActionID = actionID.lowercased()
    guard outcome == "succeeded" else {
      resolveFailedAction(actionID: normalizedActionID, pending: pending)
      return true
    }
    pendingCallActionTasks.removeValue(forKey: normalizedActionID)?.cancel()
    pendingCallActions.removeValue(forKey: normalizedActionID)

    switch pending.kind {
    case .answer:
      if var call = calls[pending.callUUID], call.phase.keepsPresentationVisible {
        call.answered = true
        if call.phase == .ringing {
          call.phase = .connecting
        }
        calls[pending.callUUID] = call
        publish(pending.callUUID)
      }
    case .mute:
      if var call = calls[pending.callUUID], let muted = pending.muted {
        call.muted = muted
        calls[pending.callUUID] = call
        presentation.setMuted(muted)
      }
    case .addParticipants:
      break
    case .end, .reject:
      removeCall(pending.callUUID)
    case .resetEnd:
      break
    }
    pending.callKitAction?.fulfill()
    return true
  }

  func answerActiveCall() {
    guard let call = presentation.activeCall,
      call.direction == .incoming,
      call.phase == .ringing
    else { return }
    requestCallKitAction(CXAnswerCallAction(call: call.id))
  }

  func endActiveCall() {
    guard let call = presentation.activeCall else { return }
    requestCallKitAction(CXEndCallAction(call: call.id))
  }

  func toggleMute() {
    guard let call = presentation.activeCall else { return }
    requestCallKitAction(CXSetMutedCallAction(call: call.id, muted: !presentation.isMuted))
  }

  func toggleSpeaker() {
    guard presentation.activeCall != nil else { return }
    let session = AVAudioSession.sharedInstance()
    let enableSpeaker = !presentation.isSpeakerEnabled
    do {
      try configureAudioSession(session)
      try session.overrideOutputAudioPort(enableSpeaker ? .speaker : .none)
      updateAudioRoute(using: session)
    } catch {
      updateAudioRoute(using: session)
    }
  }

  func addParticipants(_ participantUserIDs: [String]) {
    guard let call = presentation.activeCall,
      call.kind == .group,
      call.phase == .connected,
      let context = calls[call.id]
    else { return }
    let eligible = Set(context.eligibleParticipants.map(\.userID))
    let selected = Array(Set(participantUserIDs)).filter(eligible.contains).prefix(5)
    guard !selected.isEmpty else { return }
    queueReliableAction(
      kind: .addParticipants,
      uuid: call.id,
      call: context,
      callKitAction: nil,
      participantUserIDs: Array(selected)
    )
  }

  func startVoiceCall(roomID: String, title: String, isGroup: Bool) {
    guard presentation.activeCall == nil,
      let roomID = boundedString(roomID),
      let title = boundedString(title)
    else { return }
    eventReceiver?(
      "calls.startRequested",
      [
        "actionId": UUID().uuidString.lowercased(),
        "callId": "start-\(UUID().uuidString.lowercased())",
        "kind": isGroup ? "group" : "direct",
        "roomId": roomID,
        "title": title,
      ]
    )
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    pushToken = token
    tokenContinuation?.resume(returning: token)
    tokenContinuation = nil
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    pushToken = nil
    tokenContinuation?.resume(throwing: PushRegistrationError.registrationFailed)
    tokenContinuation = nil
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
    guard let type = boundedString(payload["type"]),
      let callID = boundedString(payload["callId"]),
      let roomID = boundedString(payload["roomId"])
    else {
      completion()
      return
    }
    let uuid = callUUID(callID: callID, roomID: roomID)
    if type == "chat.voice_call.ended" {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      removeCall(uuid)
      completion()
      return
    }
    guard type == "chat.voice_call.incoming" else {
      completion()
      return
    }

    let caller = boundedString(payload["senderDisplayName"]) ?? "COP kontakt"
    if calls[uuid] != nil {
      completion()
      return
    }
    let call = CallContext(
      callID: callID,
      roomID: roomID,
      title: caller,
      direction: .incoming,
      eligibleParticipants: [],
      kind: .direct,
      participants: [],
      phase: .ringing,
      answered: false,
      muted: false,
      connectedAt: nil,
      registeredWithCallKit: true,
      ownership: .pushAwaitingWebMedia
    )
    if let activeCall = presentation.activeCall, activeCall.id != uuid {
      reportConcurrentIncomingCall(uuid: uuid, call: call, completion: completion)
      return
    }
    calls[uuid] = call
    publish(uuid)
    reportIncomingCall(uuid: uuid, call: call, completion: completion)
  }

  func providerDidReset(_ provider: CXProvider) {
    let webOwnedCalls = calls.compactMap { uuid, call in
      call.ownership == .webMedia ? (uuid, call) : nil
    }
    resolveAllPendingActionsAfterForcedClose()
    for (uuid, call) in webOwnedCalls {
      queueReliableAction(kind: .resetEnd, uuid: uuid, call: call, callKitAction: nil)
    }
    if !webOwnedCalls.isEmpty {
      requestWebMediaInvalidation()
    }
    calls.removeAll()
    setProximityMonitoring(false)
    presentation.clear()
    deactivateAudioSession()
  }

  func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
    guard var call = calls[action.callUUID] else {
      action.fail()
      return
    }
    do {
      try configureAudioSession(AVAudioSession.sharedInstance())
      let shouldReportConnecting = call.phase != .connected
      if call.phase == .ringing {
        call.phase = .connecting
      }
      call.registeredWithCallKit = true
      calls[action.callUUID] = call
      publish(action.callUUID)
      action.fulfill()
      if shouldReportConnecting {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
      }
    } catch {
      removeCall(action.callUUID)
      action.fail()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard var call = calls[action.callUUID], call.direction == .incoming, call.phase == .ringing
    else {
      action.fail()
      return
    }
    do {
      try configureAudioSession(AVAudioSession.sharedInstance())
      // CallKit must own and activate AVAudioSession before WKWebView asks for
      // getUserMedia. Holding CXAnswerCallAction until the Matrix ACK creates a
      // cycle: WebRTC waits for audio, while CallKit waits for WebRTC. Fulfil
      // the system action now, then keep the Matrix answer independently
      // fail-closed through the reliable bridge command.
      call.answered = true
      call.phase = .connecting
      calls[action.callUUID] = call
      publish(action.callUUID)
      action.fulfill()
      queueReliableAction(kind: .answer, uuid: action.callUUID, call: call, callKitAction: nil)
    } catch {
      action.fail()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fail()
      return
    }
    queueReliableAction(
      kind: .mute,
      uuid: action.callUUID,
      call: call,
      callKitAction: action,
      muted: action.isMuted
    )
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = calls[action.callUUID] else {
      action.fulfill()
      return
    }
    let isUnansweredIncoming =
      call.direction == .incoming && !call.answered && call.phase == .ringing
    queueReliableAction(
      kind: isUnansweredIncoming ? .reject : .end,
      uuid: action.callUUID,
      call: call,
      callKitAction: action
    )
  }

  func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
    if let entry = pendingCallActions.first(where: { $0.value.callKitAction === action }) {
      resolveFailedAction(actionID: entry.key, pending: entry.value)
      return
    }
    action.fail()
    guard let callAction = action as? CXCallAction, calls[callAction.callUUID] != nil else {
      return
    }
    requestWebMediaInvalidation()
    provider.reportCall(with: callAction.callUUID, endedAt: Date(), reason: .failed)
    removeCall(callAction.callUUID)
    deactivateAudioSession()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    presentation.setAudioActive(true)
    updateAudioRoute(using: audioSession)
    updateProximityPolicy()
  }

  func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
    presentation.setAudioActive(false)
    setProximityMonitoring(false)
    try? audioSession.overrideOutputAudioPort(.none)
    updateAudioRoute(using: audioSession)
  }

  private func registerWithCallKit(uuid: UUID, call: CallContext) {
    switch call.direction {
    case .incoming:
      reportIncomingCall(uuid: uuid, call: call, completion: {})
    case .outgoing:
      let handle = CXHandle(type: .generic, value: call.title)
      let action = CXStartCallAction(call: uuid, handle: handle)
      action.isVideo = false
      requestCallKitAction(action)
    }
  }

  private func reportIncomingCall(uuid: UUID, call: CallContext, completion: @escaping () -> Void) {
    let update = incomingCallUpdate(call)
    let completionBox = CompletionBox(completion)
    provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
      if error != nil {
        Task { @MainActor in
          self?.removeCall(uuid)
        }
      }
      completionBox.completion()
    }
  }

  private func reportConcurrentIncomingCall(
    uuid: UUID,
    call: CallContext,
    completion: @escaping () -> Void
  ) {
    let completionBox = CompletionBox(completion)
    provider.reportNewIncomingCall(with: uuid, update: incomingCallUpdate(call)) {
      [weak self] error in
      Task { @MainActor in
        if error == nil {
          self?.provider.reportCall(with: uuid, endedAt: Date(), reason: .unanswered)
        }
        completionBox.completion()
      }
    }
  }

  private func incomingCallUpdate(_ call: CallContext) -> CXCallUpdate {
    let update = CXCallUpdate()
    update.hasVideo = false
    update.localizedCallerName = call.title
    update.remoteHandle = CXHandle(type: .generic, value: call.title)
    update.supportsDTMF = false
    update.supportsGrouping = false
    update.supportsHolding = false
    update.supportsUngrouping = false
    return update
  }

  private func requestCallKitAction(_ action: CXAction) {
    let callUUID = (action as? CXCallAction)?.callUUID
    callController.request(CXTransaction(action: action)) { [weak self] error in
      guard error != nil else { return }
      Task { @MainActor in
        action.fail()
        if action is CXStartCallAction, let callUUID {
          self?.removeCall(callUUID)
        }
      }
    }
  }

  private func configureAudioSession(_ session: AVAudioSession) throws {
    try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetoothHFP])
    if !presentation.isSpeakerEnabled {
      try session.overrideOutputAudioPort(.none)
    }
  }

  private func publish(_ uuid: UUID) {
    guard let call = calls[uuid], call.phase.keepsPresentationVisible else {
      if presentation.activeCall?.id == uuid {
        presentation.clear()
      }
      updateProximityPolicy()
      return
    }
    presentation.present(
      VoiceCallPresentation(
        id: uuid,
        callID: call.callID,
        roomID: call.roomID,
        title: call.title,
        direction: call.direction,
        eligibleParticipants: call.eligibleParticipants,
        kind: call.kind,
        participants: call.participants,
        phase: call.phase,
        connectedAt: call.connectedAt
      ),
      muted: call.muted
    )
    updateAudioRoute(using: AVAudioSession.sharedInstance())
    updateProximityPolicy()
  }

  private func removeCall(_ uuid: UUID) {
    resolvePendingActionsForRemovedCall(uuid)
    calls.removeValue(forKey: uuid)
    if presentation.activeCall?.id == uuid {
      setProximityMonitoring(false)
      presentation.clear()
    }
  }

  private func resolvePendingActionsForRemovedCall(_ uuid: UUID) {
    let matching = pendingCallActions.filter { $0.value.callUUID == uuid }
    for (actionID, pending) in matching {
      pendingCallActionTasks.removeValue(forKey: actionID)?.cancel()
      pendingCallActions.removeValue(forKey: actionID)
      switch pending.kind {
      case .end, .reject, .resetEnd:
        pending.callKitAction?.fulfill()
      case .addParticipants:
        break
      case .answer, .mute:
        pending.callKitAction?.fail()
      }
    }
  }

  private func requestWebMediaInvalidation() {
    NotificationCenter.default.post(name: .copWebMediaInvalidationRequired, object: nil)
  }

  private func deactivateAudioSession() {
    presentation.setAudioActive(false)
    setProximityMonitoring(false)
    let session = AVAudioSession.sharedInstance()
    try? session.overrideOutputAudioPort(.none)
    Task { @MainActor [weak self] in
      guard let self else { return }
      await audioSessionActivationCoordinator.deactivate()
      updateAudioRoute(using: AVAudioSession.sharedInstance())
    }
  }

  private func queueReliableAction(
    kind: ReliableActionKind,
    uuid: UUID,
    call: CallContext,
    callKitAction: CXAction?,
    muted: Bool? = nil,
    participantUserIDs: [String]? = nil
  ) {
    if pendingCallActions.values.contains(where: {
      $0.callUUID == uuid && $0.kind.eventType == kind.eventType
        && ($0.callKitAction != nil || kind == .addParticipants)
    }) {
      callKitAction?.fail()
      return
    }
    let actionID = UUID().uuidString.lowercased()
    let pending = PendingCallAction(
      actionID: actionID,
      callID: call.callID,
      roomID: call.roomID,
      callUUID: uuid,
      deadline: Date().addingTimeInterval(kind.acknowledgementTimeout),
      kind: kind,
      callKitAction: callKitAction,
      muted: muted,
      participantUserIDs: participantUserIDs
    )
    pendingCallActions[actionID] = pending
    emit(pending)
    pendingCallActionTasks[actionID] = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: Self.actionRetryInterval)
        guard !Task.isCancelled, let self else { return }
        guard let current = self.pendingCallActions[actionID] else { return }
        if Date() >= current.deadline {
          self.resolveFailedAction(actionID: actionID, pending: current)
          return
        }
        self.emit(current)
      }
    }
  }

  private func resolveAllPendingActionsAfterForcedClose() {
    let actions = pendingCallActions.values
    pendingCallActions.removeAll()
    let tasks = pendingCallActionTasks.values
    pendingCallActionTasks.removeAll()
    for task in tasks { task.cancel() }
    for pending in actions {
      switch pending.kind {
      case .end, .reject, .resetEnd:
        pending.callKitAction?.fulfill()
      case .addParticipants:
        break
      case .answer, .mute:
        pending.callKitAction?.fail()
      }
    }
  }

  private func resolveFailedAction(actionID: String, pending: PendingCallAction) {
    pendingCallActionTasks.removeValue(forKey: actionID)?.cancel()
    pendingCallActions.removeValue(forKey: actionID)
    if pending.kind == .addParticipants {
      return
    }
    requestWebMediaInvalidation()
    if calls[pending.callUUID] != nil {
      provider.reportCall(with: pending.callUUID, endedAt: Date(), reason: .failed)
    }
    removeCall(pending.callUUID)
    deactivateAudioSession()
    switch pending.kind {
    case .end, .reject, .resetEnd:
      pending.callKitAction?.fulfill()
    case .addParticipants:
      break
    case .answer, .mute:
      pending.callKitAction?.fail()
    }
  }

  private func emit(_ pending: PendingCallAction) {
    var payload: [String: Any] = [
      "actionId": pending.actionID,
      "callId": pending.callID,
      "roomId": pending.roomID,
    ]
    if let muted = pending.muted {
      payload["muted"] = muted
    }
    if let participantUserIDs = pending.participantUserIDs {
      payload["participantUserIds"] = participantUserIDs
    }
    eventReceiver?(
      pending.kind.eventType,
      payload
    )
  }

  private func boundedString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.count > 512 ? nil : trimmed
  }

  private static func allowsTransition(from current: VoiceCallPhase, to next: VoiceCallPhase)
    -> Bool
  {
    if current == next { return true }
    switch current {
    case .ringing:
      return [.connecting, .connected, .ended, .failed].contains(next)
    case .connecting:
      return [.connected, .ended, .failed].contains(next)
    case .connected:
      return [.ended, .failed].contains(next)
    case .ended, .failed:
      return false
    }
  }

  private static func allowsInitialPhase(
    _ phase: VoiceCallPhase,
    direction: VoiceCallDirection
  ) -> Bool {
    switch direction {
    case .incoming:
      return phase == .ringing
    case .outgoing:
      return phase == .ringing || phase == .connecting
    }
  }

  private func callUUID(callID: String, roomID: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data("\(roomID)\u{0}\(callID)".utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      )
    )
  }

  @objc private func proximityStateDidChange() {
    presentation.setProximityCovered(
      proximityMonitoringEnabled && UIDevice.current.proximityState
    )
  }

  @objc private func audioRouteDidChange() {
    updateAudioRoute(using: AVAudioSession.sharedInstance())
    updateProximityPolicy()
  }

  private func updateAudioRoute(using session: AVAudioSession) {
    let output = session.currentRoute.outputs.first
    let speaker = output?.portType == .builtInSpeaker
    let label: String
    switch output?.portType {
    case .builtInSpeaker:
      label = "Reproduktor"
    case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
      label = output?.portName ?? "Bluetooth"
    case .headphones, .headsetMic:
      label = output?.portName ?? "Sluchátka"
    case .builtInReceiver:
      label = "Telefon"
    default:
      label = output?.portName ?? "Telefon"
    }
    presentation.setRoute(label: label, speaker: speaker)
  }

  private func updateProximityPolicy() {
    let receiverRoute = AVAudioSession.sharedInstance().currentRoute.outputs.contains {
      $0.portType == .builtInReceiver
    }
    let shouldEnable =
      presentation.isAudioActive
      && presentation.activeCall?.phase == .connected
      && receiverRoute
      && !presentation.isSpeakerEnabled
    setProximityMonitoring(shouldEnable)
  }

  private func setProximityMonitoring(_ enabled: Bool) {
    guard proximityMonitoringEnabled != enabled else {
      presentation.setProximityCovered(enabled && UIDevice.current.proximityState)
      return
    }
    proximityMonitoringEnabled = enabled
    UIDevice.current.isProximityMonitoringEnabled = enabled
    presentation.setProximityCovered(enabled && UIDevice.current.proximityState)
  }
}
