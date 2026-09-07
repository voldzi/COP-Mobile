import Foundation
import Observation
import SwiftUI

/// Privacy-bounded location context supplied by the embedding COP host.
///
/// The communication kit requests this value only while preparing an AI
/// question. The host remains responsible for permission UX and never has to
/// expose Core Location or bridge internals to the messaging package.
public struct CSMCommunicationLocation: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let accuracyMeters: Double?
    public let radiusKilometers: Double?
    public let label: String?

    public init(
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double? = nil,
        radiusKilometers: Double? = nil,
        label: String? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.radiusKilometers = radiusKilometers
        self.label = label
    }
}

public enum CSMCommunicationLocationShareError: LocalizedError, Sendable {
    case permissionDenied
    case permissionRestricted
    case unavailable
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Přístup k poloze je vypnutý. Povolte jej pro COP Mobile v Nastavení."
        case .permissionRestricted:
            "Poloha je na tomto telefonu omezena systémovým nastavením."
        case .unavailable:
            "Aktuální polohu se nepodařilo zjistit. Zkuste to znovu na místě s lepším signálem."
        case .timedOut:
            "Zjištění polohy trvalo příliš dlouho. Zkuste akci zopakovat."
        }
    }
}

/// Native, end-to-end encrypted CSM conversation experience for host apps.
///
/// The host intentionally exposes a single SwiftUI surface instead of Matrix
/// credentials or internal service objects. Authentication, encrypted stores,
/// timeline sync and the offline outbox remain owned by this module.
public struct CSMCommunicationHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var runtime = CSMCommunicationRuntime.shared
    private let currentLocationProvider: (@MainActor @Sendable () async -> CSMCommunicationLocation?)?
    private let locationShareProvider:
        (@MainActor @Sendable () async throws -> CSMCommunicationLocation)?
    private let voipDeviceTokenProvider: (@MainActor @Sendable () async -> String?)?
    private let expectedSubjectID: String?
    private let onClose: (() -> Void)?
    private let onOpenCOP: (() -> Void)?
    private let onStartVoiceCall: ((String, String, [String]?) -> Void)?

    public init(
        currentLocationProvider: (@MainActor @Sendable () async -> CSMCommunicationLocation?)? = nil,
        locationShareProvider:
            (@MainActor @Sendable () async throws -> CSMCommunicationLocation)? = nil,
        voipDeviceTokenProvider: (@MainActor @Sendable () async -> String?)? = nil,
        expectedSubjectID: String? = nil,
        onClose: (() -> Void)? = nil,
        onOpenCOP: (() -> Void)? = nil,
        onStartVoiceCall: ((String, String, [String]?) -> Void)? = nil
    ) {
        self.currentLocationProvider = currentLocationProvider
        self.locationShareProvider = locationShareProvider
        self.voipDeviceTokenProvider = voipDeviceTokenProvider
        self.expectedSubjectID = expectedSubjectID
        self.onClose = onClose
        self.onOpenCOP = onOpenCOP
        self.onStartVoiceCall = onStartVoiceCall
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            Group {
                switch runtime.accessState {
                case .ready:
                    ConversationWorkspace(
                        locationShareProvider: locationShareProvider,
                        onClose: onClose,
                        onOpenCOP: onOpenCOP,
                        onStartVoiceCall: onStartVoiceCall
                    )
                case .checking:
                    EmbeddedChatSessionRestoringView()
                case .deviceUnlockRequired:
                    EmbeddedChatDeviceUnlockRequiredView(
                        onClose: onClose,
                        onUnlock: {
                            Task {
                                await runtime.unlock(expectedSubjectID: expectedSubjectID)
                            }
                        }
                    )
                case .signInRequired:
                    EmbeddedChatSignInRequiredView(
                        onClose: onClose,
                        onSignIn: {
                            Task {
                                await runtime.signIn(expectedSubjectID: expectedSubjectID)
                            }
                        }
                    )
                case .accountMismatch:
                    EmbeddedChatAccountMismatchView(
                        onClose: onClose,
                        onSwitchAccount: {
                            Task {
                                await runtime.signIn(
                                    expectedSubjectID: expectedSubjectID,
                                    switchAccount: true
                                )
                            }
                        }
                    )
                case .unavailable:
                    EmbeddedChatIdentityUnavailableView(
                        onClose: onClose,
                        onRetry: {
                            Task {
                                await runtime.prepare(
                                    expectedSubjectID: expectedSubjectID,
                                    allowInteractiveSignIn: false
                                )
                            }
                        }
                    )
                }
            }
        }
        .environment(runtime.model)
        .task {
            runtime.configureCurrentLocationProvider(currentLocationProvider)
            runtime.configureVoIPDeviceTokenProvider(voipDeviceTokenProvider)
            await runtime.prepare(
                expectedSubjectID: expectedSubjectID,
                allowInteractiveSignIn: false
            )
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await runtime.prepare(
                    expectedSubjectID: expectedSubjectID,
                    allowInteractiveSignIn: false
                )
            }
        }
        .onChange(of: expectedSubjectID) { _, value in
            Task {
                await runtime.prepare(
                    expectedSubjectID: value,
                    allowInteractiveSignIn: false
                )
            }
        }
        .onChange(of: runtime.model.authState.rawValue) { _, _ in
            runtime.refreshAccessState(expectedSubjectID: expectedSubjectID)
        }
        .onChange(of: runtime.model.isLoading) { _, isLoading in
            guard !isLoading else { return }
            Task {
                await runtime.prepare(
                    expectedSubjectID: expectedSubjectID,
                    allowInteractiveSignIn: false
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .csmPushNotificationReceived)) { notification in
            guard let payload = notification.userInfo?["payload"] as? CSMRemoteNotificationPayload else {
                return
            }
            Task {
                await runtime.handlePushPayload(payload)
            }
        }
    }
}

private struct EmbeddedChatSessionRestoringView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Otevírám chat")
        }
    }
}

private struct EmbeddedChatDeviceUnlockRequiredView: View {
    var onClose: (() -> Void)?
    let onUnlock: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Odemknout chat", systemImage: "lock.shield")
        } description: {
            Text("Přihlášení zůstalo v telefonu uložené. Pro zobrazení chráněných zpráv potvrďte svou identitu.")
        } actions: {
            Button("Odemknout", action: onUnlock)
                .buttonStyle(.borderedProminent)
            if let onClose {
                Button("Zavřít", action: onClose)
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct EmbeddedChatSignInRequiredView: View {
    var onClose: (() -> Void)?
    let onSignIn: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            ContentUnavailableView {
                Label("Přihlaste se do COP Mobile", systemImage: "person.crop.circle.badge.checkmark")
            } description: {
                Text("Přihlášení otevře zabezpečenou stránku vaší organizace. Pro mapu i chat použijte stejný účet.")
            } actions: {
                Button("Přihlásit", action: onSignIn)
                    .buttonStyle(.borderedProminent)
                if let onClose {
                    Button("Zpět", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier("chat.signInRequired")
    }
}

private struct EmbeddedChatAccountMismatchView: View {
    var onClose: (() -> Void)?
    let onSwitchAccount: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            ContentUnavailableView {
                Label("Chat používá jiný účet", systemImage: "person.crop.circle.badge.exclamationmark")
            } description: {
                Text("Kvůli ochraně zpráv otevřete chat stejným účtem, který je přihlášený v COP.")
            } actions: {
                Button("Přihlásit správný účet", action: onSwitchAccount)
                    .buttonStyle(.borderedProminent)
                if let onClose {
                    Button("Zpět", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier("chat.accountMismatch")
    }
}

private struct EmbeddedChatIdentityUnavailableView: View {
    var onClose: (() -> Void)?
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            ContentUnavailableView {
                Label("Účet chatu se nepodařilo ověřit", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Zkontrolujte připojení a zkuste chat otevřít znovu.")
            } actions: {
                Button("Zkusit znovu", action: onRetry)
                    .buttonStyle(.borderedProminent)
                if let onClose {
                    Button("Zpět", action: onClose)
                        .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityIdentifier("chat.identityUnavailable")
    }
}

@MainActor
@Observable
public final class CSMCommunicationRuntime {
    public static let shared = CSMCommunicationRuntime()

    // The standalone native communication runtime owns its APNs + PushKit
    // record. Delivery must not depend on a hidden web session being mounted.
    let model = ServiceFactory.makeCommunicationModel(managesMessagingDeviceRegistration: true)
    private(set) var accessState: NativeCommunicationAccessState = .checking
    private var started = false
    private var startTask: Task<Void, Never>?
    private var preparationGeneration = 0
    private var deviceRegistrationRefreshTask: Task<Void, Never>?
    private var deviceRegistrationRefreshPending = false

    private init() {}

    func configureCurrentLocationProvider(
        _ provider: (@MainActor @Sendable () async -> CSMCommunicationLocation?)?
    ) {
        guard let provider else {
            model.setAICurrentLocationProvider(nil)
            return
        }
        model.setAICurrentLocationProvider {
            guard let location = await provider() else { return nil }
            return CopAIChatAgentLocation(
                lat: location.latitude,
                lon: location.longitude,
                radiusKm: location.radiusKilometers,
                label: location.label
            )
        }
    }

    func configureVoIPDeviceTokenProvider(
        _ provider: (@MainActor @Sendable () async -> String?)?
    ) {
        model.setVoIPDeviceTokenProvider(provider)
        // PushKit may have delivered its callback before SwiftUI mounted the
        // communication host. Configuring the provider is therefore itself a
        // registration trigger; otherwise the first callback can be lost as a
        // server-refresh signal for the lifetime of this process.
        if provider != nil {
            scheduleDeviceRegistrationRefresh()
        }
    }

    /// Coalesces APNs and PushKit token callbacks into a process-owned device
    /// refresh. Token rotation can happen before the native chat surface is
    /// mounted, so registration must never be owned by a SwiftUI `.onReceive`.
    func scheduleDeviceRegistrationRefresh() {
        if deviceRegistrationRefreshTask != nil {
            deviceRegistrationRefreshPending = true
            return
        }

        deviceRegistrationRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.deviceRegistrationRefreshPending = false
                await self.refreshDeviceRegistration()
            } while self.deviceRegistrationRefreshPending && !Task.isCancelled
            self.deviceRegistrationRefreshTask = nil
        }
    }

    func startIfNeeded() async {
        guard !started else { return }
        if let startTask {
            await startTask.value
            guard !startTask.isCancelled else { return }
            started = true
            return
        }
        let task = Task { @MainActor [model] in
            await model.start()
        }
        startTask = task
        await task.value
        startTask = nil
        guard !task.isCancelled else { return }
        started = true
    }

    func prepare(
        expectedSubjectID: String?,
        allowInteractiveSignIn: Bool
    ) async {
        // Preparing the embedded surface is intentionally non-interactive.
        // Authentication is started only by the explicit sign-in button so a
        // returning user never sees a browser flash while a stored session is
        // still being restored.
        _ = allowInteractiveSignIn
        preparationGeneration &+= 1
        let generation = preparationGeneration

        await startIfNeeded()
        guard generation == preparationGeneration else { return }
        refreshAccessState(expectedSubjectID: expectedSubjectID)

        if accessState == .unavailable,
           started,
           model.authState == .signedIn,
           !model.isLoading {
            await model.refreshSession()
            guard generation == preparationGeneration else { return }
            refreshAccessState(expectedSubjectID: expectedSubjectID)
        }

        guard started, accessState == .ready, !model.isLoading else { return }
        await model.appDidBecomeActive()
        guard generation == preparationGeneration else { return }
        await model.refreshDeviceRegistrationFromSystem()
        guard generation == preparationGeneration else { return }
        await drainPendingNotifications()
    }

    func refreshAccessState(expectedSubjectID: String?) {
        accessState = NativeCommunicationIdentityPolicy.resolve(
            authState: model.authState,
            actorSubjectID: model.actor?.subjectId,
            expectedSubjectID: expectedSubjectID,
            isLoading: model.isLoading
        )
    }

    func unlock(expectedSubjectID: String?) async {
        preparationGeneration &+= 1
        await startIfNeeded()
        guard model.authState == .locked else {
            refreshAccessState(expectedSubjectID: expectedSubjectID)
            return
        }
        accessState = .checking
        await model.unlockSession()
        refreshAccessState(expectedSubjectID: expectedSubjectID)
    }

    func signIn(
        expectedSubjectID: String?,
        switchAccount: Bool = false
    ) async {
        preparationGeneration &+= 1
        await startIfNeeded()
        if switchAccount, model.authState == .signedIn {
            await model.signOut()
        }
        guard model.authState != .signedIn else {
            refreshAccessState(expectedSubjectID: expectedSubjectID)
            return
        }
        accessState = .checking
        await model.signIn(forceAuthentication: switchAccount)
        refreshAccessState(expectedSubjectID: expectedSubjectID)
        guard accessState == .ready else { return }
        await model.appDidBecomeActive()
        await model.refreshDeviceRegistrationFromSystem()
        await drainPendingNotifications()
    }

    func processPendingNotifications() async {
        await startIfNeeded()
        guard started, model.authState == .signedIn, !model.isLoading else { return }
        await drainPendingNotifications()
    }

    private func drainPendingNotifications() async {
        let pending = PushNotificationManager.shared.takePendingRemoteNotifications()
        for payload in pending {
            await handlePushPayload(payload, alreadyClaimed: true)
        }
    }

    func refreshDeviceRegistration() async {
        await startIfNeeded()
        guard started else { return }
        await model.refreshDeviceRegistrationFromSystem()
    }

    public func startVoiceCall(
        roomID: String,
        title: String?,
        participantSubjectIDs: [String]? = nil
    ) async throws -> CSMVoiceCallSession {
        await startIfNeeded()
        return try await model.startVoiceCall(
            roomID: roomID,
            title: title,
            participantSubjectIDs: participantSubjectIDs
        )
    }

    public func voiceCall(callID: String) async throws -> CSMVoiceCallSession {
        await startIfNeeded()
        return try await model.voiceCall(callID: callID)
    }

    public func activeVoiceCalls() async throws -> [CSMVoiceCall] {
        await startIfNeeded()
        return try await model.activeVoiceCalls()
    }

    public func transitionVoiceCall(
        callID: String,
        action: CSMVoiceCallAction,
        expectedRevision: Int?,
        reason: String? = nil
    ) async throws -> CSMVoiceCallSession {
        await startIfNeeded()
        return try await model.transitionVoiceCall(
            callID: callID,
            action: action,
            expectedRevision: expectedRevision,
            reason: reason
        )
    }

    func handlePushPayload(
        _ payload: CSMRemoteNotificationPayload,
        alreadyClaimed: Bool = false
    ) async {
        guard model.authState == .signedIn, !model.isLoading else { return }
        guard alreadyClaimed || PushNotificationManager.shared.claimRemoteNotification(payload) else { return }
        if let destination = await model.handlePushPayload(payload) {
            NotificationCenter.default.post(
                name: .csmNavigationDestinationRequested,
                object: nil,
                userInfo: ["destination": destination]
            )
        }
    }
}
