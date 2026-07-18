import CSMCommunicationKit
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
  let deviceLocationProvider: any DeviceLocationProviding
  private(set) var phase: Phase = .loading
  private(set) var reloadToken = 0
  private(set) var nativeChatExpectedSubjectID: String?
  var surface: Surface = .cop

  init(
    bundle: Bundle = .main,
    deviceLocationProvider: any DeviceLocationProviding = CoreLocationService()
  ) {
    self.deviceLocationProvider = deviceLocationProvider
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

  func openNativeChat(expectedSubjectID: String? = nil) {
    let normalizedSubjectID = expectedSubjectID?.trimmingCharacters(in: .whitespacesAndNewlines)
    nativeChatExpectedSubjectID = normalizedSubjectID?.isEmpty == false ? normalizedSubjectID : nil
    surface = .chat
  }

  func closeNativeChat() {
    surface = .cop
  }

  /// Supplies an already-authorized, short-lived location sample to the
  /// native communication surface. Chat never prompts for location itself;
  /// permission remains owned by the main COP map/device flow.
  func currentCommunicationLocation() async -> CSMCommunicationLocation? {
    guard deviceLocationProvider.permission == "granted",
      let sample = try? await deviceLocationProvider.currentLocation(timeout: .seconds(4)),
      sample["valid"] as? Bool == true,
      let latitude = sample["latitude"] as? Double,
      let longitude = sample["longitude"] as? Double
    else {
      return nil
    }
    return CSMCommunicationLocation(
      latitude: latitude,
      longitude: longitude,
      radiusKilometers: 15,
      label: "Aktuální poloha"
    )
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
