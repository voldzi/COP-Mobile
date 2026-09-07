import AVFAudio
import XCTest

@testable import COPMobile

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
