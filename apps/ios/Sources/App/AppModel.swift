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
  /// Creating `CLLocationManager` is deferred until a map/device action needs
  /// it. The native chat must not initialise a sensor or surface a permission
  /// prompt merely by being opened.
  private var storedDeviceLocationProvider: (any DeviceLocationProviding)?
  private let makeDeviceLocationProvider: @MainActor () -> any DeviceLocationProviding
  var deviceLocationProvider: any DeviceLocationProviding {
    if let storedDeviceLocationProvider {
      return storedDeviceLocationProvider
    }
    let provider = makeDeviceLocationProvider()
    storedDeviceLocationProvider = provider
    return provider
  }
  /// UI automation is deliberately available only to the Debug host. It lets
  /// smoke tests exercise the native communication surface without creating a
  /// WebKit session or asking the simulator for user permissions.
  private(set) var isUITesting = false
  private(set) var phase: Phase = .loading
  private(set) var reloadToken = 0
  private(set) var nativeChatExpectedSubjectID: String?
  var surface: Surface = .cop

  init(
    bundle: Bundle = .main,
    deviceLocationProvider: (any DeviceLocationProviding)? = nil,
    makeDeviceLocationProvider: @escaping @MainActor () -> any DeviceLocationProviding = {
      CoreLocationService()
    },
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    storedDeviceLocationProvider = deviceLocationProvider
    self.makeDeviceLocationProvider = makeDeviceLocationProvider
    do {
      configuration = .success(try AppConfiguration.load(from: bundle))
    } catch let error as AppConfigurationError {
      configuration = .failure(error)
      phase = .blocked(code: error.diagnosticCode)
    } catch {
      configuration = .failure(.invalidValue("configuration"))
      phase = .blocked(code: AppConfigurationError.invalidValue("configuration").diagnosticCode)
    }

    if case .success(let resolvedConfiguration) = configuration {
      isUITesting = resolvedConfiguration.environment == "development"
        && environment["COP_UI_TESTING"] == "1"
      if isUITesting && environment["COP_UI_TEST_INITIAL_PHASE"] == "offline" {
        webDidFail()
      }
      if isUITesting && environment["COP_UI_TEST_INITIAL_SURFACE"] == "chat" {
        surface = .chat
      }
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
      accuracyMeters: sample["horizontalAccuracyM"] as? Double,
      radiusKilometers: 15,
      label: "Aktuální poloha"
    )
  }

  /// Requests a single fresh sample only after the user explicitly chooses
  /// "Sdílet aktuální polohu" in the native composer.
  func requestCommunicationLocationShare() async throws -> CSMCommunicationLocation {
    let provider = deviceLocationProvider
    if provider.permission == "notDetermined" {
      _ = await provider.requestWhenInUseAuthorization()
    }

    switch provider.permission {
    case "granted":
      break
    case "restricted":
      throw CSMCommunicationLocationShareError.permissionRestricted
    case "denied":
      throw CSMCommunicationLocationShareError.permissionDenied
    default:
      throw CSMCommunicationLocationShareError.unavailable
    }

    do {
      let sample = try await provider.currentLocation(timeout: .seconds(8))
      guard sample["valid"] as? Bool == true,
        let latitude = sample["latitude"] as? Double,
        let longitude = sample["longitude"] as? Double
      else {
        throw CSMCommunicationLocationShareError.unavailable
      }
      return CSMCommunicationLocation(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: sample["horizontalAccuracyM"] as? Double,
        label: "Moje poloha"
      )
    } catch DeviceLocationError.timeout {
      throw CSMCommunicationLocationShareError.timedOut
    } catch let shareError as CSMCommunicationLocationShareError {
      throw shareError
    } catch {
      throw CSMCommunicationLocationShareError.unavailable
    }
  }

  func startNativeVoiceCall(
    roomID: String,
    title: String,
    participantSubjectIDs: [String]?,
    starter: (_ roomID: String, _ title: String, _ participantSubjectIDs: [String]?) -> Void = {
      roomID, title, participantSubjectIDs in
      VoiceCallService.shared.startVoiceCall(
        roomID: roomID,
        title: title,
        participantSubjectIDs: participantSubjectIDs
      )
    }
  ) {
    starter(roomID, title, participantSubjectIDs)
  }

  private static func makeDiagnosticCode(prefix: String) -> String {
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
    return "\(prefix)-\(suffix)"
  }
}
