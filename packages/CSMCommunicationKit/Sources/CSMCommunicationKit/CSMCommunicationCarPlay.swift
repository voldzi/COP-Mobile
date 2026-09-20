import Foundation

/// A privacy-minimised conversation representation for voice and CarPlay surfaces.
/// Authentication tokens, Matrix room keys and transport endpoints never leave the kit.
public struct CSMCarPlayConversation: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let lastMessagePreview: String?
    public let lastActivityAt: Date?
    public let unreadCount: Int
    public let isPinned: Bool
    public let isMuted: Bool

    public init(
        id: String,
        title: String,
        lastMessagePreview: String?,
        lastActivityAt: Date?,
        unreadCount: Int,
        isPinned: Bool,
        isMuted: Bool
    ) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.lastActivityAt = lastActivityAt
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isMuted = isMuted
    }
}

public struct CSMCarPlayMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public let conversationID: String
    public let senderID: String
    public let senderDisplayName: String
    public let body: String
    public let sentAt: Date
    public let isOwnMessage: Bool

    public init(
        id: String,
        conversationID: String,
        senderID: String,
        senderDisplayName: String,
        body: String,
        sentAt: Date,
        isOwnMessage: Bool
    ) {
        self.id = id
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.sentAt = sentAt
        self.isOwnMessage = isOwnMessage
    }
}

public enum CSMCarPlayCommunicationError: LocalizedError, Sendable {
    case authenticationRequired
    case conversationNotFound
    case emptyMessage
    case sendFailed

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Pro použití chatu v autě se nejprve přihlaste v aplikaci Jízda."
        case .conversationNotFound:
            "Konverzace už není dostupná."
        case .emptyMessage:
            "Zpráva je prázdná."
        case .sendFailed:
            "Zprávu se nepodařilo bezpečně odeslat."
        }
    }
}

public extension CSMCommunicationRuntime {
    /// Returns only user-facing metadata suitable for a glanceable in-car list.
    func carPlayConversations(limit: Int = 8) async throws -> [CSMCarPlayConversation] {
        await startIfNeeded()
        guard model.authState == .signedIn else {
            throw CSMCarPlayCommunicationError.authenticationRequired
        }

        return model.visibleConversations
            .sorted {
                ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
            }
            .prefix(max(0, limit))
            .map { conversation in
                CSMCarPlayConversation(
                    id: conversation.conversationId,
                    title: conversation.title,
                    lastMessagePreview: conversation.lastActivityPreview,
                    lastActivityAt: conversation.lastActivityAt,
                    unreadCount: model.visibleUnreadCount(for: conversation),
                    isPinned: model.isConversationPinned(conversation),
                    isMuted: model.isConversationMuted(conversation)
                )
            }
    }

    /// Loads a bounded timeline through the existing encrypted messaging runtime.
    func carPlayMessages(conversationID: String, limit: Int = 10) async throws -> [CSMCarPlayMessage] {
        await startIfNeeded()
        guard model.authState == .signedIn else {
            throw CSMCarPlayCommunicationError.authenticationRequired
        }
        guard let conversation = model.visibleConversations.first(where: { $0.conversationId == conversationID }) else {
            throw CSMCarPlayCommunicationError.conversationNotFound
        }

        await model.selectConversation(conversation)
        return model.messages
            .filter { !$0.isDeleted }
            .suffix(max(0, limit))
            .map { message in
                CSMCarPlayMessage(
                    id: message.id,
                    conversationID: conversationID,
                    senderID: message.senderId,
                    senderDisplayName: message.senderDisplayName,
                    body: message.body,
                    sentAt: message.sentAt,
                    isOwnMessage: message.isOwnMessage
                )
            }
    }

    /// Sends through the same E2EE pipeline as the phone UI. No credentials are exposed to CarPlay.
    func sendCarPlayMessage(_ body: String, conversationID: String) async throws -> CSMCarPlayMessage {
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else {
            throw CSMCarPlayCommunicationError.emptyMessage
        }

        await startIfNeeded()
        guard model.authState == .signedIn else {
            throw CSMCarPlayCommunicationError.authenticationRequired
        }
        guard let conversation = model.visibleConversations.first(where: { $0.conversationId == conversationID }) else {
            throw CSMCarPlayCommunicationError.conversationNotFound
        }

        await model.selectConversation(conversation)
        guard await model.sendMessage(normalizedBody) else {
            throw CSMCarPlayCommunicationError.sendFailed
        }

        let sent = model.messages.last(where: {
            $0.isOwnMessage && $0.body == normalizedBody && !$0.isDeleted
        })
        return CSMCarPlayMessage(
            id: sent?.id ?? UUID().uuidString,
            conversationID: conversationID,
            senderID: sent?.senderId ?? "current-user",
            senderDisplayName: sent?.senderDisplayName ?? "Já",
            body: normalizedBody,
            sentAt: sent?.sentAt ?? .now,
            isOwnMessage: true
        )
    }
}
