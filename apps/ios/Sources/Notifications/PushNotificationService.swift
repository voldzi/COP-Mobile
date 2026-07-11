import Foundation
import UIKit
@preconcurrency import UserNotifications

@MainActor
protocol PushNotificationProviding: AnyObject {
  var deviceToken: String? { get }
  var eventReceiver: ((String, [String: Any]) -> Void)? { get set }
  func status() async -> [String: Any]
  func requestAuthorization() async -> [String: Any]
  func registrationContext() -> [String: Any]
  func registerRemote(ticket: String, messagingBaseURL: String) async throws -> [String: Any]
  func recordDeviceToken(_ data: Data)
  func recordRegistrationFailure(_ error: any Error)
  func receiveRemoteNotification(_ userInfo: [AnyHashable: Any], interaction: Bool)
}

@MainActor
final class PushNotificationService: NSObject, PushNotificationProviding, UNUserNotificationCenterDelegate {
  static let shared = PushNotificationService()

  private let center = UNUserNotificationCenter.current()
  private(set) var deviceToken: String?
  private var registrationFailure: String?
  private var tokenContinuation: CheckedContinuation<String, any Error>?
  var eventReceiver: ((String, [String: Any]) -> Void)?

  private override init() {
    super.init()
    center.delegate = self
    VoiceCallService.shared.eventReceiver = { [weak self] type, payload in
      self?.eventReceiver?(type, payload)
    }
    registerCategories()
  }

  func status() async -> [String: Any] {
    let settings = await center.notificationSettings()
    return Self.statusPayload(settings, registered: deviceToken != nil, failed: registrationFailure != nil)
  }

  func requestAuthorization() async -> [String: Any] {
    do {
      _ = try await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
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
      "capabilities": ["e2ee": true, "criticalAlerts": false, "liveActivities": false, "voip": true],
      "deviceToken": token,
      "voipDeviceToken": voipToken,
      "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
      "platform": "ios",
      "preferences": ["categories": ["message.direct", "message.voice_call", "safety.alert", "system"]],
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
    tokenContinuation?.resume(returning: deviceToken!)
    tokenContinuation = nil
  }

  func recordRegistrationFailure(_ error: any Error) {
    deviceToken = nil
    registrationFailure = "registration"
    tokenContinuation?.resume(throwing: PushRegistrationError.registrationFailed)
    tokenContinuation = nil
  }

  func receiveRemoteNotification(_ userInfo: [AnyHashable: Any], interaction: Bool) {
    guard let payload = Self.sanitizedPayload(userInfo) else { return }
    eventReceiver?("notifications.opened", payload.merging(["interaction": interaction]) { current, _ in current })
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let payload = notification.request.content.userInfo
    Task { @MainActor in self.receiveRemoteNotification(payload, interaction: false) }
    completionHandler([.banner, .sound, .badge])
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let payload = response.notification.request.content.userInfo
    Task { @MainActor in self.receiveRemoteNotification(payload, interaction: true) }
    completionHandler()
  }

  private func registerCategories() {
    let open = UNNotificationAction(identifier: "OPEN", title: "Otevřít", options: [.foreground])
    center.setNotificationCategories([
      UNNotificationCategory(identifier: "CSM_SYSTEM", actions: [open], intentIdentifiers: []),
      UNNotificationCategory(identifier: "CSM_SAFETY_ALERT", actions: [open], intentIdentifiers: []),
      UNNotificationCategory(identifier: "CSM_CHAT", actions: [open], intentIdentifiers: []),
    ])
  }

  private var appInstanceID: String {
    let key = "cz.zeleznalady.csm.app-instance-id"
    if let value = UserDefaults.standard.string(forKey: key), UUID(uuidString: value) != nil { return value }
    let value = UUID().uuidString.lowercased()
    UserDefaults.standard.set(value, forKey: key)
    return value
  }

  private func currentDeviceToken() async throws -> String {
    if let deviceToken { return deviceToken }
    guard tokenContinuation == nil else { throw PushRegistrationError.registrationPending }
    UIApplication.shared.registerForRemoteNotifications()
    return try await withCheckedThrowingContinuation { continuation in tokenContinuation = continuation }
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
      guard let value = userInfo[key] as? String, !value.isEmpty, value.count <= 512 else { continue }
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
    Task { @MainActor in
      PushNotificationService.shared.receiveRemoteNotification(userInfo, interaction: false)
      completionHandler(.newData)
    }
  }
}
