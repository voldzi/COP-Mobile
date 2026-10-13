import Foundation
import XCTest
@testable import CSMCommunicationKit

@MainActor
final class HostCommunicationConsentTests: XCTestCase {
    private func configuration(_ mode: CSMCommunicationActivationPolicy = .explicitHostConsent) -> AppConfiguration {
        var value = AppConfiguration.preview
        value.communicationActivationPolicy = mode
        value.hostBundleID = "test.jizda.host-consent"
        return value
    }
    private func isolatedDefaults() -> UserDefaults {
        let name = "HostCommunicationConsentTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!
        value.removePersistentDomain(forName: name)
        return value
    }
    private func model(api: ConsentAPI, push: ConsentPush, auth: ConsentAuth,
                       messaging: any MessagingClientProtocol, defaults: UserDefaults,
                       mode: CSMCommunicationActivationPolicy = .explicitHostConsent,
                       registry: (any CSMMessagingDeviceRegistering)? = nil,
                       cleanup: ConsentCleanupStore = ConsentCleanupStore(),
                       cleanupHTTP: ConsentCleanupHTTP = ConsentCleanupHTTP(),
                       outbox: (any MessageOutboxStoring)? = nil) -> CommunicationModel {
        CommunicationModel(appConfiguration: configuration(mode), api: api, messaging: messaging,
            messageOutbox: outbox,
            localAI: DeterministicLocalAIService(), pushNotifications: push,
            messagingDeviceRegistration: registry, authSession: auth, securityUnlock: PreviewSecurityUnlock(),
            hostConsentDefaults: defaults, hostPusherCleanupStore: cleanup, hostPusherCleanupHTTP: cleanupHTTP)
    }

    func testBundlePolicyDefaultsAndUnknownValuesAreConservative() {
        XCTAssertEqual(AppConfiguration.fromInfoDictionary([:]).communicationActivationPolicy, .automatic)
        XCTAssertEqual(AppConfiguration.fromInfoDictionary(["CSMCommunicationActivationPolicy":"explicit_host_consent"]).communicationActivationPolicy, .explicitHostConsent)
        for invalid: Any in ["explicit", "", true, 1] {
            XCTAssertEqual(AppConfiguration.fromInfoDictionary(["CSMCommunicationActivationPolicy":invalid]).communicationActivationPolicy, .invalid)
        }
        XCTAssertEqual(AppConfiguration.fromInfoDictionary(["CFBundleIdentifier":"host.test"]).hostBundleID, "host.test")
    }

    func testColdRestoreRoutingAndForegroundDoNotBootstrapOptionalProducersBeforeConsent() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = StreamLifecycleMessaging()
        let outbox = ConsentOutbox()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults(), outbox: outbox)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        await runtime.prepare(expectedSubjectID: nil, allowInteractiveSignIn: false)
        await value.appDidBecomeActive()
        await runtime.refreshDeviceRegistration()
        _ = try? await runtime.drivingCapabilities()
        _ = try? await runtime.drivingRoutes(from: .init(latitude: 50, longitude: 14), to: .init(latitude: 50.1, longitude: 14.1))
        let bootstraps = await api.bootstrapCount, matrix = await api.messagingCount
        let registrations = await api.registrationCount, route = await api.routeCount, catalog = await api.catalogCount
        let configured = await messaging.configurationCount, pushers = await messaging.pusherCount
        XCTAssertEqual(value.authState, .signedIn)
        XCTAssertNotNil(runtime.mobilitySessionScope())
        XCTAssertGreaterThanOrEqual(bootstraps, 1)
        XCTAssertEqual(matrix, 0); XCTAssertEqual(registrations, 0)
        XCTAssertEqual(configured, 0); XCTAssertEqual(pushers, 0); XCTAssertEqual(push.prepareCount, 0)
        let outboxReads = await outbox.readCount
        XCTAssertEqual(outboxReads, 0)
        XCTAssertEqual(route, 1); XCTAssertEqual(catalog, 1)
        XCTAssertFalse(runtime.hostCommunicationSnapshot.enabled)
    }

    func testSingleAuthenticationEntryRemainsAuthenticationOnlyInExplicitHostMode() async {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(existing: false), messaging = StreamLifecycleMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.authenticationSignIn()
        await runtime.mobilitySignIn()
        XCTAssertEqual(auth.signInCount, 1)
        XCTAssertEqual(value.authState, .signedIn)
        XCTAssertEqual(push.prepareCount, 0)
        let count = await api.messagingCount
        XCTAssertEqual(count, 0)
    }

    func testAutomaticStandaloneRoutingRetainsExistingFullStartup() async {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = StreamLifecycleMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults(), mode: .automatic)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        _ = try? await runtime.drivingCapabilities()
        XCTAssertEqual(push.prepareCount, 1)
        let count = await api.messagingCount
        XCTAssertGreaterThan(count, 0)
    }

    func testConsentIsAccountAndBundleScopedAndWithdrawalPreservesAuthentication() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = StreamLifecycleMessaging()
        let defaults = isolatedDefaults()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: defaults)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let a = try XCTUnwrap(runtime.mobilitySessionScope())
        let enabled = try await runtime.setHostCommunicationEnabled(true, expectedScope: a)
        XCTAssertTrue(enabled.enabled)
        XCTAssertEqual(auth.signInCount, 0); XCTAssertEqual(auth.signOutCount, 0)
        let generation = enabled.generation
        let stopped = try await runtime.setHostCommunicationEnabled(false, expectedScope: a)
        XCTAssertFalse(stopped.enabled); XCTAssertFalse(stopped.registrationRemovalPending)
        XCTAssertNotEqual(generation, stopped.generation)
        XCTAssertEqual(runtime.mobilitySessionScope(), a)
        XCTAssertEqual(auth.signOutCount, 0)
        let enabledAgain = try await runtime.setHostCommunicationEnabled(true, expectedScope: a)
        XCTAssertTrue(enabledAgain.enabled)
        XCTAssertEqual(enabledAgain.scope, enabled.scope)
        XCTAssertNotEqual(enabledAgain.generation, enabled.generation)
        XCTAssertNotEqual(enabledAgain.generation, stopped.generation)
        let fresh = runtime.hostCommunicationSnapshot
        XCTAssertTrue(fresh.enabled)
        XCTAssertEqual(fresh.scope, a)
        XCTAssertEqual(fresh.generation, enabledAgain.generation)
        XCTAssertFalse(fresh.enabled && fresh.scope == enabled.scope && fresh.generation == enabled.generation,
                       "Old same-account capture must not authorize after off then on")
        let suspended = await messaging.suspendCount
        XCTAssertGreaterThan(suspended, 0)
        await api.selectSubject("synthetic-account-b")
        await value.refreshSession(authenticationOnly: true)
        XCTAssertFalse(runtime.hostCommunicationSnapshot.enabled)
        XCTAssertNotEqual(runtime.mobilitySessionScope(), a)
        do { _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: a); XCTFail("Foreign scope accepted") } catch { }
        XCTAssertFalse(runtime.hostCommunicationSnapshot.enabled)
        // No raw user IDs, tokens or E2EE recovery material in the consent store.
        let stored = defaults.dictionaryRepresentation()
        XCTAssertFalse(stored.keys.contains(where: { $0.contains("synthetic-account") }))
        XCTAssertFalse(stored.values.contains(where: { ($0 as? String)?.contains("synthetic") == true }))
    }

    func testConsentPersistsAcrossColdStartOnlyForTheSameHostAndAccount() async throws {
        let defaults = isolatedDefaults(), api = ConsentAPI()
        let first = model(api: api, push: ConsentPush(), auth: ConsentAuth(), messaging: StreamLifecycleMessaging(), defaults: defaults)
        let runtime = CSMCommunicationRuntime(model: first, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: XCTUnwrap(runtime.mobilitySessionScope()))
        let restored = model(api: api, push: ConsentPush(), auth: ConsentAuth(), messaging: StreamLifecycleMessaging(), defaults: defaults)
        await restored.start(authenticationOnly: true)
        XCTAssertTrue(restored.hostCommunicationEnabled)
        var another = configuration(); another.hostBundleID = "test.cop.other-host"
        let foreign = CommunicationModel(appConfiguration: another, api: api, messaging: StreamLifecycleMessaging(), localAI: DeterministicLocalAIService(),
            pushNotifications: ConsentPush(), authSession: ConsentAuth(), securityUnlock: PreviewSecurityUnlock(), hostConsentDefaults: defaults)
        await foreign.start(authenticationOnly: true)
        XCTAssertFalse(foreign.hostCommunicationEnabled)
        await api.selectSubject("synthetic-account-b")
        await restored.refreshSession(authenticationOnly: true)
        XCTAssertFalse(restored.hostCommunicationEnabled)
    }

    func testWithdrawalFencesDelayedPushPreparationWithoutSigningOut() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = StreamLifecycleMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        push.pauseNextPreparation = true
        let enabling = Task { try await runtime.setHostCommunicationEnabled(true, expectedScope: scope) }
        try await waitUntil { push.isPaused }
        let stopped = try await runtime.setHostCommunicationEnabled(false, expectedScope: scope)
        XCTAssertFalse(stopped.enabled)
        push.releasePreparation()
        _ = try await enabling.value
        let matrix = await api.messagingCount, configured = await messaging.configurationCount
        XCTAssertEqual(matrix, 0); XCTAssertEqual(configured, 0)
        XCTAssertEqual(auth.signOutCount, 0)
        XCTAssertFalse(runtime.hostCommunicationSnapshot.enabled)
    }

    func testSharingAndDispatchFailBeforeTokenOrNetworkWhileCleanupRemainsAvailable() async throws {
        XCTAssertTrue(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/shared-vehicles/v1/vehicles", method: "GET"))
        XCTAssertTrue(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/private-dispatch/v1/shares", method: "POST"))
        XCTAssertTrue(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/driver-measurements/v1/consent", method: "POST"))
        XCTAssertTrue(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/driver-measurements/v1/batches", method: "POST"))
        XCTAssertFalse(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/driver-measurements/v1/consent", method: "GET"))
        XCTAssertFalse(CSMHostCommunicationRequestPolicy.requiresConsent(path: "/api/v1/driver-measurements/v1/consent", method: "DELETE"))
        for path in ["/api/v1/private-dispatch/v1/shares/abc/stop", "/api/v1/private-dispatch/v1/shares/cancel-start", "/api/v1/private-dispatch/v1/devices/revoke"] {
            XCTAssertFalse(CSMHostCommunicationRequestPolicy.requiresConsent(path: path, method: "POST"))
            XCTAssertTrue(CSMHostCommunicationRequestPolicy.requiresConsent(path: path, method: "GET"))
        }
        let api = ConsentAPI()
        let value = model(api: api, push: ConsentPush(), auth: ConsentAuth(), messaging: StreamLifecycleMessaging(), defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        do { _ = try await runtime.sharedVehicles(expectedScope: XCTUnwrap(runtime.mobilitySessionScope())); XCTFail("Disabled sharing performed HTTP") }
        catch let error as CSMServiceError {
            guard case .disabled = error else { XCTFail("Did not stop at the consent boundary"); return }
        }
    }

    func testOldAccountConsentCannotAuthorizeCallbacksDuringNewIdentityBootstrap() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = StreamLifecycleMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: XCTUnwrap(runtime.mobilitySessionScope()))
        auth.existing = false
        await value.refreshSession()
        XCTAssertEqual(value.authState, .signedOut)
        let pause = ConsentPause()
        await api.selectSubject("synthetic-account-b")
        await api.pauseBootstrap(pause)
        let pushBefore = push.prepareCount, matrixBefore = await api.messagingCount
        let signingIn = Task { await value.signIn(authenticationOnly: true) }
        try await waitAsync { await pause.entered }
        XCTAssertFalse(value.communicationProducersPermitted)
        await runtime.refreshDeviceRegistration()
        await pause.release()
        await signingIn.value
        XCTAssertEqual(push.prepareCount, pushBefore)
        let matrixAfter = await api.messagingCount
        XCTAssertEqual(matrixAfter, matrixBefore)
        XCTAssertEqual(value.actor?.subjectId, "synthetic-account-b")
        XCTAssertFalse(value.communicationProducersPermitted)
    }

    func testOldAccountTeardownCannotSuspendNewAccountAfterLocationStopAwait() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: scope)
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        try await value.startLiveLocationShare(durationSeconds: 900, in: conversation,
            locationProvider: { .init(latitude: 50, longitude: 14) })
        let stopPause = ConsentPause()
        await messaging.pauseStop(stopPause)
        let stopping = Task { try await runtime.setHostCommunicationEnabled(false, expectedScope: scope) }
        try await waitAsync { await stopPause.entered }
        await api.selectSubject("synthetic-account-b")
        await value.refreshSession(authenticationOnly: true)
        let before = await messaging.suspendCount
        await stopPause.release()
        do { _ = try await stopping.value; XCTFail("Stale owner returned current result") } catch { }
        let after = await messaging.suspendCount
        XCTAssertEqual(after, before, "A's delayed teardown must not suspend B")
        XCTAssertEqual(value.actor?.subjectId, "synthetic-account-b")
    }

    func testNewAccountWithdrawalFencesImmediatelyBeforeAwaitingOldAccountTeardown() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await api.selectSubject("synthetic-account-b")
        await runtime.prepareAuthentication()
        let b = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: b)
        await api.selectSubject("synthetic-account-a")
        await value.refreshSession(authenticationOnly: true)
        let a = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: a)
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        try await value.startLiveLocationShare(durationSeconds: 900, in: conversation,
            locationProvider: { .init(latitude: 50, longitude: 14) })
        let pause = ConsentPause()
        await messaging.pauseStop(pause)
        let offA = Task { try await runtime.setHostCommunicationEnabled(false, expectedScope: a) }
        try await waitAsync { await pause.entered }
        await api.selectSubject("synthetic-account-b")
        await value.refreshSession(authenticationOnly: true)
        XCTAssertTrue(value.communicationProducersPermitted)
        let offB = Task { try await runtime.setHostCommunicationEnabled(false, expectedScope: b) }
        try await waitUntil { !value.communicationProducersPermitted }
        XCTAssertFalse(runtime.hostCommunicationSnapshot.enabled)
        await pause.release()
        do { _ = try await offA.value; XCTFail("Old account completed against B") } catch { }
        let stoppedB = try await offB.value
        XCTAssertFalse(stoppedB.enabled)
        XCTAssertEqual(runtime.mobilitySessionScope(), b)
    }

    func testOffDuringMessagingBootstrapAndConfigurationCannotResumeTransport() async throws {
        for duringConfiguration in [false, true] {
            let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging()
            let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
            let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
            await runtime.prepareAuthentication()
            let scope = try XCTUnwrap(runtime.mobilitySessionScope()), pause = ConsentPause()
            if duringConfiguration { await messaging.pauseConfiguration(pause) }
            else { await api.pauseMessaging(pause) }
            let starting = Task { try await runtime.setHostCommunicationEnabled(true, expectedScope: scope) }
            try await waitAsync { await pause.entered }
            _ = try await runtime.setHostCommunicationEnabled(false, expectedScope: scope)
            await pause.release()
            _ = try await starting.value
            let active = await messaging.configured
            XCTAssertFalse(active)
            XCTAssertFalse(value.communicationProducersPermitted)
        }
    }

    func testLateDeviceRegistrationIsRemovedAndOutageRemainsPendingUntilRetry() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging(), registry = ConsentRegistry()
        push.currentSnapshot = .init(authorization: .authorized, deviceToken: "synthetic-apns-a", environment: "development", registrationRequestedAt: nil, lastFailure: nil)
        let cleanup = ConsentCleanupStore(), cleanupHTTP = ConsentCleanupHTTP(), defaults = isolatedDefaults()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: defaults,
            registry: registry, cleanup: cleanup, cleanupHTTP: cleanupHTTP)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope()), pause = ConsentPause()
        await registry.pauseRegistration(pause)
        await registry.setFailDelete(true)
        let starting = Task { try await runtime.setHostCommunicationEnabled(true, expectedScope: scope) }
        try await waitAsync { await pause.entered }
        let stopping = Task { try await runtime.setHostCommunicationEnabled(false, expectedScope: scope) }
        await pause.release()
        _ = try await starting.value
        let pending = try await stopping.value
        XCTAssertFalse(pending.enabled); XCTAssertTrue(pending.registrationRemovalPending)
        let attempts = await registry.deletedIDs
        XCTAssertEqual(attempts, ["synthetic-own-installation"])
        // New process, same identity; retry does not register push or Matrix.
        let restartedPush = ConsentPush()
        let restartedMessaging = ConsentMessaging()
        let restarted = model(api: api, push: restartedPush, auth: ConsentAuth(), messaging: restartedMessaging,
            defaults: defaults, registry: registry, cleanup: cleanup, cleanupHTTP: cleanupHTTP)
        let restored = CSMCommunicationRuntime(model: restarted, driverReportService: DriverReportService(api: api))
        await restored.prepareAuthentication()
        await registry.setFailDelete(false)
        let completed = try await restored.retryHostCommunicationRegistrationRemoval(expectedScope: scope)
        XCTAssertFalse(completed.registrationRemovalPending)
        XCTAssertFalse(completed.enabled)
        XCTAssertEqual(restartedPush.prepareCount, 0)
        let configured = await restartedMessaging.configurationCount
        XCTAssertEqual(configured, 0)
    }

    func testPusherOffRaceAndColdRestartTokenRotationRetryUseExactSecureTargetWithoutClient() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging()
        push.currentSnapshot = .init(authorization: .authorized, deviceToken: "synthetic-old-apns", environment: "development", registrationRequestedAt: nil, lastFailure: nil)
        let defaults = isolatedDefaults(), store = ConsentCleanupStore(), http = ConsentCleanupHTTP(), pause = ConsentPause()
        await http.setFail(true)
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: defaults, cleanup: store, cleanupHTTP: http)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        await messaging.pausePusher(pause)
        let starting = Task { try await runtime.setHostCommunicationEnabled(true, expectedScope: scope) }
        try await waitAsync { await pause.entered }
        let stopping = Task { try await runtime.setHostCommunicationEnabled(false, expectedScope: scope) }
        await pause.release()
        _ = try await starting.value
        let pending = try await stopping.value
        XCTAssertTrue(pending.registrationRemovalPending); XCTAssertFalse(pending.enabled)
        let restartedPush = ConsentPush(), restartedMessaging = ConsentMessaging()
        restartedPush.currentSnapshot = .init(authorization: .authorized, deviceToken: "synthetic-rotated-apns", environment: "development", registrationRequestedAt: nil, lastFailure: nil)
        let restarted = model(api: api, push: restartedPush, auth: ConsentAuth(), messaging: restartedMessaging,
            defaults: defaults, cleanup: store, cleanupHTTP: http)
        let restored = CSMCommunicationRuntime(model: restarted, driverReportService: DriverReportService(api: api))
        await restored.prepareAuthentication()
        await http.setFail(false)
        let completed = try await restored.retryHostCommunicationRegistrationRemoval(expectedScope: scope)
        XCTAssertFalse(completed.registrationRemovalPending)
        let exact = await http.targets
        XCTAssertTrue(exact.count >= 2)
        XCTAssertTrue(exact.allSatisfy { $0.pushKey == "synthetic-old-apns" && $0.appID == "test.jizda.host-consent" })
        let configured = await restartedMessaging.configurationCount
        XCTAssertEqual(configured, 0); XCTAssertEqual(restartedPush.prepareCount, 0)
        let stored = defaults.dictionaryRepresentation()
        XCTAssertFalse(stored.values.contains { String(describing: $0).contains("synthetic-old-apns") })
        XCTAssertFalse(stored.values.contains { String(describing: $0).contains("synthetic-rotated-apns") })
    }

    func testUnknownDeviceRegistrationOutcomeCannotBecomeCompletedAfterRestart() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), registry = ConsentRegistry()
        push.currentSnapshot = .init(authorization: .authorized, deviceToken: "synthetic-apns", environment: "development", registrationRequestedAt: nil, lastFailure: nil)
        await registry.setFailRegister(true)
        let defaults = isolatedDefaults(), store = ConsentCleanupStore(), http = ConsentCleanupHTTP()
        let value = model(api: api, push: push, auth: auth, messaging: ConsentMessaging(), defaults: defaults,
            registry: registry, cleanup: store, cleanupHTTP: http)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: scope)
        let pending = try await runtime.setHostCommunicationEnabled(false, expectedScope: scope)
        XCTAssertTrue(pending.registrationRemovalPending)
        let restarted = model(api: api, push: ConsentPush(), auth: ConsentAuth(), messaging: ConsentMessaging(), defaults: defaults,
            registry: registry, cleanup: store, cleanupHTTP: http)
        let restored = CSMCommunicationRuntime(model: restarted, driverReportService: DriverReportService(api: api))
        await restored.prepareAuthentication()
        let retried = try await restored.retryHostCommunicationRegistrationRemoval(expectedScope: scope)
        XCTAssertTrue(retried.registrationRemovalPending)
        XCTAssertFalse(retried.enabled)
        do { _ = try await restored.setHostCommunicationEnabled(true, expectedScope: scope); XCTFail("Unknown registration outcome ignored") } catch { }
    }

    func testCleanupHTTPRequestContainsOnlyTheExactOwnedRemovalAndRejectsRedirectOrError() async throws {
        let transport = ConsentHTTPTransport()
        let http = HostPusherCleanupHTTP(transport: transport)
        let target = HostPusherCleanupTarget(pushKey: "synthetic-old-apns", appID: "own.bundle", homeserverURL: URL(string: "https://matrix.test")!, accessToken: "synthetic-matrix-token")
        try await http.remove(target)
        let captured = await transport.request
        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.url?.absoluteString, "https://matrix.test/_matrix/client/v3/pushers/set")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-matrix-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["pushkey", "app_id", "kind"])
        XCTAssertEqual(body["pushkey"] as? String, target.pushKey)
        XCTAssertEqual(body["app_id"] as? String, target.appID)
        XCTAssertTrue(body["kind"] is NSNull)
        for status in [302, 401, 429, 503] {
            await transport.setStatus(status)
            do { try await http.remove(target); XCTFail("Unconfirmed removal accepted") } catch { }
        }
        await transport.setStatus(200)
        await transport.setWrongOrigin(true)
        do { try await http.remove(target); XCTFail("Redirected response accepted") } catch { }
    }

    func testCarPlayAndStalePhoneCallbacksCannotRestoreRetainedWrapperDuringPendingCleanup() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), live = ConsentMessaging()
        push.currentSnapshot = .init(authorization: .authorized, deviceToken: "synthetic-retained-apns", environment: "development", registrationRequestedAt: nil, lastFailure: nil)
        let outbox = ConsentOutbox(), wrapper = OfflineFirstMessagingClient(liveClient: live, outbox: outbox)
        let http = ConsentCleanupHTTP()
        await http.setFail(true)
        let value = model(api: api, push: push, auth: auth, messaging: wrapper, defaults: isolatedDefaults(), cleanupHTTP: http)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        await runtime.prepareAuthentication()
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: scope)
        let conversations = try await PreviewCopAPIClient().conversations()
        let conversation = try XCTUnwrap(conversations.first)
        await value.selectConversation(conversation)
        let stopped = try await runtime.setHostCommunicationEnabled(false, expectedScope: scope)
        XCTAssertTrue(stopped.registrationRemovalPending)
        let configurationsBefore = await live.configurationCount, readsBefore = await live.messagesCount, outboxBefore = await outbox.readCount
        do { _ = try await runtime.carPlayConversations(); XCTFail("Disabled CarPlay list accepted") } catch { }
        do { _ = try await runtime.carPlayMessages(conversationID: conversation.conversationId); XCTFail("Disabled CarPlay read accepted") } catch { }
        do { _ = try await runtime.sendCarPlayMessage("synthetic", conversationID: conversation.conversationId); XCTFail("Disabled CarPlay send accepted") } catch { }
        await value.selectConversation(conversation)
        let preview = PreviewMessagingClient()
        let bootstrap = try await PreviewCopAPIClient().messagingBootstrap(deviceId: "synthetic-fixture")
        try await preview.configure(with: bootstrap)
        let messages = try await preview.messages(for: conversation)
        if let message = messages.first {
            await value.toggleReaction("👍", on: message)
            await value.togglePinnedMessage(message)
        }
        let configurationsAfter = await live.configurationCount, readsAfter = await live.messagesCount, outboxAfter = await outbox.readCount
        XCTAssertEqual(configurationsAfter, configurationsBefore)
        XCTAssertEqual(readsAfter, readsBefore)
        XCTAssertEqual(outboxAfter, outboxBefore)
    }

    func testVoiceDefaultNilIntentCapturedAsACannotCallHTTPAsEnabledBWhileStartIsPaused() async throws {
        let api = ConsentAPI(), push = ConsentPush(), auth = ConsentAuth(), messaging = ConsentMessaging()
        let value = model(api: api, push: push, auth: auth, messaging: messaging, defaults: isolatedDefaults())
        // Prime the model directly so the fresh Runtime still owns a real
        // startIfNeeded await while A already has verified active intent.
        await api.selectSubject("synthetic-account-b")
        await value.start(authenticationOnly: true)
        try await value.setHostCommunicationEnabled(true)
        await api.selectSubject("synthetic-account-a")
        await value.refreshSession(authenticationOnly: true)
        try await value.setHostCommunicationEnabled(true)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        let capturedA = runtime.hostCommunicationSnapshot
        XCTAssertTrue(capturedA.enabled)
        let scopeA = try XCTUnwrap(capturedA.scope), pause = ConsentPause()
        auth.nextRestorePause = pause
        let startingA = Task {
            try await runtime.startVoiceCall(roomID: "synthetic-room", title: "Synthetic")
        }
        defer { startingA.cancel(); Task { await pause.release() } }
        try await waitAsync { await pause.entered }
        await api.selectSubject("synthetic-account-b")
        await value.signIn(authenticationOnly: true)
        let currentB = runtime.hostCommunicationSnapshot
        XCTAssertTrue(currentB.enabled, "B must be enabled; this must prove identity fencing rather than the ordinary off gate")
        XCTAssertNotEqual(currentB.scope, scopeA)
        await pause.release()
        do { _ = try await startingA.value; XCTFail("A intent started a call as B") }
        catch is CancellationError { }
        let starts = await api.voiceStartCount
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(runtime.hostCommunicationSnapshot.scope, currentB.scope)
    }

    func testAllVoiceEntriesFailBeforeStartupWhenExplicitHostIsOffAndRejectIncompleteFences() async throws {
        let api = ConsentAPI(), auth = ConsentAuth()
        let value = model(api: api, push: ConsentPush(), auth: auth, messaging: ConsentMessaging(), defaults: isolatedDefaults())
        await value.start(authenticationOnly: true)
        let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
        let restoreCount = auth.restoreCount
        let offCalls: [@MainActor () async throws -> Void] = [
            { _ = try await runtime.startVoiceCall(roomID: "synthetic", title: nil) },
            { _ = try await runtime.voiceCall(callID: "synthetic") },
            { _ = try await runtime.activeVoiceCalls() },
            { _ = try await runtime.transitionVoiceCall(callID: "synthetic", action: .end, expectedRevision: 1) }
        ]
        for call in offCalls {
            do { try await call(); XCTFail("Disabled voice entry accepted") }
            catch CSMVoiceCallControlError.authenticationRequired { }
        }
        XCTAssertEqual(auth.restoreCount, restoreCount)
        let offControlCount = await api.voiceControlCount
        XCTAssertEqual(offControlCount, 0)
        let scope = try XCTUnwrap(runtime.mobilitySessionScope())
        _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: scope)
        let current = runtime.hostCommunicationSnapshot
        let enabledControlCount = await api.voiceControlCount
        let invalidCalls: [@MainActor () async throws -> Void] = [
            { _ = try await runtime.startVoiceCall(roomID: "synthetic", title: nil, expectedScope: scope) },
            { _ = try await runtime.voiceCall(callID: "synthetic", expectedGeneration: current.generation) },
            { _ = try await runtime.activeVoiceCalls(expectedScope: scope, expectedGeneration: UUID()) },
            { _ = try await runtime.transitionVoiceCall(callID: "synthetic", action: .end, expectedRevision: 1,
                                                       expectedScope: "", expectedGeneration: current.generation) }
        ]
        for call in invalidCalls {
            do { try await call(); XCTFail("Incomplete or mismatched voice fence accepted") }
            catch CSMVoiceCallControlError.authenticationRequired { }
        }
        let calls = await api.voiceControlCount
        XCTAssertEqual(calls, enabledControlCount)
    }

    func testValidExplicitVoiceFenceAndAutomaticDefaultNilRemainUsable() async throws {
        for mode in [CSMCommunicationActivationPolicy.explicitHostConsent, .automatic] {
            let api = ConsentAPI()
            let value = model(api: api, push: ConsentPush(), auth: ConsentAuth(), messaging: ConsentMessaging(),
                defaults: isolatedDefaults(), mode: mode)
            let runtime = CSMCommunicationRuntime(model: value, driverReportService: DriverReportService(api: api))
            if mode == .explicitHostConsent {
                await runtime.prepareAuthentication()
                _ = try await runtime.setHostCommunicationEnabled(true, expectedScope: XCTUnwrap(runtime.mobilitySessionScope()))
                let captured = runtime.hostCommunicationSnapshot
                _ = try await runtime.activeVoiceCalls(expectedScope: captured.scope, expectedGeneration: captured.generation)
            } else {
                // No pre-authentication/capture for the legacy automatic path.
                _ = try await runtime.activeVoiceCalls()
            }
            let reads = await api.voiceActiveListCount
            XCTAssertEqual(reads, 1)
        }
    }

    private func waitAsync(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic boundary did not reach its pause")
        throw CancellationError()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Synthetic boundary did not reach its pause")
        throw CancellationError()
    }
}

@MainActor private final class ConsentAuth: AuthSessionManaging {
    var existing: Bool
    var signInCount = 0, signOutCount = 0
    var restoreCount = 0
    var nextRestorePause: ConsentPause?
    init(existing: Bool = true) { self.existing = existing }
    func canUseExistingSession() async -> Bool {
        restoreCount += 1
        if let pause = nextRestorePause { nextRestorePause = nil; await pause.wait() }
        return existing
    }
    func signIn() async throws { existing = true; signInCount += 1 }
    func signOut() async throws { existing = false; signOutCount += 1 }
}
@MainActor private final class ConsentPush: PushNotificationManaging {
    var currentSnapshot = MobilePushSnapshot.unavailable
    var prepareCount = 0
    var pauseNextPreparation = false
    var isPaused = false
    private var pending: CheckedContinuation<Void, Never>?
    func prepareForRemoteNotifications() async -> MobilePushSnapshot {
        prepareCount += 1
        if pauseNextPreparation {
            pauseNextPreparation = false; isPaused = true
            await withCheckedContinuation { pending = $0 }
        }
        return currentSnapshot
    }
    func releasePreparation() { isPaused = false; pending?.resume(); pending = nil }
    func recordDeviceToken(_ deviceToken: Data) {}
    func recordRegistrationFailure(_ error: any Error) {}
    func recordRemoteNotification(_ payload: CSMRemoteNotificationPayload) {}
}

private actor ConsentAPI: CopAPIClientProtocol {
    private(set) var bootstrapCount = 0
    private(set) var messagingCount = 0
    private(set) var registrationCount = 0
    private(set) var routeCount = 0
    private(set) var catalogCount = 0
    private(set) var voiceStartCount = 0, voiceListCount = 0, voiceActiveListCount = 0, voiceLookupCount = 0, voiceTransitionCount = 0
    var voiceControlCount: Int { voiceStartCount + voiceListCount + voiceLookupCount + voiceTransitionCount }
    var subject = "synthetic-account-a"
    var bootstrapPause: ConsentPause?, messagingPause: ConsentPause?
    func pauseBootstrap(_ pause: ConsentPause) { bootstrapPause = pause }
    func pauseMessaging(_ pause: ConsentPause) { messagingPause = pause }
    func selectSubject(_ subject: String) { self.subject = subject }
    func bootstrap(seconds: Int) async throws -> MobileBootstrap {
        bootstrapCount += 1
        if let pause = bootstrapPause { bootstrapPause = nil; await pause.wait() }
        var value = try await PreviewCopAPIClient().bootstrap(seconds: seconds)
        value.actor.subjectId = subject
        value.capabilities.pushNotifications = true
        return value
    }
    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap {
        messagingCount += 1
        if let pause = messagingPause { messagingPause = nil; await pause.wait() }
        return try await PreviewCopAPIClient().messagingBootstrap(deviceId: deviceId)
    }
    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int) async throws -> [CSMVoiceCall] {
        voiceListCount += 1
        if activeOnly && roomId == nil { voiceActiveListCount += 1 }
        return []
    }
    func drivingCapabilities() async throws -> CSMDriverRoutingCatalog { catalogCount += 1; return try await PreviewCopAPIClient().drivingCapabilities() }
    func drivingRoutes(_ request: CSMDriverRouteRequest) async throws -> CSMDriverRouteResponse { routeCount += 1; return try await PreviewCopAPIClient().drivingRoutes(request) }
    func offlineSnapshot(seconds: Int) async throws -> MobileOfflineSnapshot { return try await PreviewCopAPIClient().offlineSnapshot(seconds: seconds) }
    func mapCatalog(locale: String, includeDiagnostics: Bool, includePartner: Bool) async throws -> MapLayerCatalog { return try await PreviewCopAPIClient().mapCatalog(locale: locale, includeDiagnostics: includeDiagnostics, includePartner: includePartner) }
    func mapFeatures(_ request: MapFeatureQueryRequest) async throws -> MapFeatureQueryResponse { return try await PreviewCopAPIClient().mapFeatures(request) }
    func transitVehicleDetail(featureId: String, sourceId: String?) async throws -> TransitVehicleDetail { return try await PreviewCopAPIClient().transitVehicleDetail(featureId: featureId, sourceId: sourceId) }
    func mapRasterOverlayImage(url: String) async throws -> Data { return try await PreviewCopAPIClient().mapRasterOverlayImage(url: url) }
    func weatherWebcamResource(url: String) async throws -> Data { return try await PreviewCopAPIClient().weatherWebcamResource(url: url) }
    func weatherRadarFrames(product: String, hours: Int, limit: Int) async throws -> WeatherRadarFrameCatalog { return try await PreviewCopAPIClient().weatherRadarFrames(product: product, hours: hours, limit: limit) }
    func sketchPalettes() async throws -> SketchPaletteCatalog { return try await PreviewCopAPIClient().sketchPalettes() }
    func sketchDrawings(bbox: MapFeatureBoundingBox?, limit: Int) async throws -> SketchDrawingCollection { return try await PreviewCopAPIClient().sketchDrawings(bbox: bbox, limit: limit) }
    func sketchDrawing(drawingId: String) async throws -> SketchDrawing { return try await PreviewCopAPIClient().sketchDrawing(drawingId: drawingId) }
    func createSketchDrawing(_ request: SketchDrawingCreateRequest) async throws -> SketchDrawing { return try await PreviewCopAPIClient().createSketchDrawing(request) }
    func updateSketchDrawing(drawingId: String, request: SketchDrawingUpdateRequest) async throws -> SketchDrawing { return try await PreviewCopAPIClient().updateSketchDrawing(drawingId: drawingId, request: request) }
    func deleteSketchDrawing(drawingId: String) async throws { try await PreviewCopAPIClient().deleteSketchDrawing(drawingId: drawingId) }
    func userPreferenceProfile() async throws -> UserPreferenceProfile { return try await PreviewCopAPIClient().userPreferenceProfile() }
    func updateUserPreferences(_ update: UserPreferenceUpdate) async throws -> UserPreferenceProfile { return try await PreviewCopAPIClient().updateUserPreferences(update) }
    func alerts(includeAcknowledged: Bool) async throws -> [CopAlert] { return try await PreviewCopAPIClient().alerts(includeAcknowledged: includeAcknowledged) }
    func acknowledgeAlert(alertId: String, note: String?) async throws -> CopAlert { return try await PreviewCopAPIClient().acknowledgeAlert(alertId: alertId, note: note) }
    func messagingStatus() async throws -> MessagingStatus { return try await PreviewCopAPIClient().messagingStatus() }
    func messagingIdentityLookup(conversationId: String) async throws -> MessagingIdentityLookup { return try await PreviewCopAPIClient().messagingIdentityLookup(conversationId: conversationId) }
    func startVoiceCall(_ request: CSMVoiceCallStartRequest) async throws -> CSMVoiceCallSession { voiceStartCount += 1; return try await PreviewCopAPIClient().startVoiceCall(request) }
    func voiceCall(callId: String) async throws -> CSMVoiceCallSession { voiceLookupCount += 1; return try await PreviewCopAPIClient().voiceCall(callId: callId) }
    func transitionVoiceCall(callId: String, request: CSMVoiceCallActionRequest) async throws -> CSMVoiceCallSession { voiceTransitionCount += 1; return try await PreviewCopAPIClient().transitionVoiceCall(callId: callId, request: request) }
    func startVoiceCall(_ request: CSMVoiceCallStartRequest, voiceScope: VoiceOutboundScope) async throws -> CSMVoiceCallSession {
        try await MainActor.run { try voiceScope.validateCurrent() }
        return try await startVoiceCall(request)
    }
    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int, voiceScope: VoiceOutboundScope) async throws -> [CSMVoiceCall] {
        try await MainActor.run { try voiceScope.validateCurrent() }
        return try await voiceCalls(roomId: roomId, activeOnly: activeOnly, limit: limit)
    }
    func voiceCall(callId: String, voiceScope: VoiceOutboundScope) async throws -> CSMVoiceCallSession {
        try await MainActor.run { try voiceScope.validateCurrent() }
        return try await voiceCall(callId: callId)
    }
    func transitionVoiceCall(callId: String, request: CSMVoiceCallActionRequest, voiceScope: VoiceOutboundScope) async throws -> CSMVoiceCallSession {
        try await MainActor.run { try voiceScope.validateCurrent() }
        return try await transitionVoiceCall(callId: callId, request: request)
    }
    func mobilePairingSession(code: String) async throws -> MobilePairingSessionResponse { return try await PreviewCopAPIClient().mobilePairingSession(code: code) }
    func claimMobilePairingSession(code: String, request: MobilePairingClaimRequest) async throws -> MobilePairingSessionResponse { return try await PreviewCopAPIClient().claimMobilePairingSession(code: code, request: request) }
    func conversations() async throws -> [Conversation] { return try await PreviewCopAPIClient().conversations() }
    func queryAIChatAgent(_ request: CopAIChatAgentRequest) async throws -> CopAIChatAgentResponse { return try await PreviewCopAPIClient().queryAIChatAgent(request) }
    func registerDevice(_ registration: MobileDeviceRegistration) async throws -> MobileDeviceRegistrationResponse { registrationCount += 1; return try await PreviewCopAPIClient().registerDevice(registration) }
    func deviceRegistrationTicket(appInstanceId: String, bundleId: String) async throws -> MobileDeviceRegistrationTicketResponse {
        .init(contractVersion: "synthetic-ticket", expiresAt: .now.addingTimeInterval(60),
            messagingBaseUrl: URL(string: "https://msg.zeleznalady.cz")!, ticket: "synthetic-ticket")
    }
    func submitCommunityReport(_ draft: CommunityReportDraft) async throws -> CommunityReportSubmission { return try await PreviewCopAPIClient().submitCommunityReport(draft) }
    func communityReports(query: DriverReportQuery?) async throws -> [CommunityReport] { return try await PreviewCopAPIClient().communityReports(query: query) }
    func confirmCommunityReport(reportId: String, value: CommunityReportConfirmationValue) async throws -> CommunityReport { return try await PreviewCopAPIClient().confirmCommunityReport(reportId: reportId, value: value) }
}

private actor ConsentPause {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor ConsentMessaging: MessagingClientProtocol, MessagingLifecycleControlling, MessagingSessionInvalidating, MessagingLiveLocationSharing {
    private(set) var configurationCount = 0, suspendCount = 0
    private(set) var configured = false
    private(set) var messagesCount = 0
    private var revision = 0
    private var configurePause: ConsentPause?, pusherPause: ConsentPause?, stopPause: ConsentPause?
    func pauseConfiguration(_ pause: ConsentPause) { configurePause = pause }
    func pausePusher(_ pause: ConsentPause) { pusherPause = pause }
    func pauseStop(_ pause: ConsentPause) { stopPause = pause }
    func configure(with bootstrap: MessagingBootstrap) async throws {
        let epoch = revision
        configurationCount += 1
        if let pause = configurePause { configurePause = nil; await pause.wait() }
        guard epoch == revision else { throw CancellationError() }
        configured = true
    }
    func messages(for conversation: Conversation) async throws -> [ChatMessage] { messagesCount += 1; return [] }
    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage { throw CancellationError() }
    func registerPusher(pushKey: String, pushGatewayURL: URL) async throws {
        if let pause = pusherPause { pusherPause = nil; await pause.wait() }
    }
    func suspendMessaging() async throws { revision += 1; suspendCount += 1; configured = false }
    func resumeMessaging() async throws { configured = true }
    func invalidateMessagingSession() async throws { revision += 1; configured = false }
    func startLiveLocationShare(durationSeconds: TimeInterval, in conversation: Conversation) async throws { }
    func updateLiveLocation(_ location: GeoPoint, in conversation: Conversation) async throws { }
    func stopLiveLocationShare(in conversation: Conversation) async throws {
        if let pause = stopPause { stopPause = nil; await pause.wait() }
    }
}

private actor ConsentRegistry: CSMMessagingDeviceRegistering {
    private var pause: ConsentPause?
    private var fails = false
    private var failsRegister = false
    private(set) var deletedIDs: [String] = []
    func pauseRegistration(_ pause: ConsentPause) { self.pause = pause }
    func setFailDelete(_ fail: Bool) { fails = fail }
    func setFailRegister(_ fail: Bool) { failsRegister = fail }
    func registerDevice(_ request: CSMMessagingDeviceRegistrationRequest, authorizationTicket: String?) async throws -> CSMMessagingDeviceRegistrationResponse {
        if let pending = pause { pause = nil; await pending.wait() }
        if failsRegister { throw CSMServiceError.unavailable("Synthetic outcome unknown") }
        var response = try await PreviewCSMMessagingDeviceClient().registerDevice(request, authorizationTicket: authorizationTicket)
        response.device.deviceId = "synthetic-own-installation"
        return response
    }
    func updatePreferences(deviceId: String, preferences: CSMNotificationPreferences, subscriptions: CSMNotificationSubscriptions) async throws -> CSMMessagingDeviceRegistrationResponse {
        try await PreviewCSMMessagingDeviceClient().updatePreferences(deviceId: deviceId, preferences: preferences, subscriptions: subscriptions)
    }
    func deleteDevice(deviceId: String) async throws {
        deletedIDs.append(deviceId)
        if fails { throw CSMServiceError.unavailable("Synthetic outage") }
    }
}

private actor ConsentCleanupStore: HostPusherCleanupStoring {
    private var records: [String: [HostPusherCleanupTarget]] = [:]
    func targets(scope: String) async throws -> [HostPusherCleanupTarget] { records[scope] ?? [] }
    func save(_ target: HostPusherCleanupTarget, scope: String) async throws {
        var owned = records[scope, default: []].filter { $0.id != target.id }
        owned.append(target); records[scope] = owned
    }
    func remove(_ target: HostPusherCleanupTarget, scope: String) async throws {
        records[scope] = records[scope, default: []].filter { $0 != target }
    }
}
private actor ConsentCleanupHTTP: HostPusherCleanupRemoving {
    private var fails = false
    private(set) var targets: [HostPusherCleanupTarget] = []
    func setFail(_ value: Bool) { fails = value }
    func remove(_ target: HostPusherCleanupTarget) async throws {
        targets.append(target)
        if fails { throw CSMServiceError.unavailable("Synthetic outage") }
    }
}
private actor ConsentHTTPTransport: MatrixHTTPTransport {
    private var status = 200
    private(set) var request: URLRequest?
    private var wrongOrigin = false
    func setStatus(_ status: Int) { self.status = status }
    func setWrongOrigin(_ value: Bool) { wrongOrigin = value }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        self.request = request
        return (Data("{}".utf8), HTTPURLResponse(url: wrongOrigin ? URL(string: "https://other.test")! : request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!)
    }
}

private actor ConsentOutbox: MessageOutboxStoring {
    private(set) var readCount = 0
    func enqueue(_ message: ChatMessage, conversation: Conversation) async throws { }
    func enqueueMatrixDraft(_ message: ChatMessage, conversation: Conversation, submission: MatrixDraftSubmission) async throws { }
    func updateMatrixSubmission(_ submission: MatrixDraftSubmission, messageId: String, conversationId: String) async throws { }
    func pendingMessages(for conversationId: String) async throws -> [ChatMessage] { readCount += 1; return [] }
    func pendingRecords(for conversationId: String) async throws -> [PendingMessageRecord] { readCount += 1; return [] }
    func pendingMessageCount() async throws -> Int { readCount += 1; return 0 }
    func recordAttempt(messageId: String, conversationId: String, error: String, retryAfter: TimeInterval) async throws { }
    func removeMessage(id: String, conversationId: String) async throws { }
    func discardPendingMessages(for conversationId: String) async throws -> Int { 0 }
    func clear() async throws { }
}
