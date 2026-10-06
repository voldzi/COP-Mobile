import AVFAudio
import XCTest

@testable import CSMVoiceCallKit

final class VoiceCallDistributionPolicyTests: XCTestCase {
  func testOnlyExplicitGlobalDistributionEnablesSystemCalling() {
    XCTAssertEqual(VoiceCallDistributionPolicy.mode(for: "global"), .system)
    XCTAssertEqual(VoiceCallDistributionPolicy.mode(for: "china"), .inApp)
    XCTAssertEqual(VoiceCallDistributionPolicy.mode(for: nil), .inApp)
    XCTAssertEqual(VoiceCallDistributionPolicy.mode(for: "unexpected"), .inApp)
  }
}

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

  func testAnsweredElsewherePushCarriesWinningEndpoint() throws {
    let payload = try XCTUnwrap(
      VoiceCallPushPayload(dictionary: [
        "acceptedEndpointId": "ios:cop-mobile-device",
        "callId": "b5ea7309-7f53-4e87-9225-fd38e9737540",
        "roomId": "!direct:msg.zeleznalady.cz",
        "type": "chat.voice_call.answered_elsewhere",
      ]))

    XCTAssertEqual(payload.event, .answeredElsewhere)
    XCTAssertEqual(payload.acceptedEndpointID, "ios:cop-mobile-device")
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

final class VoiceCallConnectionPolicyTests: XCTestCase {
  func testRingingInConnectedRoomWaitsForServerExpiryWithoutMediaFailureDeadline() {
    let stage = VoiceCallConnectionPolicy.stage(serverPhase: .ringing, roomConnected: true,
      peerPresent: false, answered: false, incoming: false, audioActivated: true, microphonePublished: true)
    XCTAssertEqual(stage, .waitingForAnswer)
    XCTAssertFalse(VoiceCallConnectionPolicy.requiresMediaDeadline(stage))
  }
  func testSocketFailureBeforeAnswerStillHasBoundedMediaDeadline() {
    let stage = VoiceCallConnectionPolicy.stage(serverPhase: .ringing, roomConnected: false,
      peerPresent: false, answered: false, incoming: false, audioActivated: true, microphonePublished: false)
    XCTAssertEqual(stage, .connectingRoom)
    XCTAssertTrue(VoiceCallConnectionPolicy.requiresMediaDeadline(stage))
  }
  func testAcceptanceStartsSeparateDeadlineAndNeverClaimsConnectionWithoutAudio() {
    for (audio, mic, peer) in [(false, true, true), (true, false, true), (true, true, false)] {
      let stage = VoiceCallConnectionPolicy.stage(serverPhase: .accepted, roomConnected: true,
        peerPresent: peer, answered: true, incoming: true, audioActivated: audio, microphonePublished: mic)
      XCTAssertEqual(stage, .connectingAcceptedMedia)
      XCTAssertTrue(VoiceCallConnectionPolicy.requiresMediaDeadline(stage))
    }
    XCTAssertEqual(VoiceCallConnectionPolicy.stage(serverPhase: .accepted, roomConnected: true,
      peerPresent: true, answered: true, incoming: true, audioActivated: true, microphonePublished: true), .waitingForServerAck)
  }
  func testLocalMediaReadyWithoutServerAckKeepsBoundedDeadlineEvenWithoutPolling() {
    let ackPending = VoiceCallConnectionPolicy.stage(serverPhase: .accepted, roomConnected: true,
      peerPresent: true, answered: true, incoming: false, audioActivated: true, microphonePublished: true)
    XCTAssertEqual(ackPending, .waitingForServerAck)
    XCTAssertTrue(VoiceCallConnectionPolicy.requiresMediaDeadline(ackPending))
    let acknowledged = VoiceCallConnectionPolicy.stage(serverPhase: .connected, roomConnected: true,
      peerPresent: true, answered: true, incoming: false, audioActivated: true, microphonePublished: true)
    XCTAssertEqual(acknowledged, .connected)
    XCTAssertFalse(VoiceCallConnectionPolicy.requiresMediaDeadline(acknowledged))
    let incomingRinging = VoiceCallConnectionPolicy.stage(serverPhase: .ringing, roomConnected: false,
      peerPresent: false, answered: false, incoming: true, audioActivated: false, microphonePublished: false)
    XCTAssertEqual(incomingRinging, .waitingForAnswer)
    XCTAssertFalse(VoiceCallConnectionPolicy.requiresMediaDeadline(incomingRinging))
  }
  func testPeerJoiningBeforeServerAcceptanceDoesNotConnectAndTerminalNeverRestarts() {
    XCTAssertEqual(VoiceCallConnectionPolicy.stage(serverPhase: .ringing, roomConnected: true,
      peerPresent: true, answered: false, incoming: false, audioActivated: true, microphonePublished: true), .waitingForAnswer)
    XCTAssertEqual(VoiceCallConnectionPolicy.stage(serverPhase: .cancelled, roomConnected: true,
      peerPresent: true, answered: true, incoming: false, audioActivated: true, microphonePublished: true), .terminal)
  }
}

@MainActor
final class VoiceCallConnectionDeadlineTests: XCTestCase {
  func testPeerDisconnectOrAudioInterruptionCannotDropOrExtendServerAckDeadline() async throws {
    for refreshCallback in [false, true] {
      let deadline = VoiceCallConnectionDeadline(duration: .milliseconds(80))
      let uuid = UUID()
      var stage: VoiceCallConnectionPolicy.Stage = .waitingForServerAck
      var failures = 0
      deadline.update(uuid: uuid, stage: stage, currentStage: { stage }, timedOut: { failures += 1 })
      try await Task.sleep(for: .milliseconds(45))
      // This is the same scheduler used by the actual peer-disconnect,
      // didDeactivate and in-app interruption callbacks. Even a missed refresh
      // must examine the CURRENT bounded stage when the original budget expires.
      stage = .connectingAcceptedMedia
      if refreshCallback {
        deadline.update(uuid: uuid, stage: stage, currentStage: { stage }, timedOut: { failures += 1 })
      }
      try await Task.sleep(for: .milliseconds(55))
      XCTAssertEqual(failures, 1, "Stage changes cannot cancel or restart the original deadline")
      deadline.cancel()
    }
  }
  func testConnectedAndTerminalCancelDeadlineAndRingingStartsANewBudgetOnAcceptance() async throws {
    for stageAfter in [VoiceCallConnectionPolicy.Stage.connected, .terminal, .waitingForAnswer] {
      let deadline = VoiceCallConnectionDeadline(duration: .milliseconds(40))
      let uuid = UUID()
      var current = VoiceCallConnectionPolicy.Stage.waitingForServerAck
      var failures = 0
      deadline.update(uuid: uuid, stage: current, currentStage: { current }, timedOut: { failures += 1 })
      current = stageAfter
      deadline.update(uuid: uuid, stage: current, currentStage: { current }, timedOut: { failures += 1 })
      try await Task.sleep(for: .milliseconds(60))
      XCTAssertEqual(failures, 0)
      if stageAfter == .waitingForAnswer {
        current = .connectingAcceptedMedia
        deadline.update(uuid: uuid, stage: current, currentStage: { current }, timedOut: { failures += 1 })
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(failures, 1)
      }
      deadline.cancel()
    }
  }
}
