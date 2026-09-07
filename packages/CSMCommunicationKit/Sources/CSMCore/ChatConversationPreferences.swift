import Foundation

/// Local, non-content conversation presentation preferences.
///
/// The model intentionally stores only conversation identifiers and opaque
/// metadata snapshots. Message bodies, attachment names, ciphertext, and Matrix
/// event payloads must stay in Matrix/E2EE storage.
struct ChatConversationPreferences: Codable, Equatable, Sendable {
    static let farFutureMuteDate = Date(timeIntervalSince1970: 4_102_444_800)
    static let empty = ChatConversationPreferences()

    var hiddenByConversationId: [String: String]
    var manuallyUnreadConversationIds: [String]
    var mutedUntilByConversationId: [String: Date]
    var pinnedConversationIds: [String]
    var readOverrideByConversationId: [String: String]
    var hiddenMessageIdsByConversationId: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case hiddenByConversationId
        case manuallyUnreadConversationIds
        case mutedUntilByConversationId
        case pinnedConversationIds
        case readOverrideByConversationId
        case hiddenMessageIdsByConversationId
    }

    init(
        hiddenByConversationId: [String: String] = [:],
        manuallyUnreadConversationIds: [String] = [],
        mutedUntilByConversationId: [String: Date] = [:],
        pinnedConversationIds: [String] = [],
        readOverrideByConversationId: [String: String] = [:],
        hiddenMessageIdsByConversationId: [String: [String]] = [:]
    ) {
        self.hiddenByConversationId = hiddenByConversationId
        self.manuallyUnreadConversationIds = manuallyUnreadConversationIds
        self.mutedUntilByConversationId = mutedUntilByConversationId
        self.pinnedConversationIds = pinnedConversationIds
        self.readOverrideByConversationId = readOverrideByConversationId
        self.hiddenMessageIdsByConversationId = hiddenMessageIdsByConversationId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenByConversationId = try container.decodeIfPresent([String: String].self, forKey: .hiddenByConversationId) ?? [:]
        manuallyUnreadConversationIds = try container.decodeIfPresent([String].self, forKey: .manuallyUnreadConversationIds) ?? []
        mutedUntilByConversationId = try container.decodeIfPresent([String: Date].self, forKey: .mutedUntilByConversationId) ?? [:]
        pinnedConversationIds = try container.decodeIfPresent([String].self, forKey: .pinnedConversationIds) ?? []
        readOverrideByConversationId = try container.decodeIfPresent([String: String].self, forKey: .readOverrideByConversationId) ?? [:]
        hiddenMessageIdsByConversationId = try container.decodeIfPresent([String: [String]].self, forKey: .hiddenMessageIdsByConversationId) ?? [:]
    }

    var normalized: Self {
        var copy = self
        copy.pinnedConversationIds = Self.uniqueNonEmptyIds(copy.pinnedConversationIds)
        copy.manuallyUnreadConversationIds = Self.uniqueNonEmptyIds(copy.manuallyUnreadConversationIds)
        copy.hiddenByConversationId = Self.normalizedSnapshots(copy.hiddenByConversationId)
        copy.readOverrideByConversationId = Self.normalizedSnapshots(copy.readOverrideByConversationId)
        copy.hiddenMessageIdsByConversationId = copy.hiddenMessageIdsByConversationId.reduce(into: [:]) { result, item in
            let conversationId = Self.normalizedId(item.key)
            let messageIds = Self.uniqueNonEmptyIds(item.value)
            guard !conversationId.isEmpty, !messageIds.isEmpty else { return }
            result[conversationId] = Array(messageIds.prefix(500))
        }
        copy.mutedUntilByConversationId = copy.mutedUntilByConversationId.reduce(into: [:]) { result, item in
            let key = item.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            result[key] = item.value
        }
        return copy
    }

    func isPinned(_ conversationId: String) -> Bool {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return false }
        return pinnedConversationIds.contains(id)
    }

    func isMuted(_ conversationId: String, now: Date = .now) -> Bool {
        let id = Self.normalizedId(conversationId)
        guard let mutedUntil = mutedUntilByConversationId[id] else { return false }
        return mutedUntil > now
    }

    func isManuallyUnread(_ conversationId: String) -> Bool {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return false }
        return manuallyUnreadConversationIds.contains(id)
    }

    func hiddenSnapshotMatches(conversationId: String, snapshot: String) -> Bool {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return false }
        return hiddenByConversationId[id] == snapshot
    }

    func readOverrideMatches(conversationId: String, snapshot: String) -> Bool {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return false }
        return readOverrideByConversationId[id] == snapshot
    }

    func isMessageHidden(conversationId: String, messageId: String) -> Bool {
        let conversationId = Self.normalizedId(conversationId)
        let messageId = Self.normalizedId(messageId)
        guard !conversationId.isEmpty, !messageId.isEmpty else { return false }
        return hiddenMessageIdsByConversationId[conversationId, default: []].contains(messageId)
    }

    func settingPinned(_ conversationId: String, enabled: Bool, limit: Int = 12) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        copy.pinnedConversationIds.removeAll { $0 == id }
        if enabled {
            copy.pinnedConversationIds.insert(id, at: 0)
            copy.pinnedConversationIds = Array(copy.pinnedConversationIds.prefix(max(1, limit)))
        }
        return copy
    }

    func movingPinnedConversation(_ conversationId: String, toIndex targetIndex: Int) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        guard let originalIndex = copy.pinnedConversationIds.firstIndex(of: id) else { return copy }

        copy.pinnedConversationIds.remove(at: originalIndex)
        var insertionIndex = max(0, min(targetIndex, copy.pinnedConversationIds.count))
        if originalIndex < targetIndex {
            insertionIndex = max(0, insertionIndex - 1)
        }
        copy.pinnedConversationIds.insert(id, at: insertionIndex)
        return copy
    }

    func settingMuted(_ conversationId: String, until mutedUntil: Date?) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        if let mutedUntil {
            copy.mutedUntilByConversationId[id] = mutedUntil
        } else {
            copy.mutedUntilByConversationId.removeValue(forKey: id)
        }
        return copy
    }

    func settingManualUnread(_ conversationId: String, enabled: Bool) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        copy.manuallyUnreadConversationIds.removeAll { $0 == id }
        if enabled {
            copy.manuallyUnreadConversationIds.insert(id, at: 0)
            copy.readOverrideByConversationId.removeValue(forKey: id)
        }
        return copy
    }

    func settingReadOverride(_ conversationId: String, snapshot: String?) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        copy.manuallyUnreadConversationIds.removeAll { $0 == id }
        if let snapshot, !snapshot.isEmpty {
            copy.readOverrideByConversationId[id] = snapshot
        } else {
            copy.readOverrideByConversationId.removeValue(forKey: id)
        }
        return copy
    }

    func settingMessageHidden(conversationId: String, messageId: String, enabled: Bool) -> Self {
        let conversationId = Self.normalizedId(conversationId)
        let messageId = Self.normalizedId(messageId)
        guard !conversationId.isEmpty, !messageId.isEmpty else { return normalized }
        var copy = normalized
        var messageIds = copy.hiddenMessageIdsByConversationId[conversationId, default: []]
        messageIds.removeAll { $0 == messageId }
        if enabled {
            messageIds.insert(messageId, at: 0)
            messageIds = Array(messageIds.prefix(500))
        }
        if messageIds.isEmpty {
            copy.hiddenMessageIdsByConversationId.removeValue(forKey: conversationId)
        } else {
            copy.hiddenMessageIdsByConversationId[conversationId] = messageIds
        }
        return copy
    }

    func settingHidden(_ conversationId: String, snapshot: String?) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        if let snapshot, !snapshot.isEmpty {
            copy.hiddenByConversationId[id] = snapshot
        } else {
            copy.hiddenByConversationId.removeValue(forKey: id)
        }
        copy.manuallyUnreadConversationIds.removeAll { $0 == id }
        return copy
    }

    func removingConversationPresentation(_ conversationId: String) -> Self {
        let id = Self.normalizedId(conversationId)
        guard !id.isEmpty else { return normalized }
        var copy = normalized
        copy.hiddenByConversationId.removeValue(forKey: id)
        copy.manuallyUnreadConversationIds.removeAll { $0 == id }
        copy.mutedUntilByConversationId.removeValue(forKey: id)
        copy.pinnedConversationIds.removeAll { $0 == id }
        copy.readOverrideByConversationId.removeValue(forKey: id)
        copy.hiddenMessageIdsByConversationId.removeValue(forKey: id)
        return copy
    }

    static func snapshot(for conversation: Conversation) -> String {
        [
            normalizedId(conversation.conversationId),
            conversation.type.rawValue,
            conversation.matrix?.roomId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            conversation.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            "\(conversation.memberCount)",
            "\(conversation.mapLinkCount)",
            "\(conversation.unreadCount)",
            timestamp(conversation.lastActivityAt),
            timestamp(conversation.updatedAt)
        ].joined(separator: "|")
    }

    private static func uniqueNonEmptyIds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let id = normalizedId(value)
            guard !id.isEmpty, !seen.contains(id) else { return nil }
            seen.insert(id)
            return id
        }
    }

    private static func normalizedSnapshots(_ values: [String: String]) -> [String: String] {
        values.reduce(into: [:]) { result, item in
            let key = normalizedId(item.key)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { return }
            result[key] = value
        }
    }

    private static func normalizedId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timestamp(_ value: Date?) -> String {
        guard let value else { return "" }
        return "\(Int(value.timeIntervalSince1970.rounded()))"
    }
}
