import Foundation

struct AppConfiguration: Sendable {
  let environment: String
  let webOrigin: WebOrigin
  let oidcOrigin: WebOrigin
  let bridgeOrigins: Set<WebOrigin>
  let navigationOrigins: Set<WebOrigin>

  var initialURL: URL { webOrigin.url }

  static func load(from bundle: Bundle) throws -> AppConfiguration {
    guard let environment = bundle.object(forInfoDictionaryKey: "COPEnvironment") as? String,
      !environment.isEmpty
    else {
      throw AppConfigurationError.missingValue("COPEnvironment")
    }
    guard let webValue = bundle.object(forInfoDictionaryKey: "COPWebOrigin") as? String,
      !webValue.isEmpty
    else {
      throw AppConfigurationError.missingValue("COPWebOrigin")
    }
    guard let oidcValue = bundle.object(forInfoDictionaryKey: "COPOIDCOrigin") as? String,
      !oidcValue.isEmpty
    else {
      throw AppConfigurationError.missingValue("COPOIDCOrigin")
    }

    let webOrigin = try WebOrigin(configurationValue: webValue)
    let oidcOrigin = try WebOrigin(configurationValue: oidcValue)
    var bridgeOrigins: Set<WebOrigin> = [webOrigin]
    var navigationOrigins: Set<WebOrigin> = [webOrigin, oidcOrigin]

    #if DEBUG
      let debugValues =
        bundle.object(forInfoDictionaryKey: "COPAdditionalDebugBridgeOrigins") as? [String] ?? []
      for value in debugValues {
        let origin = try WebOrigin(configurationValue: value, allowsInsecureLocalhost: true)
        bridgeOrigins.insert(origin)
        navigationOrigins.insert(origin)
      }
    #endif

    #if !DEBUG
      guard bridgeOrigins.allSatisfy({ $0.scheme == "https" }) else {
        throw AppConfigurationError.insecureReleaseOrigin
      }
    #endif

    return AppConfiguration(
      environment: environment,
      webOrigin: webOrigin,
      oidcOrigin: oidcOrigin,
      bridgeOrigins: bridgeOrigins,
      navigationOrigins: navigationOrigins
    )
  }
}

enum AppConfigurationError: Error, Equatable {
  case missingValue(String)
  case invalidValue(String)
  case insecureReleaseOrigin

  var diagnosticCode: String {
    switch self {
    case .missingValue: "CFG-MISSING"
    case .invalidValue: "CFG-INVALID"
    case .insecureReleaseOrigin: "CFG-INSECURE"
    }
  }

  var userMessage: String {
    switch self {
    case .missingValue:
      "Chybí povinný bezpečný origin. Sestavení zůstává fail-closed."
    case .invalidValue:
      "Nakonfigurovaný origin není platný přesný webový origin."
    case .insecureReleaseOrigin:
      "Release sestavení smí používat pouze HTTPS originy."
    }
  }
}
