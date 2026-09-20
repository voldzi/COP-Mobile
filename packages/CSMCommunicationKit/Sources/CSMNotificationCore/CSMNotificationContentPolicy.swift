import CryptoKit
import Foundation

/// Privacy-preserving presentation for a metadata-only CSM notification.
///
/// The policy deliberately never accepts a server-provided title or body. E2EE
/// message text belongs to the Matrix crypto store and must not be copied into
/// APNs, extension logs or the system notification database.
public struct CSMNotificationPresentation: Equatable, Sendable {
    public let title: String
    public let body: String
    public let categoryIdentifier: String
    public let threadIdentifier: String?
    public let targetContentIdentifier: String?
    public let sanitizedUserInfo: [String: String]

    public init(
        title: String,
        body: String,
        categoryIdentifier: String,
        threadIdentifier: String?,
        targetContentIdentifier: String?,
        sanitizedUserInfo: [String: String]
    ) {
        self.title = title
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier
        self.targetContentIdentifier = targetContentIdentifier
        self.sanitizedUserInfo = sanitizedUserInfo
    }
}

public enum CSMNotificationContentPolicy {
    private static let maximumValueLength = 512
    private static let canonicalKeys: [(canonical: String, aliases: [String])] = [
        ("notificationId", ["notificationId", "notification_id"]),
        ("eventId", ["eventId", "event_id", "messageId", "message_id", "matrixEventId", "matrix_event_id"]),
        ("roomId", ["roomId", "room_id", "matrixRoomId", "matrix_room_id"]),
        ("alertId", ["alertId", "alert_id"]),
        ("reportId", ["reportId", "report_id"]),
        ("callId", ["callId", "call_id"]),
        ("deepLink", ["deepLink", "deeplink", "deep_link", "url"]),
        ("route", ["route"]),
        ("category", ["category", "notificationCategory", "notification_category", "type"]),
        ("expiresAt", ["expiresAt", "expires_at"])
    ]

    public static func presentation(
        userInfo: [AnyHashable: Any],
        preferredLanguage: String? = Locale.preferredLanguages.first
    ) -> CSMNotificationPresentation {
        var sanitized: [String: String] = [:]
        for item in canonicalKeys {
            guard let value = firstString(for: item.aliases, in: userInfo) else { continue }
            if item.canonical == "route", !value.hasPrefix("/") { continue }
            if item.canonical == "deepLink", !isAllowedDeepLink(value) { continue }
            sanitized[item.canonical] = value
        }

        if sanitized["category"] == nil,
           let aps = userInfo["aps"] as? [String: Any],
           let value = normalizedString(aps["category"]) {
            sanitized["category"] = value
        }

        let kind = notificationKind(sanitized["category"])
        let copy = localizedCopy(for: kind, language: preferredLanguage)
        let roomIdentifier = sanitized["roomId"].map(stableOpaqueIdentifier)
        let targetIdentifier = roomIdentifier ?? sanitized["alertId"].map(stableOpaqueIdentifier)

        return CSMNotificationPresentation(
            title: copy.title,
            body: copy.body,
            categoryIdentifier: kind.systemCategoryIdentifier,
            threadIdentifier: roomIdentifier.map { "room.\($0)" },
            targetContentIdentifier: targetIdentifier,
            sanitizedUserInfo: sanitized
        )
    }

    private enum NotificationKind {
        case safety
        case directMessage
        case groupMessage
        case system

        var systemCategoryIdentifier: String {
            switch self {
            case .safety: "CSM_SAFETY_ALERT"
            case .directMessage, .groupMessage: "CSM_CHAT"
            case .system: "CSM_SYSTEM"
            }
        }
    }

    private static func notificationKind(_ rawValue: String?) -> NotificationKind {
        let value = rawValue?
            .lowercased()
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".") ?? ""
        if value.contains("safety") || value == "alert" || value == "risk" { return .safety }
        if value.contains("message.direct") || value == "direct" || value == "dm" { return .directMessage }
        if value.contains("message") || value.contains("chat") || value == "group" { return .groupMessage }
        return .system
    }

    private static func localizedCopy(
        for kind: NotificationKind,
        language: String?
    ) -> (title: String, body: String) {
        let isCzech = language?.lowercased().hasPrefix("cs") == true
        return switch (kind, isCzech) {
        case (.safety, true):
            ("Bezpečnostní upozornění", "Otevřete COP pro ověřené podrobnosti a doporučený postup.")
        case (.directMessage, true):
            ("Nová zabezpečená zpráva", "Otevřete komunikaci COP pro zobrazení obsahu.")
        case (.groupMessage, true):
            ("Nová zpráva v komunikaci", "Otevřete komunikaci COP pro zobrazení obsahu.")
        case (.system, true):
            ("Aktualizace COP", "Otevřete aplikaci pro aktuální informace.")
        case (.safety, false):
            ("Safety alert", "Open COP for verified details and recommended actions.")
        case (.directMessage, false):
            ("New secure message", "Open COP communication to view the content.")
        case (.groupMessage, false):
            ("New communication message", "Open COP communication to view the content.")
        case (.system, false):
            ("COP update", "Open the app for current information.")
        }
    }

    private static func firstString(
        for keys: [String],
        in userInfo: [AnyHashable: Any]
    ) -> String? {
        for key in keys {
            if let value = normalizedString(userInfo[key]) { return value }
        }
        return nil
    }

    private static func normalizedString(_ raw: Any?) -> String? {
        let value: String
        if let string = raw as? String {
            value = string
        } else if let number = raw as? NSNumber {
            value = number.stringValue
        } else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumValueLength else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private static func isAllowedDeepLink(_ value: String) -> Bool {
        guard let url = URL(string: value), url.user == nil, url.password == nil else { return false }
        if url.scheme?.lowercased() == "csm" { return true }
        return url.scheme?.lowercased() == "https" && url.host?.lowercased() == "cop.zeleznalady.cz"
    }

    private static func stableOpaqueIdentifier(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
