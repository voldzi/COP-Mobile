import CryptoKit
import Foundation

enum CSMDeepLink: Equatable, Sendable {
    case mapAlert(alertId: String)
    case mapReport(reportId: String)
    case chatRoom(roomId: String)
    case message(messageId: String)
    case mobilePairing(code: String)

    init?(url: URL) {
        let scheme = url.scheme?.lowercased()
        let host = url.host(percentEncoded: false)
        let path = url.pathComponents.filter { $0 != "/" }

        if scheme == "https",
           host == "cop.zeleznalady.cz",
           path.count == 3,
           path[0] == "mobile",
           path[1] == "pair",
           let code = Self.normalizedPairingCode(path[2]) {
            self = .mobilePairing(code: code)
            return
        }

        guard scheme == "csm" else { return nil }

        if host == "pair",
           path.isEmpty,
           let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
            .flatMap(Self.normalizedPairingCode) {
            self = .mobilePairing(code: code)
            return
        }

        if host == "map",
           path.count == 2,
           path[0] == "alert",
           let alertId = Self.normalizedIdentifier(path[1]) {
            self = .mapAlert(alertId: alertId)
            return
        }

        if host == "map",
           path.count == 2,
           path[0] == "report",
           let reportId = Self.normalizedIdentifier(path[1]) {
            self = .mapReport(reportId: reportId)
            return
        }

        if host == "chat",
           path.count == 2,
           path[0] == "room",
           let roomId = Self.normalizedIdentifier(path[1]) {
            self = .chatRoom(roomId: roomId)
            return
        }

        if host == "message",
           path.count == 1,
           let messageId = Self.normalizedIdentifier(path[0]) {
            self = .message(messageId: messageId)
            return
        }

        return nil
    }

    var auditMetadata: [String: String] {
        switch self {
        case let .mapAlert(alertId):
            ["alertId": alertId]
        case let .mapReport(reportId):
            ["reportId": reportId]
        case let .chatRoom(roomId):
            ["roomId": roomId]
        case let .message(messageId):
            ["messageId": messageId]
        case let .mobilePairing(code):
            ["target": "mobilePairing", "pairingCodeHash": Self.auditHash(code)]
        }
    }

    var roomId: String? {
        if case let .chatRoom(roomId) = self {
            return roomId
        }
        return nil
    }

    var messageId: String? {
        if case let .message(messageId) = self {
            return messageId
        }
        return nil
    }

    private static func normalizedIdentifier(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    private static func normalizedPairingCode(_ value: String) -> String? {
        let decoded = value.removingPercentEncoding ?? value
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard (8...256).contains(trimmed.count) else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    private static func auditHash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct CSMRemoteNotificationPayload: Equatable, Sendable {
    var deepLink: URL?
    var alertId: String?
    var reportId: String?
    var roomId: String?
    var messageId: String?
    var category: CSMRemoteNotificationCategory?
    var action: CSMRemoteNotificationAction?
    var responseText: String?
    var deliveryContext: CSMRemoteNotificationDeliveryContext

    init(
        deepLink: URL? = nil,
        alertId: String? = nil,
        reportId: String? = nil,
        roomId: String? = nil,
        messageId: String? = nil,
        category: CSMRemoteNotificationCategory? = nil,
        action: CSMRemoteNotificationAction? = nil,
        responseText: String? = nil,
        deliveryContext: CSMRemoteNotificationDeliveryContext = .userInteraction
    ) {
        self.deepLink = deepLink
        self.alertId = alertId
        self.reportId = reportId
        self.roomId = roomId
        self.messageId = messageId
        self.category = category
        self.action = action
        self.responseText = responseText.flatMap(Self.normalizedResponseText)
        self.deliveryContext = deliveryContext
    }

    init(
        userInfo: [AnyHashable: Any],
        deliveryContext: CSMRemoteNotificationDeliveryContext = .userInteraction
    ) {
        let deepLinkString = Self.stringValue(for: ["deepLink", "deeplink", "deep_link", "url"], in: userInfo)
        self.deepLink = deepLinkString.flatMap(URL.init(string:))
        self.alertId = Self.stringValue(for: ["alertId", "alert_id"], in: userInfo)
        self.reportId = Self.stringValue(for: ["reportId", "report_id"], in: userInfo)
        self.roomId = Self.stringValue(for: ["roomId", "room_id", "matrixRoomId", "matrix_room_id"], in: userInfo)
        self.messageId = Self.stringValue(for: ["messageId", "message_id", "eventId", "event_id", "matrixEventId", "matrix_event_id"], in: userInfo)
        self.category = Self.categoryValue(in: userInfo)
        self.action = Self.actionValue(in: userInfo)
        self.responseText = nil
        self.deliveryContext = deliveryContext
    }

    var targetDeepLink: CSMDeepLink? {
        if let deepLink, let parsed = CSMDeepLink(url: deepLink) {
            return parsed
        }
        if let alertId, !alertId.isEmpty {
            return .mapAlert(alertId: alertId)
        }
        if let reportId, !reportId.isEmpty {
            return .mapReport(reportId: reportId)
        }
        if let roomId, !roomId.isEmpty {
            return .chatRoom(roomId: roomId)
        }
        if let messageId, !messageId.isEmpty {
            return .message(messageId: messageId)
        }
        return nil
    }

    var auditMetadata: [String: String] {
        var metadata = targetDeepLink?.auditMetadata ?? [:]
        if let category {
            metadata["category"] = category.rawValue
        }
        if let action {
            metadata["action"] = action.rawValue
        }
        return metadata
    }

    func applying(
        action: CSMRemoteNotificationAction?,
        responseText: String? = nil
    ) -> CSMRemoteNotificationPayload {
        guard let action else { return self }
        var copy = self
        copy.action = action
        copy.responseText = responseText.flatMap(Self.normalizedResponseText)
        return copy
    }

    func applying(deliveryContext: CSMRemoteNotificationDeliveryContext) -> CSMRemoteNotificationPayload {
        var copy = self
        copy.deliveryContext = deliveryContext
        return copy
    }

    private static func stringValue(for keys: [String], in userInfo: [AnyHashable: Any]) -> String? {
        for key in keys {
            if let value = userInfo[key] {
                return normalizedString(value)
            }
        }
        return nil
    }

    private static func categoryValue(in userInfo: [AnyHashable: Any]) -> CSMRemoteNotificationCategory? {
        if let direct = stringValue(for: ["category", "notificationCategory", "notification_category", "type"], in: userInfo),
           let category = CSMRemoteNotificationCategory(payloadValue: direct) {
            return category
        }
        guard
            let aps = userInfo["aps"] as? [String: Any],
            let apsCategory = stringValue(
                for: ["category"],
                in: Dictionary(uniqueKeysWithValues: aps.map { (AnyHashable($0.key), $0.value) })
            )
        else {
            return nil
        }
        return CSMRemoteNotificationCategory(payloadValue: apsCategory)
    }

    private static func actionValue(in userInfo: [AnyHashable: Any]) -> CSMRemoteNotificationAction? {
        guard let action = stringValue(for: ["action", "actionId", "action_id"], in: userInfo) else {
            return nil
        }
        return CSMRemoteNotificationAction(payloadValue: action)
    }

    private static func normalizedString(_ value: Any) -> String? {
        if let string = value as? String {
            return normalizedPayloadString(string)
        }
        if let number = value as? NSNumber {
            return normalizedPayloadString(number.stringValue)
        }
        return nil
    }

    private static func normalizedPayloadString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    private static func normalizedResponseText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 4_000 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ $0.value != 0 }) else { return nil }
        return trimmed
    }
}

enum CSMRemoteNotificationDeliveryContext: String, Codable, Equatable, Sendable {
    /// User tapped the notification or selected one of its foreground actions.
    case userInteraction = "user_interaction"
    /// APNs was received while the app was already foregrounded.
    case foregroundPresentation = "foreground_presentation"
    /// iOS woke the app in the background to refresh data from a minimal payload.
    case backgroundFetch = "background_fetch"

    var shouldNavigate: Bool {
        self == .userInteraction
    }
}

enum CSMNotificationActionIdentifier {
    static let open = "CSM_OPEN"
    static let acknowledge = "CSM_ACKNOWLEDGE"
    static let markRead = "CSM_MARK_READ"
    static let reply = "CSM_REPLY"
}

enum CSMNotificationCategoryIdentifier {
    static let safetyAlert = "CSM_SAFETY_ALERT"
    static let chat = "CSM_CHAT"
    static let system = "CSM_SYSTEM"
}

enum CSMRemoteNotificationAction: String, Codable, Equatable, Sendable {
    case open
    case acknowledge
    case markRead = "mark_read"
    case reply

    init?(payloadValue: String) {
        let normalized = payloadValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")

        switch normalized {
        case "open", "csm.open":
            self = .open
        case "acknowledge", "ack", "confirm", "csm.acknowledge":
            self = .acknowledge
        case "mark.read", "read", "markread", "csm.mark.read":
            self = .markRead
        case "reply", "respond", "text.reply", "quick.reply", "csm.reply":
            self = .reply
        default:
            return nil
        }
    }

    init?(notificationResponseIdentifier: String) {
        switch notificationResponseIdentifier {
        case CSMNotificationActionIdentifier.open:
            self = .open
        case CSMNotificationActionIdentifier.acknowledge:
            self = .acknowledge
        case CSMNotificationActionIdentifier.markRead:
            self = .markRead
        case CSMNotificationActionIdentifier.reply:
            self = .reply
        case "com.apple.UNNotificationDefaultActionIdentifier":
            self = .open
        default:
            return nil
        }
    }
}

enum CSMRemoteNotificationCategory: String, Codable, Equatable, Sendable {
    case safetyAlert = "safety.alert"
    case directMessage = "message.direct"
    case groupMessage = "message.group"
    case system = "system"

    init?(payloadValue: String) {
        let normalized = payloadValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-", with: ".")

        switch normalized {
        case "safety.alert", "safety", "alert", "risk", "csm.safety.alert":
            self = .safetyAlert
        case "message.direct", "direct.message", "direct", "dm", "csm.message.direct":
            self = .directMessage
        case "message.group", "group.message", "group", "chat", "message", "csm.chat", "csm.message.group":
            self = .groupMessage
        case "system", "csm.system":
            self = .system
        default:
            return nil
        }
    }
}

enum CSMNavigationDestination: Equatable, Sendable {
    case conversations
    case map
    case alerts
    case reports
    case settings
}
