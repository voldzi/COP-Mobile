import Foundation

extension Notification.Name {
    static let csmNavigationDestinationRequested = Notification.Name(
        "cz.zeleznalady.csm.navigationDestinationRequested"
    )
    static let csmFieldReadinessDetailRequested = Notification.Name(
        "cz.zeleznalady.csm.fieldReadinessDetailRequested"
    )
    public static let csmVoiceCallTimelineChanged = Notification.Name(
        "cz.zeleznalady.csm.voiceCallTimelineChanged"
    )
}

/// Process-safe APNs integration for applications embedding
/// `CSMCommunicationKit`.
///
/// iOS exposes one `UNUserNotificationCenterDelegate` per process. The host
/// remains that delegate and forwards the relevant callbacks here. This keeps
/// Matrix pusher registration, notification actions and native navigation in
/// sync without replacing the host application's delegate.
public enum CSMCommunicationNotifications {
    @MainActor
    public static func prepareHostApplication() {
        PushNotificationManager.shared.prepareForHostApplication()
    }

    @MainActor
    public static func recordDeviceToken(_ deviceToken: Data) {
        PushNotificationManager.shared.recordDeviceToken(deviceToken)
        CSMCommunicationRuntime.shared.scheduleDeviceRegistrationRefresh()
    }

    /// Tells the communication runtime that the host application's PushKit
    /// token became available or changed. The runtime reads the current value
    /// through the provider supplied to `CSMCommunicationHost` and refreshes
    /// the single native CSM Messaging device record.
    @MainActor
    public static func recordVoIPDeviceTokenUpdate() {
        NotificationCenter.default.post(name: .csmVoIPPushDeviceTokenUpdated, object: nil)
        CSMCommunicationRuntime.shared.scheduleDeviceRegistrationRefresh()
    }

    @MainActor
    public static func recordRegistrationFailure(_ error: any Error) {
        PushNotificationManager.shared.recordRegistrationFailure(error)
        CSMCommunicationRuntime.shared.scheduleDeviceRegistrationRefresh()
    }

    @MainActor
    public static func receiveBackgroundNotification(_ userInfo: [AnyHashable: Any]) {
        PushNotificationManager.shared.recordBackgroundNotification(userInfo: userInfo)
    }

    @MainActor
    public static func receiveForegroundNotification(_ userInfo: [AnyHashable: Any]) {
        PushNotificationManager.shared.recordForegroundNotification(userInfo: userInfo)
    }

    @MainActor
    public static func receiveNotificationResponse(
        _ userInfo: [AnyHashable: Any],
        actionIdentifier: String,
        responseText: String? = nil
    ) {
        PushNotificationManager.shared.recordNotificationResponse(
            userInfo: userInfo,
            actionIdentifier: actionIdentifier,
            responseText: responseText
        )
    }

    /// Starts the shared communication runtime when necessary and handles all
    /// queued metadata-only notifications that are eligible for the current
    /// authenticated session. If authentication or bootstrap is not ready, the
    /// bounded queue remains intact and is drained after readiness instead.
    ///
    /// Host applications should await this method before completing an iOS
    /// notification callback so actions such as reply and mark-as-read do not
    /// depend on `CSMCommunicationHost` already being mounted.
    @MainActor
    public static func processPendingNotifications() async {
        await CSMCommunicationRuntime.shared.processPendingNotifications()
    }

    /// Restores the native communication session and refreshes the APNs +
    /// PushKit device record without requiring the chat screen or a hidden web
    /// session to be open. The method never starts interactive authentication.
    @MainActor
    public static func prepareDeviceRegistration(
        voipDeviceTokenProvider: (@MainActor @Sendable () async -> String?)?
    ) async {
        let runtime = CSMCommunicationRuntime.shared
        runtime.configureVoIPDeviceTokenProvider(voipDeviceTokenProvider)
        await runtime.prepare(expectedSubjectID: nil, allowInteractiveSignIn: false)
    }
}
