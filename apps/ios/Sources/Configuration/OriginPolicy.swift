import Foundation

struct WebOrigin: Hashable, Sendable, CustomStringConvertible {
  let scheme: String
  let host: String
  let port: Int

  var description: String {
    let defaultPort = scheme == "https" ? 443 : 80
    return port == defaultPort ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
  }

  var url: URL { URL(string: description)! }

  init(configurationValue: String, allowsInsecureLocalhost: Bool = false) throws {
    guard let components = URLComponents(string: configurationValue),
      let rawScheme = components.scheme?.lowercased(),
      let rawHost = components.host?.lowercased(),
      components.user == nil,
      components.password == nil,
      components.query == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else {
      throw AppConfigurationError.invalidValue(configurationValue)
    }
    guard
      rawScheme == "https"
        || (allowsInsecureLocalhost && rawScheme == "http" && rawHost == "localhost")
    else {
      throw AppConfigurationError.invalidValue(configurationValue)
    }
    scheme = rawScheme
    host = rawHost
    port = components.port ?? (rawScheme == "https" ? 443 : 80)
  }

  init?(url: URL) {
    guard let scheme = url.scheme?.lowercased(),
      let host = url.host?.lowercased(),
      url.user == nil,
      url.password == nil,
      scheme == "https" || scheme == "http"
    else { return nil }
    self.scheme = scheme
    self.host = host
    port = url.port ?? (scheme == "https" ? 443 : 80)
  }
}

struct OriginPolicy: Sendable {
  let bridgeOrigins: Set<WebOrigin>
  let navigationOrigins: Set<WebOrigin>

  func allowsBridge(frameURL: URL, mainFrameURL: URL?) -> Bool {
    guard let frameOrigin = WebOrigin(url: frameURL),
      let mainFrameURL,
      let mainOrigin = WebOrigin(url: mainFrameURL)
    else { return false }
    return frameOrigin == mainOrigin && bridgeOrigins.contains(frameOrigin)
  }

  func allowsInternalNavigation(to url: URL) -> Bool {
    guard let origin = WebOrigin(url: url) else { return false }
    return navigationOrigins.contains(origin)
  }

  func allowsExternalOpen(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      url.host?.isEmpty == false
    else { return false }
    return true
  }

  func allowsMicrophoneCapture(
    frameURL: URL?,
    mainFrameURL: URL?,
    requestingScheme: String,
    requestingHost: String,
    requestingPort: Int,
    isMainFrame: Bool,
    microphoneOnly: Bool
  ) -> Bool {
    guard microphoneOnly,
      let frameURL,
      allowsBridge(frameURL: frameURL, mainFrameURL: mainFrameURL),
      let frameOrigin = WebOrigin(url: frameURL)
    else { return false }
    let normalizedRequestingPort =
      requestingPort == 0 ? (requestingScheme.lowercased() == "https" ? 443 : 80) : requestingPort
    return frameOrigin.scheme == requestingScheme.lowercased()
      && frameOrigin.host == requestingHost.lowercased()
      && frameOrigin.port == normalizedRequestingPort
  }

  func isBridgeOrigin(_ url: URL?) -> Bool {
    guard let url, let origin = WebOrigin(url: url) else { return false }
    return bridgeOrigins.contains(origin)
  }
}
