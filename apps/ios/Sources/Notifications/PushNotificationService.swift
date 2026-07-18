import CSMCommunicationKit
import Foundation
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
  static let copNativeChatRequested = Notification.Name("cz.zeleznalady.csm.nativeChatRequested")
}

private final class NotificationCompletionBox<Value>: @unchecked Sendable {
  private let completion: (Value) -> Void

  init(_ completion: @escaping (Value) -> Void) {
    self.completion = completion
  }

  func callAsFunction(_ value: Value) {
    completion(value)
  }
}

@MainActor
protocol PushNotificationProviding: AnyObject {
  var deviceToken: String? { get }
  func attachEventReceiver(
    ownerID: UUID,
    receiver: @escaping (String, [String: Any]) -> Void
  )
  func detachEventReceiver(ownerID: UUID)
  func status() async -> [String: Any]
  func requestAuthorization() async -> [String: Any]
  func registrationContext() -> [String: Any]
  func registerRemote(ticket: String, messagingBaseURL: String) async throws -> [String: Any]
  func recordDeviceToken(_ data: Data)
  func recordRegistrationFailure(_ error: any Error)
  func receiveRemoteNotification(_ userInfo: [AnyHashable: Any], interaction: Bool)
}

@MainActor
final class PushNotificationService: NSObject, PushNotificationProviding,
  UNUserNotificationCenterDelegate
{
  static let shared = PushNotificationService()
  static let registrationCategories = [
    "community.report",
    "message.direct",
    "message.group",
    "message.voice_call",
    "safety.alert",
    "safety.area_update",
    "system.account",
    "system.delivery",
  ]

  private let center = UNUserNotificationCenter.current()
  private(set) var deviceToken: String?
  private var registrationFailure: String?
  private var tokenContinuation: CheckedContinuation<String, any Error>?
  private var pendingBridgeEvents: [(String, [String: Any])] = []
  private var eventReceiverOwnerID: UUID?
  private var eventReceiver: ((String, [String: Any]) -> Void)?

  private override init() {
    super.init()
    CSMCommunicationNotifications.prepareHostApplication()
    center.delegate = self
    VoiceCallService.shared.eventReceiver = { [weak self] type, payload in
      self?.emitBridgeEvent(type: type, payload: payload)
    }
  }

  func status() async -> [String: Any] {
    let settings = await center.notificationSettings()
    return Self.statusPayload(
      settings, registered: deviceToken != nil, failed: registrationFailure != nil)
  }

  func requestAuthorization() async -> [String: Any] {
    do {
      // Time Sensitive authorization is granted through the signed
      // com.apple.developer.usernotifications.time-sensitive entitlement.
      // UNAuthorizationOption.timeSensitive has been deprecated since iOS 15.
      _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      registrationFailure = nil
      UIApplication.shared.registerForRemoteNotifications()
    } catch {
      registrationFailure = "authorization"
    }
    return await status()
  }

  func registrationContext() -> [String: Any] {
    ["appInstanceId": appInstanceID, "bundleId": "cz.zeleznalady.csm.messenger"]
  }

  func registerRemote(ticket: String, messagingBaseURL: String) async throws -> [String: Any] {
    guard ticket.hasPrefix("csmrt1."), ticket.count <= 4096,
      let baseURL = URL(string: messagingBaseURL), baseURL.scheme == "https",
      baseURL.host == "msg.zeleznalady.cz", baseURL.user == nil, baseURL.password == nil
    else { throw PushRegistrationError.invalidRequest }
    let token = try await currentDeviceToken()
    let voipToken = try await VoiceCallService.shared.currentPushToken()
    let endpoint = baseURL.appending(path: "api/v1/devices")
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("Bearer \(ticket)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "appBundleId": "cz.zeleznalady.csm.messenger",
      "appInstanceId": appInstanceID,
      "capabilities": [
        "e2ee": true, "criticalAlerts": false, "liveActivities": false, "voip": true,
      ],
      "deviceToken": token,
      "voipDeviceToken": voipToken,
      "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
      "platform": "ios",
      "preferences": ["categories": Self.registrationCategories],
      "subscriptions": ["groupIds": [], "areaIds": []],
      "timezone": TimeZone.current.identifier,
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 201,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let device = object["device"] as? [String: Any], let deviceID = device["deviceId"] as? String
    else { throw PushRegistrationError.serverRejected }
    return ["registered": true, "deviceId": deviceID]
  }

  func recordDeviceToken(_ data: Data) {
    deviceToken = data.map { String(format: "%02x", $0) }.joined()
    registrationFailure = nil
    CSMCommunicationNotifications.recordDeviceToken(data)
    tokenContinuation?.resume(returning: deviceToken!)
    tokenContinuation = nil
  }

  func recordRegistrationFailure(_ error: any Error) {
    deviceToken = nil
    registrationFailure = "registration"
    CSMCommunicationNotifications.recordRegistrationFailure(error)
    tokenContinuation?.resume(throwing: PushRegistrationError.registrationFailed)
    tokenContinuation = nil
  }

  func receiveRemoteNotification(_ userInfo: [AnyHashable: Any], interaction: Bool) {
    guard let payload = Self.sanitizedPayload(userInfo) else { return }
    emitBridgeEvent(
      type: "notifications.opened",
      payload: payload.merging(["interaction": interaction]) { current, _ in current }
    )
    if interaction, payload["roomId"] is String {
      NotificationCenter.default.post(name: .copNativeChatRequested, object: nil, userInfo: payload)
    }
  }

  func attachEventReceiver(
    ownerID: UUID,
    receiver: @escaping (String, [String: Any]) -> Void
  ) {
    eventReceiverOwnerID = ownerID
    eventReceiver = receiver
    flushPendingBridgeEvents()
  }

  func detachEventReceiver(ownerID: UUID) {
    guard eventReceiverOwnerID == ownerID else { return }
    eventReceiverOwnerID = nil
    eventReceiver = nil
  }

  private func emitBridgeEvent(type: String, payload: [String: Any]) {
    guard let eventReceiver else {
      if pendingBridgeEvents.count >= 16 { pendingBridgeEvents.removeFirst() }
      pendingBridgeEvents.append((type, payload))
      return
    }
    eventReceiver(type, payload)
  }

  private func flushPendingBridgeEvents() {
    guard let eventReceiver else { return }
    let events = pendingBridgeEvents
    pendingBridgeEvents.removeAll(keepingCapacity: true)
    for (type, payload) in events {
      eventReceiver(type, payload)
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let payload = notification.request.content.userInfo
    let completion = NotificationCompletionBox(completionHandler)
    Task { @MainActor in
      CSMCommunicationNotifications.receiveForegroundNotification(payload)
      await CSMCommunicationNotifications.processPendingNotifications()
      self.receiveRemoteNotification(payload, interaction: false)
      completion([.banner, .sound, .badge])
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = response.notification.request.content.userInfo
    let actionIdentifier = response.actionIdentifier
    let responseText = (response as? UNTextInputNotificationResponse)?.userText
    let completion = NotificationCompletionBox<Void> { _ in completionHandler() }
    Task { @MainActor in
      CSMCommunicationNotifications.receiveNotificationResponse(
        payload,
        actionIdentifier: actionIdentifier,
        responseText: responseText
      )
      await CSMCommunicationNotifications.processPendingNotifications()
      self.receiveRemoteNotification(
        payload,
        interaction: Self.shouldOpenNativeChat(for: actionIdentifier)
      )
      completion(())
    }
  }

  static func shouldOpenNativeChat(for actionIdentifier: String) -> Bool {
    switch actionIdentifier {
    case UNNotificationDefaultActionIdentifier, "CSM_OPEN", "CSM_REPLY":
      true
    default:
      false
    }
  }

  private var appInstanceID: String {
    let key = "cz.zeleznalady.csm.app-instance-id"
    if let value = UserDefaults.standard.string(forKey: key), UUID(uuidString: value) != nil {
      return value
    }
    let value = UUID().uuidString.lowercased()
    UserDefaults.standard.set(value, forKey: key)
    return value
  }

  private func currentDeviceToken() async throws -> String {
    if let deviceToken { return deviceToken }
    guard tokenContinuation == nil else { throw PushRegistrationError.registrationPending }
    UIApplication.shared.registerForRemoteNotifications()
    return try await withCheckedThrowingContinuation { continuation in
      tokenContinuation = continuation
    }
  }

  private static func statusPayload(
    _ settings: UNNotificationSettings, registered: Bool, failed: Bool
  ) -> [String: Any] {
    [
      "authorization": authorization(settings.authorizationStatus),
      "alert": setting(settings.alertSetting),
      "sound": setting(settings.soundSetting),
      "badge": setting(settings.badgeSetting),
      "timeSensitive": setting(settings.timeSensitiveSetting),
      "criticalAlert": setting(settings.criticalAlertSetting),
      "remoteRegistered": registered,
      "registrationFailed": failed,
    ]
  }

  private static func authorization(_ value: UNAuthorizationStatus) -> String {
    switch value {
    case .notDetermined: "notDetermined"
    case .denied: "denied"
    case .authorized: "authorized"
    case .provisional: "provisional"
    case .ephemeral: "ephemeral"
    @unknown default: "unknown"
    }
  }

  private static func setting(_ value: UNNotificationSetting) -> String {
    switch value {
    case .enabled: "enabled"
    case .disabled: "disabled"
    case .notSupported: "notSupported"
    @unknown default: "unknown"
    }
  }

  private static func sanitizedPayload(_ userInfo: [AnyHashable: Any]) -> [String: Any]? {
    let allowed = ["notificationId", "eventId", "category", "route", "roomId", "callId"]
    var result: [String: Any] = [:]
    for key in allowed {
      guard let value = userInfo[key] as? String, !value.isEmpty, value.count <= 512 else {
        continue
      }
      if key == "route" && !value.hasPrefix("/") { continue }
      result[key] = value
    }
    return result.isEmpty ? nil : result
  }
}

enum PushRegistrationError: Error {
  case invalidRequest
  case registrationFailed
  case registrationPending
  case serverRejected
}

final class COPMobileAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    _ = PushNotificationService.shared
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor in PushNotificationService.shared.recordDeviceToken(deviceToken) }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    Task { @MainActor in PushNotificationService.shared.recordRegistrationFailure(error) }
  }

  func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    let completion = NotificationCompletionBox(completionHandler)
    Task { @MainActor in
      CSMCommunicationNotifications.receiveBackgroundNotification(userInfo)
      await CSMCommunicationNotifications.processPendingNotifications()
      PushNotificationService.shared.receiveRemoteNotification(userInfo, interaction: false)
      completion(.newData)
    }
  }
}
