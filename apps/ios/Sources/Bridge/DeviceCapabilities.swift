import Foundation

enum DeviceCapabilities {
  static let protocolVersion = "1.0.0"
  static let maximumJSONBytes = 65_536
  static let requestTimeoutMilliseconds = 15_000

  static func limits() -> [String: Any] {
    [
      "maxAssetBytes": 0,
      "maxJsonBytes": maximumJSONBytes,
      "requestTimeoutMs": requestTimeoutMilliseconds,
    ]
  }

  static func snapshot() -> [String: Any] {
    let unsupported: [String: Any] = [
      "availability": "unsupported",
      "permission": "unavailable",
      "supportsBackground": false,
      "limitations": ["Not implemented in the iOS feasibility host."],
    ]
    let system: [String: Any] = [
      "availability": "supported",
      "permission": "granted",
      "supportsBackground": false,
    ]
    return [
      "system": system,
      "permissions": unsupported,
      "location": unsupported,
      "heading": unsupported,
      "attitude": unsupported,
      "tracking": unsupported,
      "connectivity": unsupported,
      "media": unsupported,
      "shares": unsupported,
      "notifications": unsupported,
      "relay": unsupported,
    ]
  }

  static func fullSnapshot(observedAt: String) -> [String: Any] {
    [
      "adapter": "native",
      "capabilities": snapshot(),
      "limits": limits(),
      "protocolVersion": protocolVersion,
      "observedAt": observedAt,
    ]
  }
}
