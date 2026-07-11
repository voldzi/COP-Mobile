import AVFAudio
@preconcurrency import CallKit
import CryptoKit
import Foundation
@preconcurrency import PushKit

@MainActor
final class VoiceCallService: NSObject, @preconcurrency CXProviderDelegate, @preconcurrency PKPushRegistryDelegate {
  static let shared = VoiceCallService()

  struct CallContext {
    let callID: String
    let roomID: String
    var answered: Bool
  }

  private final class CompletionBox: @unchecked Sendable {
    let completion: () -> Void

    init(_ completion: @escaping () -> Void) {
      self.completion = completion
    }
  }

  private let provider: CXProvider
  private var registry: PKPushRegistry!
  private var calls: [UUID: CallContext] = [:]
  private var pushToken: String?
  private var tokenContinuation: CheckedContinuation<String, any Error>?
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
  }

  func currentPushToken() async throws -> String {
    if let pushToken { return pushToken }
    guard tokenContinuation == nil else { throw PushRegistrationError.registrationPending }
    return try await withCheckedThrowingContinuation { continuation in
      tokenContinuation = continuation
    }
  }

  func prepareForegroundAudio() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.allowBluetoothHFP, .defaultToSpeaker]
    )
    try session.setActive(true)
  }

  func requestMicrophoneAndPrepare(_ completion: @escaping @MainActor (Bool) -> Void) {
    switch AVAudioApplication.shared.recordPermission {
    case .granted:
      completion((try? prepareForegroundAudio()) != nil)
    case .denied:
      completion(false)
    case .undetermined:
      AVAudioApplication.requestRecordPermission { granted in
        Task { @MainActor in
          guard granted else {
            completion(false)
            return
          }
          completion((try? self.prepareForegroundAudio()) != nil)
        }
      }
    @unknown default:
      completion(false)
    }
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
    let uuid = callUUID(callID)
    if type == "chat.voice_call.ended" {
      provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
      calls.removeValue(forKey: uuid)
      completion()
      return
    }
    guard type == "chat.voice_call.incoming" else {
      completion()
      return
    }

    let caller = boundedString(payload["senderDisplayName"]) ?? "COP kontakt"
    calls[uuid] = CallContext(callID: callID, roomID: roomID, answered: false)
    let update = CXCallUpdate()
    update.hasVideo = false
    update.localizedCallerName = caller
    update.remoteHandle = CXHandle(type: .generic, value: caller)
    update.supportsDTMF = false
    update.supportsGrouping = false
    update.supportsHolding = false
    update.supportsUngrouping = false
    let completionBox = CompletionBox(completion)
    provider.reportNewIncomingCall(with: uuid, update: update) { _ in
      completionBox.completion()
    }
  }

  func providerDidReset(_ provider: CXProvider) {
    calls.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    guard var call = calls[action.callUUID] else {
      action.fail()
      return
    }
    do {
      try prepareForegroundAudio()
      call.answered = true
      calls[action.callUUID] = call
      emit("calls.answerRequested", call)
      action.fulfill()
    } catch {
      action.fail()
    }
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    guard let call = calls.removeValue(forKey: action.callUUID) else {
      action.fulfill()
      return
    }
    emit(call.answered ? "calls.endRequested" : "calls.rejectRequested", call)
    action.fulfill()
  }

  func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
    try? prepareForegroundAudio()
  }

  private func emit(_ type: String, _ call: CallContext) {
    eventReceiver?(type, ["callId": call.callID, "roomId": call.roomID])
  }

  private func boundedString(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || trimmed.count > 512 ? nil : trimmed
  }

  private func callUUID(_ callID: String) -> UUID {
    var bytes = Array(SHA256.hash(data: Data(callID.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0f) | 0x40
    bytes[8] = (bytes[8] & 0x3f) | 0x80
    return UUID(uuid: (
      bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
  }
}
