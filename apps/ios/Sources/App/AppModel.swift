import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
  enum Phase: Equatable {
    case loading
    case webContent
    case offlineFallback(code: String)
    case blocked(code: String)
  }

  let configuration: Result<AppConfiguration, AppConfigurationError>
  private(set) var phase: Phase = .loading
  private(set) var reloadToken = 0

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

  private static func makeDiagnosticCode(prefix: String) -> String {
    let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)
    return "\(prefix)-\(suffix)"
  }
}
