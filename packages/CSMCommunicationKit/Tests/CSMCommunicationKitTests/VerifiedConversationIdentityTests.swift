import Foundation
import XCTest
@testable import CSMCommunicationKit
@testable import CSMVoiceCallKit

@MainActor
final class VerifiedConversationIdentityTests: XCTestCase {
    private let actor = AuthenticatedActor(subjectId: "actor-a", username: "username-not-id", displayName: "Same name", roles: ["user"])
    private func conversation() -> Conversation {
        Conversation(conversationId: "room-1", title: "Peer", type: .direct, status: "active", encrypted: true, e2eeRequired: true, memberCount: 2, mapLinkCount: 0, members: [ConversationMember(userId: "actor-a", displayName: "Same name"), ConversationMember(userId: "actor-b", displayName: "Same name")], mapLinks: [], updatedAt: .now)
    }
    private func lookup(actorID: String = "actor-a", roomID: String = "room-1", pairs: [MessagingIdentityLookup.Pair]? = nil, expires: Date = Date().addingTimeInterval(25)) -> MessagingIdentityLookup {
        MessagingIdentityLookup(contractVersion: "cop-messaging-identity-lookup-v1", providerId: "csm.messaging", actorUserId: actorID, conversationId: roomID, matrixRoomId: nil, identities: pairs ?? [.init(userId: "actor-a", matrixUserId: "@cop_actor-a_012345:matrix.test"), .init(userId: "actor-b", matrixUserId: "@cop_actor-b_abcdef:matrix.test")], unresolvedUserIds: [], validUntil: expires, status: "online", warnings: [])
    }
    func testAuthoritativePairsUnifyFourTransportEntriesIntoTwoPeopleWithoutNameGuessing() {
        var room = conversation(); let map = lookup()
        XCTAssertTrue(map.verified(for: room, actorUserId: actor.subjectId, matrixUserId: "@cop_actor-a_012345:matrix.test"))
        room.identityLookup = map
        room.members += [ConversationMember(userId: "@cop_actor-a_012345:matrix.test", displayName: "Other own name"), ConversationMember(userId: "@cop_actor-b_abcdef:matrix.test", displayName: "Different peer name")]
        let output = CommunicationModel.normalizedConversationList([room], actor: actor, matrixUserId: "@cop_actor-a_012345:matrix.test")
        XCTAssertEqual(output[0].memberCount, 2); XCTAssertEqual(Set(output[0].members.map(\.userId)), ["actor-a","actor-b"])
        XCTAssertEqual(output[0].title, "Same name")
        XCTAssertEqual(CommunicationModel.knownRecipients(actor: actor, conversations: output).map(\.userId), ["actor-b"])
    }
    func testMissingMappingDoesNotGuessPeerByNameOrMergeForeignServers() {
        var room = conversation(); room.members += [ConversationMember(userId: "@cop_actor-a_012345:matrix.test", displayName: "Same name"), ConversationMember(userId: "@cop_actor-b_abcdef:matrix.test", displayName: "Same name")]
        let output = CommunicationModel.normalizedConversationList([room], actor: actor)
        XCTAssertEqual(output[0].title, "Peer"); XCTAssertEqual(output[0].members.count, 4)
        XCTAssertFalse(ConversationIdentity.matches("@cop_actor-a:server-a", "actor-a"))
        XCTAssertFalse(ConversationIdentity.matches("@same:server-a", "@same:server-b"))
        XCTAssertFalse(ConversationIdentity.matches("Actor-A", "actor-a"))
    }
    func testWrongActorRoomBootstrapAndExpiredMappingAreRejected() {
        let room = conversation()
        for map in [lookup(actorID:"actor-b"), lookup(roomID:"other"), lookup(expires:.distantPast), lookup(pairs:[.init(userId:"actor-a",matrixUserId:"@duplicate:matrix.test"),.init(userId:"actor-b",matrixUserId:"@duplicate:matrix.test")])] {
            XCTAssertFalse(map.verified(for:room,actorUserId:"actor-a",matrixUserId:"@cop_actor-a_012345:matrix.test"))
        }
        XCTAssertFalse(lookup().verified(for:room,actorUserId:"actor-a",matrixUserId:"@wrong:matrix.test"))
        var changed = room; changed.members.append(ConversationMember(userId:"new-member"))
        XCTAssertFalse(lookup().verified(for:changed,actorUserId:"actor-a",matrixUserId:nil))
    }
    func testVerifiedMappingIsNotSerializedIntoConversationCache() throws {
        var room = conversation(); room.identityLookup = lookup()
        let encoded = try JSONEncoder().encode(room)
        XCTAssertFalse(String(decoding:encoded,as:UTF8.self).contains("cop-messaging-identity-lookup-v1"))
        XCTAssertNil(try JSONDecoder().decode(Conversation.self,from:encoded).identityLookup)
    }
    func testAmbiguousSameTitlesDoNotMergeUnrelatedConversations() {
        var first=conversation(); first.members=[]
        var second=first; second.conversationId="different-room"
        XCTAssertEqual(CommunicationModel.normalizedConversationList([first,second],actor:actor).count,2)
    }
    func testIncomingPushNameUsesOnlyExplicitSenderField() throws {
        var payload:[AnyHashable:Any] = ["type":"chat.voice_call.incoming","callId":"b5ea7309-7f53-4e87-9225-fd38e9737540","roomId":"!room:matrix.test","senderDisplayName":"Caller","recipientDisplayName":"Callee","title":"Callee"]
        XCTAssertEqual(try XCTUnwrap(VoiceCallPushPayload(dictionary:payload)).callerDisplayName,"Caller")
        payload.removeValue(forKey:"senderDisplayName")
        XCTAssertEqual(try XCTUnwrap(VoiceCallPushPayload(dictionary:payload)).callerDisplayName,"COP kontakt")
    }
    func testAPIIncomingCallUsesVerifiedCallerAndRejectsCalleeTitleAndMismatchedPeer() throws {
        let payload = #"{"acceptedByEndpointId":null,"callId":"b5ea7309-7f53-4e87-9225-fd38e9737540","connectedAt":null,"createdAt":"2026-10-05T20:00:00Z","direction":"incoming","endedAt":null,"endReason":null,"expiresAt":"2026-10-05T20:01:30Z","initiatorSubjectId":"caller","kind":"direct","participantSubjectIds":["callee"],"phase":"ringing","revision":1,"roomId":"!room:matrix.test","title":"Callee name","updatedAt":"2026-10-05T20:00:00Z"}"#
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(CSMVoiceCall.self, from: Data(payload.utf8))
        XCTAssertNil(legacy.peer); XCTAssertEqual(legacy.presentationTitle,"COP kontakt")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String:Any])
        object["peer"] = ["subjectId":"caller","displayName":"Caller name"]
        let verified = try decoder.decode(CSMVoiceCall.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertEqual(verified.presentationTitle,"Caller name")
        object["peer"] = ["subjectId":"callee","displayName":"Callee name"]
        XCTAssertEqual(try decoder.decode(CSMVoiceCall.self,from:JSONSerialization.data(withJSONObject:object)).presentationTitle,"COP kontakt")
        object["direction"] = "outgoing"; object["peer"] = ["subjectId":"callee","displayName":"Callee name"]
        XCTAssertEqual(try decoder.decode(CSMVoiceCall.self,from:JSONSerialization.data(withJSONObject:object)).presentationTitle,"Callee name")
    }

}
