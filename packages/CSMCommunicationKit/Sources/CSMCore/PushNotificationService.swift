import Foundation

#if os(iOS)
import UIKit
import UserNotifications
#endif

extension Notification.Name {
    static let csmPushDeviceTokenUpdated = Notification.Name("cz.zeleznalady.csm.pushDeviceTokenUpdated")
    static let csmVoIPPushDeviceTokenUpdated = Notification.Name(
        "cz.zeleznalady.csm.voipPushDeviceTokenUpdated"
    )
    static let csmPushRegistrationFailed = Notification.Name("cz.zeleznalady.csm.pushRegistrationFailed")
    static let csmPushNotificationReceived = Notification.Name("cz.zeleznalady.csm.pushNotificationReceived")
}

enum MobilePushAuthorization: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

struct MobilePushSnapshot: Codable, Equatable, Sendable {
    var authorization: MobilePushAuthorization
    var deviceToken: String?
    var environment: String
    var registrationRequestedAt: Date?
    var lastFailure: String?

    static let unavailable = MobilePushSnapshot(
        authorization: .unknown,
        deviceToken: nil,
        environment: "unavailable",
        registrationRequestedAt: nil,
        lastFailure: nil
    )

    var registration: MobilePushRegistration {
        MobilePushRegistration(
            token: deviceToken,
            environment: environment,
            authorization: authorization.rawValue,
            updatedAt: registrationRequestedAt ?? .now
        )
    }
}

@MainActor
protocol PushNotificationManaging: AnyObject {
    var currentSnapshot: MobilePushSnapshot { get }

    func prepareForRemoteNotifications() async -> MobilePushSnapshot
    func recordDeviceToken(_ deviceToken: Data)
    func recordRegistrationFailure(_ error: any Error)
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload)
    func updateApplicationBadgeCount(_ count: Int) async
}

extension PushNotificationManaging {
    func recordRemoteNotification(userInfo: [AnyHashable: Any]) {
        recordRemoteNotification(CSMRemoteNotificationPayload(userInfo: userInfo))
    }

    func updateApplicationBadgeCount(_ count: Int) async {}
}

#if os(iOS)
@MainActor
final class PushNotificationManager: NSObject, PushNotificationManaging, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()

    private let center = UNUserNotificationCenter.current()
    private var pendingRemoteNotifications: [CSMRemoteNotificationPayload] = []
    private(set) var currentSnapshot = MobilePushSnapshot(
        authorization: .notDetermined,
        deviceToken: nil,
        environment: PushNotificationManager.apnsEnvironment,
        registrationRequestedAt: nil,
        lastFailure: nil
    )

    private override init() {
        super.init()
        registerNotificationCategories()
    }

    /// Standalone CSM Mobile owns the notification-center delegate. Embedded
    /// hosts forward callbacks through `CSMCommunicationNotifications` instead
    /// so two SDKs never compete for this process-global delegate.
    func installAsNotificationCenterDelegate() {
        center.delegate = self
        registerNotificationCategories()
    }

    func prepareForHostApplication() {
        registerNotificationCategories()
    }

    func recordBackgroundNotification(userInfo: [AnyHashable: Any]) {
        recordRemoteNotification(
            CSMRemoteNotificationPayload(
                userInfo: userInfo,
                deliveryContext: .backgroundFetch
            )
        )
    }

    func recordForegroundNotification(userInfo: [AnyHashable: Any]) {
        let payload = CSMRemoteNotificationPayload(
            userInfo: userInfo,
            deliveryContext: .foregroundPresentation
        )
        emitForegroundFeedback(for: payload)
        recordRemoteNotification(payload)
    }

    func recordNotificationResponse(
        userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        responseText: String?
    ) {
        guard actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        let action = Self.responseAction(from: actionIdentifier)
        let payload = CSMRemoteNotificationPayload(
            userInfo: userInfo,
            deliveryContext: .userInteraction
        )
            .applying(action: action, responseText: responseText)
        recordRemoteNotification(payload)
    }

    func prepareForRemoteNotifications() async -> MobilePushSnapshot {
        registerNotificationCategories()
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            currentSnapshot.authorization = await currentAuthorization()
            currentSnapshot.registrationRequestedAt = .now
            currentSnapshot.lastFailure = nil
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            currentSnapshot.authorization = await currentAuthorization()
            currentSnapshot.registrationRequestedAt = .now
            currentSnapshot.lastFailure = error.localizedDescription
        }

        return currentSnapshot
    }

    func recordDeviceToken(_ deviceToken: Data) {
        currentSnapshot.deviceToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        currentSnapshot.registrationRequestedAt = .now
        currentSnapshot.lastFailure = nil
        NotificationCenter.default.post(name: .csmPushDeviceTokenUpdated, object: nil)
    }

    func recordRegistrationFailure(_ error: any Error) {
        currentSnapshot.registrationRequestedAt = .now
        currentSnapshot.lastFailure = error.localizedDescription
        NotificationCenter.default.post(name: .csmPushRegistrationFailed, object: nil)
    }

    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {
        if pendingRemoteNotifications.count >= 16 {
            pendingRemoteNotifications.removeFirst()
        }
        pendingRemoteNotifications.append(payload)
        NotificationCenter.default.post(
            name: .csmPushNotificationReceived,
            object: nil,
            userInfo: ["payload": payload]
        )
    }

    func claimRemoteNotification(_ payload: CSMRemoteNotificationPayload) -> Bool {
        guard let index = pendingRemoteNotifications.firstIndex(of: payload) else { return false }
        pendingRemoteNotifications.remove(at: index)
        return true
    }

    func takePendingRemoteNotifications() -> [CSMRemoteNotificationPayload] {
        let notifications = pendingRemoteNotifications
        pendingRemoteNotifications.removeAll(keepingCapacity: true)
        return notifications
    }

    func updateApplicationBadgeCount(_ count: Int) async {
        try? await center.setBadgeCount(max(0, count))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else {
            completionHandler()
            return
        }
        let action = Self.responseAction(from: response.actionIdentifier)
        let responseText = (response as? UNTextInputNotificationResponse)?.userText
        let payload = CSMRemoteNotificationPayload(
            userInfo: response.notification.request.content.userInfo,
            deliveryContext: .userInteraction
        )
            .applying(action: action, responseText: responseText)
        Task { @MainActor in
            recordRemoteNotification(payload)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let payload = CSMRemoteNotificationPayload(
            userInfo: notification.request.content.userInfo,
            deliveryContext: .foregroundPresentation
        )
        Task { @MainActor in
            emitForegroundFeedback(for: payload)
            recordRemoteNotification(payload)
        }
        completionHandler([.banner, .sound, .badge])
    }

    private func registerNotificationCategories() {
        let open = UNNotificationAction(
            identifier: CSMNotificationActionIdentifier.open,
            title: CSMLocalization.text("notification.action.open", fallback: "Otevřít"),
            options: [.foreground]
        )
        let acknowledge = UNNotificationAction(
            identifier: CSMNotificationActionIdentifier.acknowledge,
            title: CSMLocalization.text("notification.action.acknowledge", fallback: "Potvrdit"),
            options: [.foreground]
        )
        let markRead = UNNotificationAction(
            identifier: CSMNotificationActionIdentifier.markRead,
            title: CSMLocalization.text("notification.action.mark_read", fallback: "Přečtené"),
            options: []
        )
        let reply = UNTextInputNotificationAction(
            identifier: CSMNotificationActionIdentifier.reply,
            title: CSMLocalization.text("notification.action.reply", fallback: "Odpovědět"),
            options: [.foreground],
            textInputButtonTitle: CSMLocalization.text("notification.action.reply_send", fallback: "Odeslat"),
            textInputPlaceholder: CSMLocalization.text("notification.action.reply_placeholder", fallback: "Zpráva")
        )

        let safetyAlert = UNNotificationCategory(
            identifier: CSMNotificationCategoryIdentifier.safetyAlert,
            actions: [acknowledge, open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let chat = UNNotificationCategory(
            identifier: CSMNotificationCategoryIdentifier.chat,
            actions: [reply, markRead, open],
            intentIdentifiers: [],
            options: []
        )
        let system = UNNotificationCategory(
            identifier: CSMNotificationCategoryIdentifier.system,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([safetyAlert, chat, system])
    }

    private func emitForegroundFeedback(for payload: CSMRemoteNotificationPayload) {
        let isSafetyAlert = payload.category == .safetyAlert || {
            if case .mapAlert = payload.targetDeepLink {
                return true
            }
            return false
        }()
        guard isSafetyAlert else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    private nonisolated static func responseAction(from identifier: String) -> CSMRemoteNotificationAction? {
        guard identifier != UNNotificationDismissActionIdentifier else { return nil }
        return CSMRemoteNotificationAction(notificationResponseIdentifier: identifier)
    }

    private func currentAuthorization() async -> MobilePushAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    private static var apnsEnvironment: String {
        CSMAPNSEnvironmentResolver.current
    }
}
#else
@MainActor
final class PushNotificationManager: PushNotificationManaging {
    static let shared = PushNotificationManager()
    private(set) var currentSnapshot = MobilePushSnapshot.unavailable

    private init() {}

    func prepareForRemoteNotifications() async -> MobilePushSnapshot {
        currentSnapshot
    }

    func recordDeviceToken(_ deviceToken: Data) {}

    func recordRegistrationFailure(_ error: any Error) {
        currentSnapshot.lastFailure = error.localizedDescription
        NotificationCenter.default.post(name: .csmPushRegistrationFailed, object: nil)
    }

    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {
        NotificationCenter.default.post(
            name: .csmPushNotificationReceived,
            object: nil,
            userInfo: ["payload": payload]
        )
    }
}
#endif
