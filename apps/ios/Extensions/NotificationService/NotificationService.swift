import CSMNotificationCore
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        let presentation = CSMNotificationContentPolicy.presentation(userInfo: content.userInfo)
        content.title = presentation.title
        content.subtitle = ""
        content.body = presentation.body
        content.categoryIdentifier = presentation.categoryIdentifier
        content.threadIdentifier = presentation.threadIdentifier ?? ""
        content.targetContentIdentifier = presentation.targetContentIdentifier
        content.attachments = []
        content.userInfo = presentation.sanitizedUserInfo
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler, let bestAttemptContent else { return }
        let presentation = CSMNotificationContentPolicy.presentation(
            userInfo: bestAttemptContent.userInfo
        )
        bestAttemptContent.title = presentation.title
        bestAttemptContent.subtitle = ""
        bestAttemptContent.body = presentation.body
        bestAttemptContent.attachments = []
        bestAttemptContent.userInfo = presentation.sanitizedUserInfo
        contentHandler(bestAttemptContent)
    }
}
