import Foundation

#if os(iOS) && !canImport(MatrixRustSDK)
#error("CSM Messenger iOS requires MatrixRustSDK. Open CSMMobile.xcodeproj and do not build stale duplicate projects.")
#endif

enum ServiceFactory {
    @MainActor
    static func makeCommunicationModel(
        configuration: AppConfiguration = .fromBundle(),
        managesMessagingDeviceRegistration: Bool = true
    ) -> CommunicationModel {
        let deviceRegistration = StaticDeviceRegistrationProvider(
            value: DeviceRegistrationFactory.make(configuration: configuration)
        )

        if configuration.usePreviewServices {
            let messageOutbox = InMemoryMessageOutbox()
            let messageHistory = InMemoryMessageHistoryStore()
            let messagingBootstrapStore = InMemoryMessagingBootstrapStore()
            let messagingBoundary = PreviewCSMMessagingDeviceClient()
            return CommunicationModel(
                appConfiguration: configuration,
                api: PreviewCopAPIClient(),
                messaging: OfflineFirstMessagingClient(
                    liveClient: PreviewMessagingClient(),
                    outbox: messageOutbox,
                    history: messageHistory
                ),
                messageOutbox: messageOutbox,
                messageHistory: messageHistory,
                messagingBootstrapStore: messagingBootstrapStore,
                localAI: DeterministicLocalAIService(),
                pushNotifications: PushNotificationManager.shared,
                deviceRegistration: deviceRegistration,
                messagingDeviceRegistration: managesMessagingDeviceRegistration ? messagingBoundary : nil,
                conversationMetadata: messagingBoundary,
                authSession: PreviewAuthSession(hasExistingSession: !configuration.previewStartsSignedOut),
                securityUnlock: PreviewSecurityUnlock()
            )
        }

        let keychain = KeychainCredentialStore()
        let tokenLifecycle = OIDCTokenLifecycle(
            issuer: configuration.oidcIssuer,
            clientId: configuration.oidcClientId,
            credentialStore: keychain
        )
        let http = HTTPClient(
            baseURL: configuration.copBaseURL,
            tokenProvider: tokenLifecycle,
            requiresAuthorization: true
        )
        let messagingHTTP = HTTPClient(
            baseURL: configuration.messagingBaseURL,
            tokenProvider: tokenLifecycle,
            requiresAuthorization: true
        )
        let messagingBoundary = CSMMessagingDeviceClient(http: messagingHTTP)
        let conversationMetadata = CopConversationMetadataClient(http: http)
        let authSession = makeProductionAuthSession(
            configuration: configuration,
            keychain: keychain,
            tokenLifecycle: tokenLifecycle
        )
        let messageOutbox = EncryptedMessageOutbox(keychain: keychain)
        let messageHistory = EncryptedMessageHistoryStore(keychain: keychain)
        let messagingBootstrapStore = EncryptedMessagingBootstrapStore(keychain: keychain)
        let liveMessagingClient: any MessagingClientProtocol = {
            #if canImport(MatrixRustSDK) && !os(watchOS)
            MatrixRustE2EEMessagingClient(keychain: keychain)
            #else
            MatrixMessagingClient()
            #endif
        }()

        return CommunicationModel(
            appConfiguration: configuration,
            api: ProductionCopAPIClient(http: http),
            messaging: OfflineFirstMessagingClient(
                liveClient: liveMessagingClient,
                outbox: messageOutbox,
                history: messageHistory
            ),
            messageOutbox: messageOutbox,
            messageHistory: messageHistory,
            messagingBootstrapStore: messagingBootstrapStore,
            localAI: DeterministicLocalAIService(),
            pushNotifications: PushNotificationManager.shared,
            deviceRegistration: deviceRegistration,
            messagingDeviceRegistration: managesMessagingDeviceRegistration ? messagingBoundary : nil,
            conversationMetadata: conversationMetadata,
            authSession: authSession,
            securityUnlock: SystemSecurityUnlock()
        )
    }

    @MainActor
    private static func makeProductionAuthSession(
        configuration: AppConfiguration,
        keychain: KeychainCredentialStore,
        tokenLifecycle: OIDCTokenLifecycle
    ) -> any AuthSessionManaging {
        #if os(iOS)
        ProductionOIDCAuthSession(
            issuer: configuration.oidcIssuer,
            clientId: configuration.oidcClientId,
            redirectScheme: configuration.oidcRedirectScheme,
            scope: configuration.oidcScope,
            keychain: keychain,
            tokenLifecycle: tokenLifecycle
        )
        #else
        ProductionOIDCAuthSession()
        #endif
    }
}

actor MatrixMessagingClientPlaceholder: MessagingClientProtocol {
    private var configuredBootstrap: MessagingBootstrap?

    func configure(with bootstrap: MessagingBootstrap) async throws {
        guard bootstrap.chatAvailable, bootstrap.tokenAvailable, bootstrap.e2eeRequired else {
            throw CSMServiceError.disabled("Matrix/E2EE bootstrap is not available.")
        }
        configuredBootstrap = bootstrap
    }

    func messages(for conversation: Conversation) async throws -> [ChatMessage] {
        guard configuredBootstrap != nil else {
            throw CSMServiceError.invalidState("Matrix client is not configured.")
        }
        return []
    }

    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage {
        throw CSMServiceError.disabled("Matrix SDK adapter is required before sending plaintext messages.")
    }

    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        throw CSMServiceError.disabled("Matrix SDK adapter is required before sending structured E2EE message drafts.")
    }

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {}
}
