import Foundation
import XCTest
@testable import CSMCommunicationKit

final class MobilityInvitationNotificationTests: XCTestCase {
    private let user = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    private let invite = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    private var valid: String { "csm://mobility/invitations/v1/\(user.uuidString.lowercased())/vehicle/\(invite.uuidString.lowercased())" }
    func testVersionedTargetAndBothEntityTypes() throws {
        for type in ["vehicle", "group"] {
            let target = try XCTUnwrap(CSMMobilityInvitationNotificationTarget(url: URL(string: valid.replacingOccurrences(of: "/vehicle/", with: "/\(type)/"))!))
            XCTAssertEqual(target.recipientAccountId, user); XCTAssertEqual(target.invitationId, invite)
            XCTAssertEqual(target.entityType.rawValue, type)
        }
    }
    func testRejectsUntrustedOrFreeContextLinks() {
        for value in [valid+"?email=private", valid+"#free", valid+"/extra", valid.replacingOccurrences(of: "v1", with: "v2"), valid.replacingOccurrences(of: "vehicle", with: "gps"), valid.replacingOccurrences(of: "csm://", with: "https://"), valid.replacingOccurrences(of: "mobility/", with: "attacker/"), valid.replacingOccurrences(of: "/v1/", with: "/v1//")] {
            XCTAssertNil(CSMMobilityInvitationNotificationTarget(url: URL(string: value)!))
        }
    }
    @MainActor
    func testResolutionRechecksIdentityRevocationAndExpiration() async throws {
        let target = try XCTUnwrap(CSMMobilityInvitationNotificationTarget(url: URL(string: valid)!))
        let now = Date(timeIntervalSince1970: 1000)
        let account = CSMMobilityAccount(contractVersion: .cop_mobility_account_v1, accountId: user, displayName: "Synthetic", emailVerified: true, serverTimestamp: "")
        let item = CSMMobilityPendingInvitation(invitationId: invite, entityType: .vehicle, entityId: UUID(), entityName: "Synthetic", inviterName: "Synthetic", expiresAt: "2026-10-06T00:00:00Z", capabilities: [])
        let inbox = CSMMobilityPendingInvitations(contractVersion: .cop_mobility_invitation_v1, items: [item], serverTimestamp: "")
        var scope = "a"
        let resolved = try await resolveMobilityInvitationNotification(target: target, expectedScope: "a", currentScope: { scope }, account: { account }, invitations: { inbox }, now: now)
        XCTAssertEqual(resolved?.invitationId, invite)
        let wrong = CSMMobilityAccount(contractVersion: .cop_mobility_account_v1, accountId: UUID(), displayName: "Other", emailVerified: true, serverTimestamp: "")
        var inboxCalls = 0
        let mismatch = try await resolveMobilityInvitationNotification(target: target, expectedScope: "a", currentScope: { scope }, account: { wrong }, invitations: { inboxCalls += 1; return inbox }, now: now)
        XCTAssertNil(mismatch); XCTAssertEqual(inboxCalls, 0)
        let revoked = try await resolveMobilityInvitationNotification(target: target, expectedScope: "a", currentScope: { scope }, account: { account }, invitations: { .init(contractVersion: .cop_mobility_invitation_v1, items: [], serverTimestamp: "") }, now: now)
        XCTAssertNil(revoked)
        let expired = try await resolveMobilityInvitationNotification(target: target, expectedScope: "a", currentScope: { scope }, account: { account }, invitations: { inbox }, now: Date(timeIntervalSince1970: 3_000_000_000))
        XCTAssertNil(expired)
        let changed = try await resolveMobilityInvitationNotification(target: target, expectedScope: "a", currentScope: { scope }, account: { account }, invitations: { scope = "b"; return inbox }, now: now)
        XCTAssertNil(changed)
    }
}
