import CryptoKit
import Foundation

@MainActor
final class DeviceBridgeCoordinator {
  struct RequestContext {
    let isMainFrame: Bool
    let frameURL: URL?
    let mainFrameURL: URL?
  }

  private let originPolicy: OriginPolicy
  private var navigationIsEligible = false
  private var sessionID: String?
  private struct CachedResponse {
    let requestDigest: String
    let response: [String: Any]
  }

  private var responseCache: [String: CachedResponse] = [:]
  private var responseOrder: [String] = []

  init(originPolicy: OriginPolicy) {
    self.originPolicy = originPolicy
  }

  func navigationDidCommit(url: URL?) {
    invalidateSession()
    navigationIsEligible = originPolicy.isBridgeOrigin(url)
  }

  func invalidateSession() {
    navigationIsEligible = false
    sessionID = nil
    responseCache.removeAll(keepingCapacity: true)
    responseOrder.removeAll(keepingCapacity: true)
  }

  func handle(message body: Any, context: RequestContext) -> [String: Any] {
    guard let dictionary = body as? [String: Any],
      JSONSerialization.isValidJSONObject(dictionary),
      let encoded = try? JSONSerialization.data(withJSONObject: dictionary),
      encoded.count <= DeviceCapabilities.maximumJSONBytes
    else {
      return blocked(
        id: messageID(from: body), code: "INVALID_REQUEST",
        message: "Bridge message is invalid or too large.")
    }
    guard context.isMainFrame else {
      return blocked(
        id: messageID(from: dictionary), code: "MAIN_FRAME_REQUIRED",
        message: "Device API is available only to the main frame.")
    }
    guard navigationIsEligible,
      let frameURL = context.frameURL,
      originPolicy.allowsBridge(frameURL: frameURL, mainFrameURL: context.mainFrameURL)
    else {
      invalidateSession()
      return blocked(
        id: messageID(from: dictionary), code: "ORIGIN_NOT_ALLOWED",
        message: "The current origin is not allowed to use Device API.")
    }
    guard let kind = dictionary["kind"] as? String else {
      return blocked(
        id: messageID(from: dictionary), code: "INVALID_REQUEST",
        message: "Bridge message kind is missing.")
    }

    switch kind {
    case "hello":
      return handleHello(dictionary)
    case "request":
      return handleRequest(dictionary, requestDigest: digest(dictionary))
    default:
      return blocked(
        id: messageID(from: dictionary), code: "INVALID_REQUEST",
        message: "Bridge message kind is unsupported.")
    }
  }

  private func handleHello(_ message: [String: Any]) -> [String: Any] {
    let requiredKeys: Set<String> = ["kind", "id", "sentAt", "supportedVersions", "webBuildId"]
    guard Set(message.keys) == requiredKeys,
      let id = validUUID(message["id"]),
      isTimestamp(message["sentAt"]),
      let versions = message["supportedVersions"] as? [String],
      !versions.isEmpty,
      versions.count <= 8,
      let webBuildID = message["webBuildId"] as? String,
      !webBuildID.isEmpty,
      webBuildID.count <= 128
    else {
      return blocked(
        id: messageID(from: message), code: "INVALID_REQUEST",
        message: "Handshake does not match the Device API contract.")
    }
    guard versions.contains(DeviceCapabilities.protocolVersion) else {
      return blocked(
        id: id, code: "PROTOCOL_VERSION_UNSUPPORTED",
        message: "No compatible Device API version is available.")
    }

    let sessionID = UUID().uuidString.lowercased()
    self.sessionID = sessionID
    responseCache.removeAll(keepingCapacity: true)
    responseOrder.removeAll(keepingCapacity: true)
    return [
      "kind": "ready",
      "id": id,
      "sentAt": timestamp(),
      "selectedVersion": DeviceCapabilities.protocolVersion,
      "sessionId": sessionID,
      "capabilities": DeviceCapabilities.snapshot(),
      "limits": DeviceCapabilities.limits(),
    ]
  }

  private func handleRequest(_ message: [String: Any], requestDigest: String) -> [String: Any] {
    let requiredKeys: Set<String> = [
      "kind", "protocolVersion", "id", "sessionId", "method", "sentAt", "params",
    ]
    guard Set(message.keys) == requiredKeys,
      let id = validUUID(message["id"]),
      let requestSessionID = validUUID(message["sessionId"]),
      message["protocolVersion"] as? String == DeviceCapabilities.protocolVersion,
      isTimestamp(message["sentAt"]),
      message["params"] is [String: Any],
      let method = message["method"] as? String
    else {
      return responseError(
        id: messageID(from: message),
        sessionID: message["sessionId"] as? String,
        code: "INVALID_REQUEST",
        message: "Request does not match the Device API contract."
      )
    }
    guard requestSessionID == sessionID else {
      return responseError(
        id: id, sessionID: requestSessionID, code: "SESSION_EXPIRED",
        message: "Bridge session is no longer active.")
    }
    if let cached = responseCache[id] {
      guard cached.requestDigest == requestDigest else {
        return responseError(
          id: id,
          sessionID: requestSessionID,
          code: "INVALID_REQUEST",
          message: "Request ID was reused with different content."
        )
      }
      return cached.response
    }
    guard method == "system.getCapabilities" else {
      return cache(
        responseError(
          id: id, sessionID: requestSessionID, code: "UNSUPPORTED",
          message: "Method is not implemented by this host."),
        id: id,
        requestDigest: requestDigest
      )
    }
    let response: [String: Any] = [
      "kind": "response",
      "protocolVersion": DeviceCapabilities.protocolVersion,
      "id": id,
      "sessionId": requestSessionID,
      "sentAt": timestamp(),
      "ok": true,
      "result": DeviceCapabilities.fullSnapshot(observedAt: timestamp()),
    ]
    return cache(response, id: id, requestDigest: requestDigest)
  }

  private func blocked(id: String, code: String, message: String) -> [String: Any] {
    [
      "kind": "blocked",
      "id": validUUID(id) ?? UUID().uuidString.lowercased(),
      "sentAt": timestamp(),
      "error": errorPayload(code: code, message: message),
    ]
  }

  private func responseError(id: String, sessionID: String?, code: String, message: String)
    -> [String: Any]
  {
    [
      "kind": "response",
      "protocolVersion": DeviceCapabilities.protocolVersion,
      "id": validUUID(id) ?? UUID().uuidString.lowercased(),
      "sessionId": validUUID(sessionID) ?? UUID().uuidString.lowercased(),
      "sentAt": timestamp(),
      "ok": false,
      "error": errorPayload(code: code, message: message),
    ]
  }

  private func errorPayload(code: String, message: String) -> [String: Any] {
    ["code": code, "message": message, "retryable": false]
  }

  private func cache(_ response: [String: Any], id: String, requestDigest: String) -> [String: Any]
  {
    responseCache[id] = CachedResponse(requestDigest: requestDigest, response: response)
    responseOrder.append(id)
    if responseOrder.count > 128 {
      let removed = responseOrder.removeFirst()
      responseCache.removeValue(forKey: removed)
    }
    return response
  }

  private func digest(_ message: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])
    else {
      return "invalid"
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func validUUID(_ value: Any?) -> String? {
    guard let value = value as? String, UUID(uuidString: value) != nil else { return nil }
    return value.lowercased()
  }

  private func messageID(from body: Any?) -> String {
    let dictionary = body as? [String: Any]
    return dictionary?["id"] as? String ?? ""
  }

  private func isTimestamp(_ value: Any?) -> Bool {
    guard let value = value as? String else { return false }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: value) != nil || ISO8601DateFormatter().date(from: value) != nil
  }

  private func timestamp() -> String {
    ISO8601DateFormatter().string(from: Date())
  }
}
