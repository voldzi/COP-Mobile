import AVFAudio
import XCTest

@testable import CSMVoiceCallKit

final class VoiceCallPushPayloadTests: XCTestCase {
  func testIncomingVoiceCallPushMatchesCSMMessagingContract() throws {
    let payload = try XCTUnwrap(
      VoiceCallPushPayload(dictionary: [
        "aps": ["content-available": 1],
        "callId": "b5ea7309-7f53-4e87-9225-fd38e9737540",
        "roomId": "!direct:msg.zeleznalady.cz",
        "senderDisplayName": "Jiřina Volková",
        "type": "chat.voice_call.incoming",
      ]))

    XCTAssertEqual(payload.event, .incoming)
    XCTAssertEqual(payload.callID, "b5ea7309-7f53-4e87-9225-fd38e9737540")
    XCTAssertEqual(payload.roomID, "!direct:msg.zeleznalady.cz")
    XCTAssertEqual(payload.callerDisplayName, "Jiřina Volková")
  }

  func testVoiceCallPushRejectsUnknownAndIncompletePayloads() {
    XCTAssertNil(
      VoiceCallPushPayload(dictionary: [
        "callId": "b5ea7309-7f53-4e87-9225-fd38e9737540",
        "roomId": "!direct:msg.zeleznalady.cz",
        "type": "chat.voice_call.progress",
      ]))
    XCTAssertNil(
      VoiceCallPushPayload(dictionary: [
        "callId": "not-a-uuid",
        "roomId": "!direct:msg.zeleznalady.cz",
        "type": "chat.voice_call.incoming",
      ]))
  }
}

final class VoiceCallPushTokenStateTests: XCTestCase {
  func testCachedTokenIsNeverRegisteredBeforePushKitConfirmsIt() {
    let state = VoiceCallPushTokenState(cachedToken: "stale-token")

    XCTAssertNil(state.tokenForServerRegistration)
    XCTAssertTrue(state.needsRegistrationRecovery)
  }

  func testPushKitConfirmationRefreshesServerEvenWhenTokenMatchesCache() {
    var state = VoiceCallPushTokenState(cachedToken: "same-token")

    XCTAssertTrue(state.confirm("same-token"))
    XCTAssertEqual(state.tokenForServerRegistration, "same-token")
    XCTAssertFalse(state.needsRegistrationRecovery)
  }

  func testRepeatedConfirmationDoesNotCreateDuplicateRegistration() {
    var state = VoiceCallPushTokenState(cachedToken: nil)

    XCTAssertTrue(state.confirm("current-token"))
    XCTAssertFalse(state.confirm("current-token"))
  }

  func testInvalidationRemovesConfirmedTokenAndRequestsRecovery() {
    var state = VoiceCallPushTokenState(cachedToken: nil)
    _ = state.confirm("current-token")

    state.invalidate()

    XCTAssertNil(state.tokenForServerRegistration)
    XCTAssertTrue(state.needsRegistrationRecovery)
  }
}

final class VoiceCallAudioSessionPolicyTests: XCTestCase {
  func testActiveCallKitSessionIsNeverReconfigured() {
    XCTAssertFalse(
      VoiceCallAudioSessionPolicy.needsConfiguration(
        category: .ambient,
        mode: .default,
        options: [],
        isActive: true
      )
    )
  }

  func testPreparedVoiceSessionIsReused() {
    XCTAssertFalse(
      VoiceCallAudioSessionPolicy.needsConfiguration(
        category: .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetoothHFP],
        isActive: false
      )
    )
  }

  func testInactiveUnpreparedSessionIsConfiguredBeforeCallKitAction() {
    XCTAssertTrue(
      VoiceCallAudioSessionPolicy.needsConfiguration(
        category: .ambient,
        mode: .default,
        options: [],
        isActive: false
      )
    )
  }
}
