import Foundation

/// Ephemeral authenticated metadata. Never serialized with a cached conversation.
struct MessagingIdentityLookup: Codable, Equatable, Hashable, Sendable {
    struct Pair: Codable, Equatable, Hashable, Sendable { let userId: String; let matrixUserId: String }
    let contractVersion: String
    let providerId: String
    let actorUserId: String
    let conversationId: String
    let matrixRoomId: String?
    let identities: [Pair]
    let unresolvedUserIds: [String]
    let validUntil: Date
    let status: String
    let warnings: [String]

    func verified(for conversation: Conversation, actorUserId: String, matrixUserId: String?, now: Date = .now) -> Bool {
        guard contractVersion == "cop-messaging-identity-lookup-v1", providerId == "csm.messaging", status == "online", warnings.isEmpty,
              self.actorUserId == actorUserId, conversationId == conversation.conversationId,
              matrixRoomId == conversation.activeMatrixRoomId,
              validUntil > now, validUntil.timeIntervalSince(now) <= 35 else { return false }
        let ids = identities.map(\.userId) + unresolvedUserIds
        let expected = conversation.members.map(\.userId)
        guard !ids.isEmpty, ids.count <= 100, Set(ids).count == ids.count,
              Set(expected) == Set(ids), Set(expected).count == expected.count, ids.contains(actorUserId),
              identities.allSatisfy({ validID($0.userId) && !$0.userId.hasPrefix("@") && validMatrixID($0.matrixUserId) }),
              unresolvedUserIds.allSatisfy({ validID($0) && !$0.hasPrefix("@") }),
              Set(identities.map(\.matrixUserId)).count == identities.count else { return false }
        if let matrixUserId {
            guard identities.first(where: { $0.userId == actorUserId })?.matrixUserId == matrixUserId else { return false }
        }
        return true
    }

    func canonicalKey(_ id: String) -> String {
        identities.first(where: { $0.matrixUserId == id })?.userId ?? ConversationIdentity.canonicalKey(id)
    }

    var complete: Bool { unresolvedUserIds.isEmpty }
    private func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 160 && id == id.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
    private func validMatrixID(_ id: String) -> Bool {
        validID(id) && id.hasPrefix("@") && id.dropFirst().contains(":") && !id.contains(where: { $0.isWhitespace })
    }
}
