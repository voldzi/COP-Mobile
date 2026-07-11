import CryptoKit
import Foundation
import UIKit

private enum BridgeExecutionError: Error {
  case notForeground
  case unsupported
}

@MainActor
final class DeviceBridgeCoordinator {
  struct RequestContext {
    let isMainFrame: Bool
    let frameURL: URL?
    let mainFrameURL: URL?
  }

  private let originPolicy: OriginPolicy
  private let location: DeviceLocationProviding
  private let notifications: PushNotificationProviding
  private let isForeground: () -> Bool
  var eventSink: (([String: Any]) -> Void)?
  private var navigationIsEligible = false
  private var sessionID: String?
  private var eventSequence = 0
  private var pendingEvents: [(String, Any)] = []
  private struct CachedResponse {
    let requestDigest: String
    let response: [String: Any]
  }

  private var responseCache: [String: CachedResponse] = [:]
  private var responseOrder: [String] = []

  init(
    originPolicy: OriginPolicy,
    location: DeviceLocationProviding = CoreLocationService(),
    notifications: PushNotificationProviding = PushNotificationService.shared,
    isForeground: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
  ) {
    self.originPolicy = originPolicy
    self.location = location
    self.notifications = notifications
    self.isForeground = isForeground
    notifications.eventReceiver = { [weak self] type, payload in self?.emit(type: type, payload: payload) }
  }

  func navigationDidCommit(url: URL?) {
    invalidateSession()
    navigationIsEligible = originPolicy.isBridgeOrigin(url)
  }

  func invalidateSession() {
    location.stopAllUpdates()
    navigationIsEligible = false
    sessionID = nil
    eventSequence = 0
    responseCache.removeAll(keepingCapacity: true)
    responseOrder.removeAll(keepingCapacity: true)
  }

  func handle(message body: Any, context: RequestContext) async -> [String: Any] {
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
      return await handleRequest(dictionary, requestDigest: digest(dictionary))
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
    flushPendingEvents()
    return [
      "kind": "ready",
      "id": id,
      "sentAt": timestamp(),
      "selectedVersion": DeviceCapabilities.protocolVersion,
      "sessionId": sessionID,
      "capabilities": DeviceCapabilities.snapshot(location: location),
      "limits": DeviceCapabilities.limits(),
    ]
  }

  private func handleRequest(_ message: [String: Any], requestDigest: String) async -> [String: Any] {
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
    let result: Any
    do {
      result = try await execute(method: method, params: message["params"] as! [String: Any])
    } catch {
      let mapped = mapError(error)
      return cache(
        responseError(id: id, sessionID: requestSessionID, code: mapped.0, message: mapped.1),
        id: id, requestDigest: requestDigest)
    }
    let response: [String: Any] = [
      "kind": "response",
      "protocolVersion": DeviceCapabilities.protocolVersion,
      "id": id,
      "sessionId": requestSessionID,
      "sentAt": timestamp(),
      "ok": true,
      "result": result,
    ]
    return cache(response, id: id, requestDigest: requestDigest)
  }

  private func execute(method: String, params: [String: Any]) async throws -> Any {
    switch method {
    case "system.getCapabilities":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      return DeviceCapabilities.fullSnapshot(observedAt: timestamp(), location: location)
    case "permissions.getStatus":
      try validateLocationPermissionParams(params)
      return permissionResult()
    case "permissions.request":
      try validateLocationPermissionParams(params)
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      let previous = location.permission
      _ = await location.requestWhenInUseAuthorization()
      if location.permission != previous {
        emit(type: "permission.changed", payload: permissionResult())
      }
      return permissionResult()
    case "permissions.openSettings":
      try validateLocationPermissionParams(params)
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        throw DeviceLocationError.unavailable
      }
      return ["opened": await UIApplication.shared.open(url)]
    case "location.getCurrent":
      try validateAccuracyParams(params)
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      return try await location.currentLocation(timeout: .milliseconds(DeviceCapabilities.requestTimeoutMilliseconds))
    case "location.startUpdates":
      try validateAccuracyParams(params)
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      try location.startLocationUpdates { [weak self] sample in
        self?.emit(type: "location.updated", payload: sample)
      }
      return ["started": true]
    case "location.stopUpdates":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      location.stopLocationUpdates()
      return ["stopped": true]
    case "heading.startUpdates":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      try location.startHeadingUpdates { [weak self] sample in
        self?.emit(type: "heading.updated", payload: sample)
        if sample["calibration"] as? String == "uncalibrated" {
          self?.emit(type: "heading.calibrationRequired", payload: ["required": true])
        }
      }
      return ["started": true]
    case "heading.stopUpdates":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      location.stopHeadingUpdates()
      return ["stopped": true]
    case "notifications.getStatus":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      return await notifications.status()
    case "notifications.requestAuthorization":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      return await notifications.requestAuthorization()
    case "notifications.getRegistrationContext":
      guard params.isEmpty else { throw DeviceLocationError.invalidSample }
      return notifications.registrationContext()
    case "notifications.registerRemote":
      guard Set(params.keys) == ["ticket", "messagingBaseUrl"],
        let ticket = params["ticket"] as? String,
        let messagingBaseURL = params["messagingBaseUrl"] as? String
      else { throw DeviceLocationError.invalidSample }
      guard isForeground() else { throw BridgeExecutionError.notForeground }
      return try await notifications.registerRemote(ticket: ticket, messagingBaseURL: messagingBaseURL)
    default:
      throw BridgeExecutionError.unsupported
    }
  }

  private func validateLocationPermissionParams(_ params: [String: Any]) throws {
    guard Set(params.keys) == ["permission"], params["permission"] as? String == "location" else {
      throw DeviceLocationError.invalidSample
    }
  }

  private func validateAccuracyParams(_ params: [String: Any]) throws {
    guard Set(params.keys).isSubset(of: ["desiredAccuracy"]) else {
      throw DeviceLocationError.invalidSample
    }
    if let accuracy = params["desiredAccuracy"] {
      guard let value = accuracy as? String, ["best", "balanced"].contains(value) else {
        throw DeviceLocationError.invalidSample
      }
    }
  }

  private func permissionResult() -> [String: Any] {
    [
      "permission": "location", "status": location.permission,
      "accuracy": location.permission == "granted" ? (location.reducedAccuracy ? "reduced" : "full") : "unavailable",
    ]
  }

  private func emit(type: String, payload: Any) {
    guard let sessionID else {
      if pendingEvents.count >= 8 { pendingEvents.removeFirst() }
      pendingEvents.append((type, payload))
      return
    }
    eventSequence += 1
    eventSink?([
      "kind": "event", "protocolVersion": DeviceCapabilities.protocolVersion,
      "eventId": UUID().uuidString.lowercased(), "sessionId": sessionID,
      "sequence": eventSequence, "type": type, "occurredAt": timestamp(), "payload": payload,
    ])
  }

  private func flushPendingEvents() {
    guard sessionID != nil else { return }
    let events = pendingEvents
    pendingEvents.removeAll(keepingCapacity: true)
    for (type, payload) in events {
      emit(type: type, payload: payload)
    }
  }

  private func mapError(_ error: any Error) -> (String, String) {
    switch error {
    case DeviceLocationError.permissionNotDetermined:
      ("PERMISSION_NOT_DETERMINED", "Location permission has not been requested.")
    case DeviceLocationError.permissionDenied:
      ("PERMISSION_DENIED", "Location permission was denied.")
    case DeviceLocationError.permissionRestricted:
      ("PERMISSION_RESTRICTED", "Location permission is restricted.")
    case DeviceLocationError.timeout:
      ("TIMEOUT", "A location sample was not available in time.")
    case is CancellationError:
      ("CANCELLED", "The operation was cancelled.")
    case BridgeExecutionError.notForeground:
      ("NOT_FOREGROUND", "This operation requires the app to be active.")
    case BridgeExecutionError.unsupported:
      ("UNSUPPORTED", "Method is not implemented by this host.")
    case DeviceLocationError.invalidSample:
      ("INVALID_REQUEST", "Request parameters do not match the Device API contract.")
    default:
      ("TRANSPORT_UNAVAILABLE", "The requested sensor is currently unavailable.")
    }
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
