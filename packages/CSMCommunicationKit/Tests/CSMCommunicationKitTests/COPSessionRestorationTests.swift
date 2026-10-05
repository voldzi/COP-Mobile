import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class COPSessionRestorationTests: XCTestCase {
    func testSameAccountRestorationPreservesEstablishedChat() async throws {
        let auth = RestorationAuth(); let model = await startedModel(auth)
        let subject = try XCTUnwrap(model.actor?.subjectId)
        let conversations = model.conversations.map(\.conversationId)
        XCTAssertFalse(conversations.isEmpty)
        try await model.reauthenticateCOPSession(expectedSubjectID: subject)
        XCTAssertEqual(model.authState, .signedIn)
        XCTAssertEqual(model.actor?.subjectId, subject)
        XCTAssertEqual(model.conversations.map(\.conversationId), conversations)
        XCTAssertEqual(auth.reauthenticationCount, 1)
        XCTAssertEqual(auth.signOutCount, 0)
    }
    func testTemporaryRestorationFailurePreservesEstablishedChat() async throws {
        let auth = RestorationAuth(); let model = await startedModel(auth)
        let subject = try XCTUnwrap(model.actor?.subjectId)
        let conversations = model.conversations.map(\.conversationId)
        auth.failure = URLError(.notConnectedToInternet)
        do { try await model.reauthenticateCOPSession(expectedSubjectID: subject); XCTFail("Must fail offline") }
        catch { XCTAssertEqual(CSMMobilityFailureKind.classify(error), .temporaryNetwork) }
        XCTAssertEqual(model.authState, .signedIn)
        XCTAssertEqual(model.actor?.subjectId, subject)
        XCTAssertEqual(model.conversations.map(\.conversationId), conversations)
        XCTAssertEqual(auth.signOutCount, 0)
    }
    func testDifferentSelectedAccountCannotStartRestoration() async {
        let auth = RestorationAuth(); let model = await startedModel(auth)
        do { try await model.reauthenticateCOPSession(expectedSubjectID: "other-synthetic-account"); XCTFail("Must reject changed actor") }
        catch { XCTAssertEqual(CSMMobilityFailureKind.classify(error), .accountChanged) }
        XCTAssertEqual(auth.reauthenticationCount, 0)
        XCTAssertEqual(auth.signOutCount, 0)
    }
    private func startedModel(_ auth: RestorationAuth) async -> CommunicationModel {
        let model = CommunicationModel(api: PreviewCopAPIClient(), messaging: PreviewMessagingClient(),
            localAI: DeterministicLocalAIService(), pushNotifications: RestorationPush(),
            authSession: auth, securityUnlock: PreviewSecurityUnlock())
        await model.start()
        // Seed the existing chat cache explicitly; OIDC restoration must not
        // depend on whether the preview Matrix transport boots in this test host.
        let cached = try! await PreviewCopAPIClient().conversations()
        model.conversationListStore.replace(cached, selection: cached.first, loadState: .loaded)
        return model
    }
}

@MainActor private final class RestorationAuth: AuthSessionManaging {
    var failure: (any Error)?
    var reauthenticationCount = 0
    var signOutCount = 0
    func canUseExistingSession() async -> Bool { true }
    func signIn() async throws {}
    func signOut() async throws { signOutCount += 1 }
    func reauthenticate(expectedSubjectID: String) async throws {
        reauthenticationCount += 1
        if let failure { throw failure }
    }
}
@MainActor private final class RestorationPush: PushNotificationManaging {
    var currentSnapshot: MobilePushSnapshot { .unavailable }
    func prepareForRemoteNotifications() async -> MobilePushSnapshot { .unavailable }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}
