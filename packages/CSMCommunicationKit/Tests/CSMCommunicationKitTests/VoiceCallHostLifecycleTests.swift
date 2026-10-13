import AVFAudio
import Foundation
import XCTest

@testable import CSMCommunicationKit
@testable import CSMVoiceCallKit

@MainActor
final class VoiceCallHostLifecycleTests: XCTestCase {
  func testColdStaticSuspendDoesNotConstructTheSharedService() {
    XCTAssertNil(VoiceCallService.existingHostState)
    XCTAssertEqual(
      VoiceCallService.suspendExisting(expectedScope: "opaque-cold-scope", expectedGeneration: UUID()),
      .notInitialized
    )
    XCTAssertNil(VoiceCallService.existingHostState)
  }

  func testExplicitOffConstructionAndForegroundNeverInitializeNativeProducers() async {
    let harness = VoiceHostHarness(enabled: false)
    let service = harness.makeService()

    service.prepareForApplicationLaunch()
    service.applicationDidBecomeActive()
    service.incomingUserNotificationReceived()
    service.startVoiceCall(roomID: "synthetic-room", title: "Synthetic call", participantSubjectIDs: nil)
    let token = await service.currentPushTokenIfAvailable()
    await settleTasks()

    XCTAssertTrue(service.hostState.suspended)
    XCTAssertNil(token)
    XCTAssertEqual(harness.audioInitializations, 0)
    XCTAssertEqual(harness.bindings.count, 0)
    XCTAssertEqual(harness.permissionRequests, 0)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertFalse(service.hasActiveCall)
  }

  func testAutomaticPolicyKeepsLegacySystemInitializationAndRejectsHostStop() {
    let harness = VoiceHostHarness(policy: .automatic, enabled: false)
    let service = harness.makeService(policy: .automatic)

    service.prepareForApplicationLaunch()
    service.prepareForApplicationLaunch()

    XCTAssertFalse(service.hostState.suspended)
    XCTAssertEqual(harness.audioInitializations, 1)
    XCTAssertEqual(harness.bindings.count, 1)
    XCTAssertEqual(
      service.suspend(expectedScope: harness.scope, expectedGeneration: harness.generation),
      .automaticPolicy
    )
    XCTAssertFalse(service.hostState.suspended)
    XCTAssertFalse(harness.bindings[0].retired)
  }

  func testChinaAndUnknownDistributionNeverConstructSystemCallingResources() throws {
    let distributions: [String?] = ["china", nil, "unknown"]
    for distribution in distributions {
      let harness = VoiceHostHarness()
      let mode = VoiceCallDistributionPolicy.mode(for: distribution)
      let service = harness.makeService(mode: mode)
      defer { harness.stop(service) }

      service.prepareForApplicationLaunch()
      _ = try service.resumeForHostCommunication(
        expectedScope: harness.scope, expectedGeneration: harness.generation
      )

      XCTAssertEqual(mode, .inApp)
      XCTAssertEqual(harness.bindings.count, 0)
      XCTAssertEqual(harness.audioInitializations, 1, "Repeated resume must not reconfigure audio")
    }
  }

  func testUnknownActivationPolicyCannotConstructResourcesOrResume() {
    let harness = VoiceHostHarness(policy: .invalid)
    let service = harness.makeService(policy: .invalid)

    XCTAssertThrowsError(try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    ))
    XCTAssertTrue(service.hostState.suspended)
    XCTAssertEqual(harness.audioInitializations, 0)
    XCTAssertEqual(harness.bindings.count, 0)
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testHeldIncomingReportFinishesOnItsOldBindingAfterAnotherAccountResumes() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let timeline = VoiceTimelineCounter()
    let observer = observeTimeline(timeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    let oldBinding = harness.bindings[0]
    let oldReporter = harness.reporters[0]
    let oldID = UUID()
    var oldCompletionCount = 0

    service.receive(payload: incomingPayload(oldID), binding: oldBinding) {
      oldCompletionCount += 1
      oldReporter.recordCompletion()
    }
    XCTAssertEqual(service.presentation.activeCall?.id, oldID)
    XCTAssertEqual(oldCompletionCount, 0)
    harness.stop(service)
    XCTAssertTrue(service.hostState.serverAssistanceRequired)
    XCTAssertEqual(oldReporter.events, [.incoming(oldID)], "A pending report ends only after its result")

    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    )
    let newID = UUID()
    let newReporter = harness.reporters[1]
    service.receive(payload: incomingPayload(newID), binding: harness.bindings[1]) {}
    newReporter.completeReport(at: 0, succeeded: true)

    oldReporter.completeReport(at: 0, succeeded: true)
    oldReporter.completeReport(at: 0, succeeded: true)

    XCTAssertEqual(oldReporter.events, [.incoming(oldID), .ended(oldID), .completed])
    XCTAssertEqual(oldCompletionCount, 1)
    XCTAssertEqual(newReporter.events, [.incoming(newID)])
    XCTAssertEqual(service.presentation.activeCall?.id, newID)
    XCTAssertEqual(service.hostState.scope, "opaque-account-b")
    XCTAssertFalse(service.hostState.suspended)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertEqual(timeline.value, 0)
  }

  func testOldReportCompletionCannotRemoveSameCallUUIDFromANewEpoch() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let timeline = VoiceTimelineCounter()
    let observer = observeTimeline(timeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    let callID = UUID()
    let oldReporter = harness.reporters[0]
    var oldCompletions = 0
    service.receive(payload: incomingPayload(callID), binding: harness.bindings[0]) {
      oldCompletions += 1
    }
    harness.stop(service)

    // The same broadcast invitation may still exist after OFF then ON. Its
    // server UUID is unchanged, but its local producer owner is a new epoch.
    harness.select(scope: harness.scope, generation: UUID(), endpointID: harness.endpointID)
    _ = try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    )
    let newReporter = harness.reporters[1]
    service.receive(payload: incomingPayload(callID), binding: harness.bindings[1]) {}
    newReporter.completeReport(at: 0, succeeded: true)
    oldReporter.completeReport(at: 0, succeeded: true)

    XCTAssertEqual(oldCompletions, 1)
    XCTAssertEqual(oldReporter.events, [.incoming(callID), .ended(callID)])
    XCTAssertEqual(newReporter.events, [.incoming(callID)])
    XCTAssertEqual(service.presentation.activeCall?.id, callID)
    XCTAssertFalse(service.hostState.suspended)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertEqual(timeline.value, 0)
  }

  func testHeldReconciliationReportSurvivesOffAndCannotAffectTheNewAccount() async throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    let oldID = UUID()
    harness.listResult = [syntheticSession(callID: oldID, roomID: "old-room", direction: .incoming).call]
    let oldReporter = harness.reporters[0]
    let oldBinding = harness.bindings[0]
    let timeline = VoiceTimelineCounter()
    let observer = observeTimeline(timeline)
    defer { NotificationCenter.default.removeObserver(observer); harness.stop(service) }
    let reconciliation = Task { await service.reconcileActiveIncomingCalls() }
    defer { oldReporter.completeReportIfPresent(at: 0, succeeded: true); reconciliation.cancel() }
    try await waitUntil { !oldReporter.events.isEmpty }

    XCTAssertTrue(oldBinding.reportIsPending(oldID))
    harness.stop(service)
    XCTAssertEqual(oldReporter.events, [.incoming(oldID)])
    XCTAssertTrue(oldBinding.hasPendingReports)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    let newID = UUID()
    service.receive(payload: incomingPayload(newID), binding: harness.bindings[1]) {}
    harness.reporters[1].completeReport(at: 0, succeeded: true)
    oldReporter.completeReport(at: 0, succeeded: true)
    await reconciliation.value

    XCTAssertFalse(oldBinding.hasPendingReports)
    XCTAssertEqual(oldReporter.events, [.incoming(oldID), .ended(oldID)])
    XCTAssertEqual(service.presentation.activeCall?.id, newID)
    XCTAssertEqual(service.hostState.scope, harness.scope)
    XCTAssertEqual(harness.listOwners.count, 1)
    XCTAssertEqual(harness.listOwners[0].scope, "opaque-account-a")
    XCTAssertTrue(harness.fetchOwners.allSatisfy { $0.scope == harness.scope })
    XCTAssertEqual(harness.transitionOwners.count, 0)
    XCTAssertEqual(timeline.value, 0)
  }

  func testTwoRetiredBindingsBlockThirdProviderUntilEveryDuplicateReportDrains() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let idA = UUID()
    let reporterA = harness.reporters[0]
    let bindingA = harness.bindings[0]
    service.receive(payload: incomingPayload(idA), binding: bindingA) {}
    harness.stop(service)
    // A second in-flight delivery on the retired registry is OS bookkeeping.
    // Its separate result must not be lost when the first callback finishes.
    service.receive(payload: incomingPayload(idA), binding: bindingA) {}
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    let idB = UUID()
    let reporterB = harness.reporters[1]
    service.receive(payload: incomingPayload(idB), binding: harness.bindings[1]) {}
    harness.stop(service)
    harness.select(scope: "opaque-account-c", generation: UUID(), endpointID: "synthetic-endpoint-c")

    func assertThirdIsBlocked() {
      XCTAssertThrowsError(try service.resumeForHostCommunication(
        expectedScope: harness.scope, expectedGeneration: harness.generation
      )) { error in
        guard case .systemCleanupPending? = error as? VoiceCallHostLifecycleError else {
          return XCTFail("Expected bounded system-cleanup wait, got \(error)")
        }
      }
      XCTAssertTrue(service.hostState.suspended)
      XCTAssertEqual(harness.bindings.count, 2)
      XCTAssertEqual(harness.audioInitializations, 2)
    }
    assertThirdIsBlocked()
    reporterA.completeReport(at: 0, succeeded: true)
    XCTAssertTrue(bindingA.hasPendingReports)
    assertThirdIsBlocked()
    reporterA.completeReport(at: 1, succeeded: true)
    XCTAssertFalse(bindingA.hasPendingReports)
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    XCTAssertEqual(harness.bindings.count, 3, "The third factory runs only after A is fully retired")
    XCTAssertFalse(service.hostState.suspended)
    reporterB.completeReport(at: 0, succeeded: true)

    XCTAssertEqual(reporterA.events, [.incoming(idA), .incoming(idA), .ended(idA), .ended(idA)])
    XCTAssertEqual(reporterB.events, [.incoming(idB), .ended(idB)])
    XCTAssertEqual(service.hostState.scope, "opaque-account-c")
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testRetiredAudioCallbacksCannotActivateOrStopTheNewOwnersAudio() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let oldBinding = harness.bindings[0]
    service.systemAudioDidActivate(binding: oldBinding, audioSession: AVAudioSession.sharedInstance())
    XCTAssertTrue(service.presentation.isAudioActive)
    harness.stop(service)
    XCTAssertEqual(harness.audioStops, 1)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    let bindingB = harness.bindings[1]
    service.systemAudioDidActivate(binding: bindingB, audioSession: AVAudioSession.sharedInstance())
    XCTAssertEqual(harness.audioActivations, 2)
    service.systemAudioDidActivate(binding: oldBinding, audioSession: AVAudioSession.sharedInstance())
    service.systemAudioDidDeactivate(binding: oldBinding)

    XCTAssertEqual(harness.audioActivations, 2)
    XCTAssertEqual(harness.audioStops, 1)
    XCTAssertTrue(service.presentation.isAudioActive)
    service.systemAudioDidDeactivate(binding: bindingB)
    XCTAssertEqual(harness.audioStops, 2)
    XCTAssertFalse(service.presentation.isAudioActive)
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testServerAssistanceStaysWithItsAccountAndIsNotClearedByLocalResume() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let scopeA = harness.scope
    service.receive(payload: incomingPayload(UUID()), binding: harness.bindings[0]) {}
    harness.stop(service)
    XCTAssertTrue(service.hostState.serverAssistanceRequired)
    harness.reporters[0].completeReport(at: 0, succeeded: true)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    XCTAssertFalse(service.hostState.serverAssistanceRequired, "A's pending cleanup is not B's state")
    harness.stop(service)
    harness.select(scope: scopeA, generation: UUID(), endpointID: "synthetic-endpoint-a")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)

    XCTAssertTrue(service.hostState.serverAssistanceRequired, "Local ON cannot confirm remote cleanup")
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testIncomingWhileSuspendedIsOnlyOSBookkeepingWithoutPollingOrTimeline() async throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    let binding = harness.bindings[0]
    let reporter = harness.reporters[0]
    harness.stop(service)
    let timeline = VoiceTimelineCounter()
    let observer = observeTimeline(timeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    let callID = UUID()
    var completions = 0

    service.receive(payload: incomingPayload(callID), binding: binding) {
      completions += 1
      reporter.recordCompletion()
    }
    XCTAssertFalse(service.hasActiveCall)
    XCTAssertEqual(reporter.events, [.incoming(callID)])
    XCTAssertEqual(completions, 0)
    reporter.completeReport(at: 0, succeeded: true)
    reporter.completeReport(at: 0, succeeded: true)
    service.applicationDidBecomeActive()
    service.incomingUserNotificationReceived()
    // A mistakenly started state-poll task would dispatch after one second.
    try await Task.sleep(for: .milliseconds(1100))

    XCTAssertEqual(reporter.events, [.incoming(callID), .ended(callID), .completed])
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(harness.bindings.count, 1)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertEqual(harness.permissionRequests, 0)
    XCTAssertEqual(timeline.value, 0)
    XCTAssertFalse(service.hasActiveCall)
    XCTAssertTrue(service.hostState.suspended)
  }

  func testRejectedLateIncomingCompletesOnceWithoutRemoteDecline() {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    let binding = harness.bindings[0]
    let reporter = harness.reporters[0]
    harness.stop(service)
    let callID = UUID()
    var completions = 0

    service.receive(payload: incomingPayload(callID), binding: binding) {
      completions += 1
      reporter.recordCompletion()
    }
    reporter.completeReport(at: 0, succeeded: false)
    reporter.completeReport(at: 0, succeeded: true)

    XCTAssertEqual(reporter.events, [.incoming(callID), .completed])
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(harness.transitionOwners.count, 0)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertFalse(service.hasActiveCall)
  }

  func testTerminalPushWhileSuspendedCannotResolveEndpointOrFetchHistory() {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    let binding = harness.bindings[0]
    let reporter = harness.reporters[0]
    harness.stop(service)
    let timeline = VoiceTimelineCounter()
    let observer = observeTimeline(timeline)
    defer { NotificationCenter.default.removeObserver(observer) }
    let endpointReads = harness.endpointReads
    var completions = 0

    for event in ["chat.voice_call.ended", "chat.voice_call.answered_elsewhere"] {
      let callID = UUID()
      service.receive(payload: incomingPayload(callID, event: event), binding: binding) {
        completions += 1
      }
    }

    XCTAssertEqual(completions, 2)
    XCTAssertEqual(reporter.events.count, 2)
    XCTAssertEqual(harness.endpointReads, endpointReads)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertEqual(timeline.value, 0)
    XCTAssertFalse(service.hasActiveCall)
  }

  func testOldPermissionResultCannotStartOrInstallAfterForeignAccountResume() async throws {
    let harness = VoiceHostHarness()
    let gate = VoicePermissionGate()
    harness.permissionGate = gate
    let service = harness.makeService()
    defer { gate.release(false); harness.stop(service) }
    let oldScope = harness.scope
    let oldGeneration = harness.generation

    service.startVoiceCall(roomID: "old-room", title: "Old synthetic call", participantSubjectIDs: nil)
    try await waitUntil { gate.entered }
    harness.stop(service)
    XCTAssertTrue(service.hostState.serverAssistanceRequired)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    )
    harness.permissionGate = nil
    let currentCallID = UUID()
    harness.startResult = syntheticSession(callID: currentCallID, roomID: "new-room")
    service.startVoiceCall(roomID: "new-room", title: "New synthetic call", participantSubjectIDs: nil)
    try await waitUntil { service.presentation.activeCall?.id == currentCallID }

    gate.release(true)
    try await waitUntil { harness.permissionReturns == 2 }
    await settleTasks()

    XCTAssertEqual(harness.startOwners.count, 1)
    XCTAssertEqual(harness.startOwners[0].scope, harness.scope)
    XCTAssertEqual(harness.startOwners[0].generation, harness.generation)
    XCTAssertEqual(harness.startOwners[0].endpointID, "synthetic-endpoint-b")
    XCTAssertNotEqual(harness.startOwners[0].scope, oldScope)
    XCTAssertNotEqual(harness.startOwners[0].generation, oldGeneration)
    XCTAssertEqual(service.presentation.activeCall?.id, currentCallID)
    XCTAssertNil(service.lastErrorMessage)
    XCTAssertEqual(harness.transitionOwners.count, 0)
    // B's legitimate one-second poll may run while the simulator schedules the
    // held permission result. Only B's captured operation may own that work.
    XCTAssertTrue(harness.fetchOwners.allSatisfy { $0 == harness.startOwners[0] })
    XCTAssertFalse(harness.fetchOwners.contains { $0.scope == oldScope || $0.generation == oldGeneration })
  }

  func testOldStartResponseCannotInstallOrClearTheNewAccountAttempt() async throws {
    let harness = VoiceHostHarness()
    let gate = VoiceStartGate()
    let gateB = VoiceStartGate()
    harness.startGate = gate
    let service = harness.makeService()
    let oldID = UUID()
    let newID = UUID()
    defer {
      gate.release(syntheticSession(callID: oldID, roomID: "old-room"))
      gateB.release(syntheticSession(callID: newID, roomID: "new-room"))
      harness.stop(service)
    }
    service.startVoiceCall(roomID: "old-room", title: "Old synthetic call", participantSubjectIDs: nil)
    try await waitUntil { gate.entered }
    let oldOwner = harness.startOwners[0]
    harness.stop(service)
    XCTAssertTrue(service.hostState.serverAssistanceRequired)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(expectedScope: harness.scope, expectedGeneration: harness.generation)
    harness.startGate = gateB
    service.startVoiceCall(roomID: "new-room", title: "New synthetic call", participantSubjectIDs: nil)
    try await waitUntil { gateB.entered }
    gate.release(syntheticSession(callID: oldID, roomID: "old-room"))
    try await waitUntil { gate.returned }
    await settleTasks()
    harness.startGate = nil
    // A's late defer must not clear B's in-flight gate and permit a third start.
    service.startVoiceCall(roomID: "unexpected-room", title: "Unexpected synthetic call", participantSubjectIDs: nil)
    await settleTasks()
    XCTAssertEqual(harness.permissionRequests, 2)
    XCTAssertEqual(harness.startOwners.count, 2)
    XCTAssertFalse(service.hasActiveCall)
    gateB.release(syntheticSession(callID: newID, roomID: "new-room"))
    try await waitUntil { service.presentation.activeCall?.id == newID }

    XCTAssertEqual(harness.startOwners.count, 2)
    XCTAssertEqual(harness.startOwners[1].scope, harness.scope)
    XCTAssertNotEqual(harness.startOwners[1], oldOwner)
    XCTAssertEqual(service.presentation.activeCall?.id, newID)
    XCTAssertNil(service.lastErrorMessage)
    XCTAssertFalse(service.hostState.serverAssistanceRequired, "A's server start is not B's cleanup")
    XCTAssertTrue(harness.fetchOwners.allSatisfy { $0 == harness.startOwners[1] })
    XCTAssertEqual(harness.transitionOwners.count, 0, "OFF has no remote cancel/end bypass")
  }

  func testOldScopeStopCannotSuspendNewAccountOrItsCall() throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService()
    defer { harness.stop(service) }
    let oldScope = harness.scope
    let oldGeneration = harness.generation
    harness.stop(service)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    )
    let currentBinding = harness.bindings[1]
    let callID = UUID()
    service.receive(payload: incomingPayload(callID), binding: currentBinding) {}
    harness.reporters[1].completeReport(at: 0, succeeded: true)

    XCTAssertEqual(service.suspend(expectedScope: oldScope, expectedGeneration: oldGeneration), .ownerMismatch)
    XCTAssertFalse(service.hostState.suspended)
    XCTAssertFalse(currentBinding.retired)
    XCTAssertEqual(service.presentation.activeCall?.id, callID)
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testQueuedInAppNotificationFromOldOwnerCannotReconcileTheNewAccount() async throws {
    let harness = VoiceHostHarness()
    let service = harness.makeService(mode: .inApp)
    defer { harness.stop(service) }

    // Do not yield until A's callback has queued its task and ownership has
    // changed. The queued work must retain A rather than recapture B on entry.
    service.incomingUserNotificationReceived()
    harness.stop(service)
    harness.select(scope: "opaque-account-b", generation: UUID(), endpointID: "synthetic-endpoint-b")
    _ = try service.resumeForHostCommunication(
      expectedScope: harness.scope, expectedGeneration: harness.generation
    )
    await settleTasks()

    XCTAssertEqual(harness.listOwners.count, 0)
    XCTAssertEqual(harness.remoteOperationCount, 0)
    XCTAssertFalse(service.hasActiveCall)
    XCTAssertFalse(service.hostState.suspended)
    XCTAssertEqual(service.hostState.scope, "opaque-account-b")
  }

  func testAnsweredElsewhereUsesCapturedEndpointRatherThanAChangedProviderValue() {
    let harness = VoiceHostHarness(endpointID: "synthetic-original-endpoint")
    let service = harness.makeService()
    defer { harness.stop(service) }
    let binding = harness.bindings[0]
    let callID = UUID()
    service.receive(payload: incomingPayload(callID), binding: binding) {}
    harness.reporters[0].completeReport(at: 0, succeeded: true)
    harness.endpointID = "synthetic-later-endpoint"
    let endpointReads = harness.endpointReads
    var completions = 0
    var payload = incomingPayload(callID, event: "chat.voice_call.answered_elsewhere")
    payload["acceptedEndpointId"] = "synthetic-original-endpoint"

    service.receive(payload: payload, binding: binding) { completions += 1 }

    XCTAssertEqual(completions, 1)
    XCTAssertEqual(service.presentation.activeCall?.id, callID)
    XCTAssertEqual(harness.endpointReads, endpointReads)
    XCTAssertEqual(harness.remoteOperationCount, 0)
  }

  func testOnceCompletionClearsItsOperationBeforeReentrantFinish() {
    var calls = 0
    var once: VoiceCallOnceCompletion?
    once = VoiceCallOnceCompletion {
      calls += 1
      once?.finish()
    }

    once?.finish()
    once?.finish()

    XCTAssertEqual(calls, 1)
    XCTAssertEqual(once?.isPending, false)
  }

  private func incomingPayload(_ id: UUID, event: String = "chat.voice_call.incoming") -> [AnyHashable: Any] {
    ["type": event, "callId": id.uuidString, "roomId": "synthetic-room", "senderDisplayName": "Synthetic caller"]
  }

  private func observeTimeline(_ counter: VoiceTimelineCounter) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(forName: .csmVoiceCallTimelineChanged, object: nil, queue: nil) { _ in
      counter.increment()
    }
  }

  private func settleTasks() async {
    for _ in 0..<12 { await Task.yield() }
  }

  private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(2)
    while !condition() {
      guard Date() < deadline else { throw VoiceHostTestError.timeout }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

private enum VoiceHostTestError: Error { case timeout }

@MainActor
private final class VoicePermissionGate {
  private(set) var entered = false
  private var continuation: CheckedContinuation<Bool, Never>?
  private var result: Bool?

  func wait() async -> Bool {
    entered = true
    if let result { return result }
    return await withCheckedContinuation { continuation = $0 }
  }

  func release(_ value: Bool) {
    guard result == nil else { return }
    result = value
    let operation = continuation
    continuation = nil
    operation?.resume(returning: value)
  }
}

@MainActor
private final class VoiceStartGate {
  private(set) var entered = false
  private(set) var returned = false
  private var continuation: CheckedContinuation<CSMVoiceCallSession, Never>?
  private var result: CSMVoiceCallSession?
  func wait() async -> CSMVoiceCallSession {
    entered = true
    let value: CSMVoiceCallSession
    if let result { value = result } else { value = await withCheckedContinuation { continuation = $0 } }
    returned = true
    return value
  }
  func release(_ value: CSMVoiceCallSession) {
    guard result == nil else { return }
    result = value
    let operation = continuation
    continuation = nil
    operation?.resume(returning: value)
  }
}

@MainActor
private final class VoiceHeldIncomingReporter: VoiceCallIncomingReporting {
  enum Event: Equatable { case incoming(UUID), ended(UUID), completed }
  private(set) var events: [Event] = []
  private var reportCompletions: [@MainActor (Bool) -> Void] = []

  func reportIncoming(uuid: UUID, title: String, completion: @escaping @MainActor (Bool) -> Void) {
    events.append(.incoming(uuid))
    reportCompletions.append(completion)
  }

  func reportEnded(uuid: UUID) { events.append(.ended(uuid)) }
  func recordCompletion() { events.append(.completed) }

  // Retain the callback deliberately so tests can simulate duplicate OS results.
  func completeReport(at index: Int, succeeded: Bool) { reportCompletions[index](succeeded) }
  func completeReportIfPresent(at index: Int, succeeded: Bool) {
    if reportCompletions.indices.contains(index) { completeReport(at: index, succeeded: succeeded) }
  }
}

private final class VoiceTimelineCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.lock(); defer { lock.unlock() }; return count }
  func increment() { lock.lock(); defer { lock.unlock() }; count += 1 }
}

@MainActor
private final class VoiceHostHarness {
  var snapshot: CSMHostCommunicationSnapshot
  var endpointID: String
  var permissionGate: VoicePermissionGate?
  var startGate: VoiceStartGate?
  var startResult = syntheticSession(callID: UUID(), roomID: "synthetic-room")
  var listResult: [CSMVoiceCall] = []
  private(set) var endpointReads = 0
  private(set) var audioInitializations = 0
  private(set) var audioStops = 0
  private(set) var audioActivations = 0
  private(set) var permissionRequests = 0
  private(set) var permissionReturns = 0
  private(set) var bindings: [VoiceCallSystemBinding] = []
  private(set) var reporters: [VoiceHeldIncomingReporter] = []
  private(set) var startOwners: [VoiceCallOwner] = []
  private(set) var fetchOwners: [VoiceCallOwner] = []
  private(set) var listOwners: [VoiceCallOwner] = []
  private(set) var transitionOwners: [VoiceCallOwner] = []

  var scope: String { snapshot.scope! }
  var generation: UUID { snapshot.generation }
  var remoteOperationCount: Int { startOwners.count + fetchOwners.count + listOwners.count + transitionOwners.count }

  init(policy: CSMCommunicationActivationPolicy = .explicitHostConsent, enabled: Bool = true,
       endpointID: String = "synthetic-endpoint-a") {
    snapshot = .init(policy: policy, enabled: enabled, registrationRemovalPending: false,
      generation: UUID(), scope: "opaque-account-a")
    self.endpointID = endpointID
  }

  func select(scope: String, generation: UUID, endpointID: String) {
    snapshot = .init(policy: .explicitHostConsent, enabled: true, registrationRemovalPending: false,
      generation: generation, scope: scope)
    self.endpointID = endpointID
  }

  func makeService(mode: VoiceCallPresentationMode = .system,
                   policy: CSMCommunicationActivationPolicy = .explicitHostConsent) -> VoiceCallService {
    let controls = VoiceCallServiceControls(
      snapshot: { self.snapshot },
      endpointID: { self.endpointReads += 1; return self.endpointID },
      permission: {
        self.permissionRequests += 1
        let result: Bool
        if let gate = self.permissionGate { result = await gate.wait() } else { result = true }
        self.permissionReturns += 1
        return result
      },
      start: { _, _, _, owner in
        self.startOwners.append(owner)
        if let gate = self.startGate { return await gate.wait() }
        return self.startResult
      },
      fetch: { _, owner in self.fetchOwners.append(owner); throw CancellationError() },
      list: { owner in self.listOwners.append(owner); return self.listResult },
      transition: { _, _, _, _, owner in self.transitionOwners.append(owner); throw CancellationError() },
      initializeAudio: { self.audioInitializations += 1 },
      stopAudio: { self.audioStops += 1 },
      makeSystem: { _, epoch in
        let reporter = VoiceHeldIncomingReporter()
        let binding = VoiceCallSystemBinding(epoch: epoch, provider: nil, controller: nil,
          registry: nil, reporter: reporter)
        self.reporters.append(reporter)
        self.bindings.append(binding)
        return binding
      },
      activateSystemAudio: { self.audioActivations += 1 },
      observeHardware: false
    )
    return VoiceCallService(presentationMode: mode, activationPolicy: policy, controls: controls)
  }

  func stop(_ service: VoiceCallService) {
    _ = service.suspend(expectedScope: scope, expectedGeneration: generation)
  }
}

private func syntheticSession(callID: UUID, roomID: String,
                              direction: CSMVoiceCallDirection = .outgoing) -> CSMVoiceCallSession {
  let now = Date()
  let call = CSMVoiceCall(callId: callID.uuidString, connectedAt: nil, createdAt: now,
    direction: direction, endedAt: nil, endReason: nil, expiresAt: now.addingTimeInterval(90),
    initiatorSubjectId: "synthetic-subject", kind: .direct, participantSubjectIds: [],
    phase: .ringing, revision: 1, roomId: roomID, title: "Synthetic call", updatedAt: now)
  return .init(contractVersion: "cop-voice-call-v1", call: call, media: nil)
}
