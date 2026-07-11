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

  @MainActor static func snapshot(location: DeviceLocationProviding? = nil) -> [String: Any] {
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
    let permission = location?.permission ?? "unavailable"
    let permissions: [String: Any] = [
      "availability": "supported", "permission": "granted", "supportsBackground": false,
    ]
    let locationCapability: [String: Any] = [
      "availability": location?.locationAvailable == false ? "temporarilyUnavailable" : "supported",
      "permission": permission,
      "supportsBackground": false,
      "requiresForeground": true,
      "limitations": ["Foreground only; reduced accuracy is reported without automatic escalation."],
    ]
    let headingCapability: [String: Any] = [
      "availability": location?.headingAvailable == false ? "temporarilyUnavailable" : "supported",
      "permission": permission,
      "supportsBackground": false,
      "requiresForeground": true,
    ]
    return [
      "system": system,
      "permissions": permissions,
      "location": locationCapability,
      "heading": headingCapability,
      "attitude": unsupported,
      "tracking": unsupported,
      "connectivity": unsupported,
      "media": unsupported,
      "shares": unsupported,
      "notifications": unsupported,
      "relay": unsupported,
    ]
  }

  @MainActor static func fullSnapshot(observedAt: String, location: DeviceLocationProviding? = nil)
    -> [String: Any]
  {
    [
      "adapter": "native",
      "capabilities": snapshot(location: location),
      "limits": limits(),
      "protocolVersion": protocolVersion,
      "observedAt": observedAt,
    ]
  }
}
