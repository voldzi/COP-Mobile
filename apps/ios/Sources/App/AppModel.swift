import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  enum Surface: Equatable {
    case cop
    case chat
  }

  enum Phase: Equatable {
    case loading
    case webContent
    case offlineFallback(code: String)
    case blocked(code: String)
  }

  let configuration: Result<AppConfiguration, AppConfigurationError>
  private(set) var phase: Phase = .loading
  private(set) var reloadToken = 0
  var surface: Surface = .cop

  init(bundle: Bundle = .main) {
    do {
      configuration = .success(try AppConfiguration.load(from: bundle))
    } catch let error as AppConfigurationError {
      configuration = .failure(error)
      phase = .blocked(code: error.diagnosticCode)
    } catch {
      configuration = .failure(.invalidValue("configuration"))
      phase = .blocked(code: AppConfigurationError.invalidValue("configuration").diagnosticCode)
    }
  }

  func webDidStartLoading() {
    phase = .loading
  }

  func webDidBecomeReady() {
    phase = .webContent
  }

  func webDidFail() {
    phase = .offlineFallback(code: Self.makeDiagnosticCode(prefix: "WEB"))
  }

  func webWasBlocked() {
    phase = .blocked(code: Self.makeDiagnosticCode(prefix: "SEC"))
  }

  func retry() {
    reloadToken += 1
    phase = .loading
  }

  func invalidateWebMedia() {
    reloadToken += 1
    phase = .loading
  }

  func openNativeChat() {
    surface = .chat
  }

  func closeNativeChat() {
    surface = .cop
  }

  func startNativeVoiceCall(
    roomID: String,
    title: String,
    isGroup: Bool,
    starter: (_ roomID: String, _ title: String, _ isGroup: Bool) -> Void = { roomID, title, isGroup in
      VoiceCallService.shared.startVoiceCall(roomID: roomID, title: title, isGroup: isGroup)
    }
  ) {
    starter(roomID, title, isGroup)
  }

  private static func makeDiagnosticCode(prefix: String) -> String {
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
    return "\(prefix)-\(suffix)"
  }
}
