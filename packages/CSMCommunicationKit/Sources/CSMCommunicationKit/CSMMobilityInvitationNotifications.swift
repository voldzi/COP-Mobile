import Foundation

public extension Notification.Name {
    /// userInfo["navigation"] is CSMMobilityInvitationNavigation, verified via current COP session.
    static let csmMobilityInvitationRequested = Notification.Name("CSMMobilityInvitationRequested")
    /// Verification failed or no current matching invite (one neutral result). No invitation is accepted; host may offer inbox retry.
    static let csmMobilityInvitationVerificationFailed = Notification.Name("CSMMobilityInvitationVerificationFailed")
}

public struct CSMMobilityInvitationNotificationTarget: Equatable, Sendable {
    public let recipientAccountId: UUID
    public let invitationId: UUID
    public let entityType: CSMMobilityPendingInvitationEntityType
    public init?(url: URL) {
        guard url.scheme == "csm", url.host == "mobility", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        let path = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 6, path[0].isEmpty, path[1] == "invitations", path[2] == "v1",
              let account = UUID(uuidString: String(path[3])),
              let type = CSMMobilityPendingInvitationEntityType(rawValue: String(path[4])),
              let invitation = UUID(uuidString: String(path[5])) else { return nil }
        recipientAccountId = account; entityType = type; invitationId = invitation
    }
}

public struct CSMMobilityInvitationNavigation: Sendable {
    public let invitation: CSMMobilityPendingInvitation
    public let sessionScope: String
}

@MainActor
func resolveMobilityInvitationNotification(
    target: CSMMobilityInvitationNotificationTarget, expectedScope: String,
    currentScope: () -> String?, account: () async throws -> CSMMobilityAccount,
    invitations: () async throws -> CSMMobilityPendingInvitations, now: Date = .now
) async throws -> CSMMobilityPendingInvitation? {
    guard currentScope() == expectedScope else { return nil }
    let user = try await account()
    guard currentScope() == expectedScope, user.accountId == target.recipientAccountId,
          user.emailVerified else { return nil }
    let inbox = try await invitations()
    guard currentScope() == expectedScope else { return nil }
    let item = inbox.items.first { $0.invitationId == target.invitationId && $0.entityType == target.entityType }
    guard let item else { return nil }
    let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let expiry = precise.date(from: item.expiresAt) ?? ISO8601DateFormatter().date(from: item.expiresAt), expiry > now else { return nil }
    return item
}

public extension CSMCommunicationRuntime {
    /// Fetches account and authoritative inbox; this is navigation only, never acceptance/start.
    func mobilityInvitationForNotification(url: URL, expectedScope: String) async throws -> CSMMobilityPendingInvitation? {
        guard let target = CSMMobilityInvitationNotificationTarget(url: url) else { return nil }
        return try await resolveMobilityInvitationNotification(target: target, expectedScope: expectedScope,
            currentScope: { self.mobilitySessionScope() },
            account: { try await self.mobilityAccount(expectedScope: expectedScope) },
            invitations: { try await self.mobilityInvitations(expectedScope: expectedScope) })
    }
}
