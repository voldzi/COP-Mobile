@preconcurrency import CallKit
import Foundation

@MainActor
protocol VoiceCallIncomingReporting: AnyObject {
  func reportIncoming(uuid: UUID, title: String, completion: @escaping @MainActor (Bool) -> Void)
  func reportEnded(uuid: UUID)
}

@MainActor
final class VoiceCallProviderReporter: VoiceCallIncomingReporting {
  let provider: CXProvider
  init(provider: CXProvider) { self.provider = provider }
  func reportIncoming(uuid: UUID, title: String, completion: @escaping @MainActor (Bool) -> Void) {
    let update = CXCallUpdate()
    update.localizedCallerName = title
    update.remoteHandle = CXHandle(type: .generic, value: title)
    update.hasVideo = false
    // Invoke CallKit synchronously from the PushKit callback, before returning.
    provider.reportNewIncomingCall(with: uuid, update: update) { error in
      let succeeded = error == nil
      Task { @MainActor in completion(succeeded) }
    }
  }
  func reportEnded(uuid: UUID) {
    provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
  }
}

@MainActor
final class VoiceCallOnceCompletion {
  private var completion: (() -> Void)?
  var isPending: Bool { completion != nil }
  init(_ completion: @escaping () -> Void) { self.completion = completion }
  func finish() {
    let operation = completion
    completion = nil
    operation?()
  }
}

/// Only OS bookkeeping for an already delivered push. No runtime/auth/media path.
@MainActor
enum VoiceCallLatePushReporting {
  static func receive(_ push: VoiceCallPushPayload, reporter: any VoiceCallIncomingReporting,
                      completion: @escaping () -> Void) {
    let once = VoiceCallOnceCompletion(completion)
    guard push.event == .incoming else {
      reporter.reportEnded(uuid: push.uuid)
      once.finish()
      return
    }
    reporter.reportIncoming(uuid: push.uuid, title: push.callerDisplayName) { succeeded in
      guard once.isPending else { return }
      if succeeded { reporter.reportEnded(uuid: push.uuid) }
      once.finish()
    }
  }
}
