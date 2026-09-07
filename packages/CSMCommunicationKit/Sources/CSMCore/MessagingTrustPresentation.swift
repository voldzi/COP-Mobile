import Foundation

struct MessagingTrustPresentation: Codable, Equatable, Sendable {
    var value: String
    var systemImage: String
    var isReady: Bool
    var isQueueOnly: Bool
    var blocksSending: Bool
    var allowsManualSync: Bool
    var userMessage: String?

    static func make(status: String, pendingCount: Int) -> MessagingTrustPresentation {
        if status == "e2ee_queue" {
            let pendingSuffix = pendingMessageSuffix(pendingCount)
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.preparing", fallback: "PŘÍPRAVA"),
                systemImage: "lock.trianglebadge.exclamationmark",
                isReady: false,
                isQueueOnly: false,
                blocksSending: true,
                allowsManualSync: false,
                userMessage: CSMLocalization.text(
                    "messaging.trust.preparing.message",
                    fallback: "Bezpečný chat se zatím připravuje. Aplikace neodešle nezabezpečený obsah."
                ) + pendingSuffix
            )
        }

        if pendingCount > 0 {
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.waiting", fallback: "ČEKÁ"),
                systemImage: "tray.full.fill",
                isReady: false,
                isQueueOnly: true,
                blocksSending: false,
                allowsManualSync: true,
                userMessage: CSMLocalization.text(
                    "messaging.trust.waiting.message",
                    fallback: "Zprávy jsou uložené v tomto zařízení a čekají na bezpečné spojení."
                )
            )
        }

        switch status {
        case "online", "ready":
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.ready", fallback: "PŘIPRAVENO"),
                systemImage: "lock.shield.fill",
                isReady: true,
                isQueueOnly: false,
                blocksSending: false,
                allowsManualSync: true,
                userMessage: nil
            )

        case "offline_queue":
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.offline", fallback: "OFFLINE"),
                systemImage: "tray.full.fill",
                isReady: false,
                isQueueOnly: true,
                blocksSending: false,
                allowsManualSync: true,
                userMessage: CSMLocalization.text(
                    "messaging.trust.offline.message",
                    fallback: "Zprávy jsou uložené v tomto zařízení a čekají na obnovení spojení."
                )
            )

        case "disabled", "signed_out":
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.disabled", fallback: "VYPNUTO"),
                systemImage: "lock.slash.fill",
                isReady: false,
                isQueueOnly: false,
                blocksSending: false,
                allowsManualSync: false,
                userMessage: nil
            )

        default:
            return MessagingTrustPresentation(
                value: CSMLocalization.text("messaging.trust.value.checking", fallback: "KONTROLA"),
                systemImage: "lock.trianglebadge.exclamationmark",
                isReady: false,
                isQueueOnly: false,
                blocksSending: false,
                allowsManualSync: true,
                userMessage: nil
            )
        }
    }

    private static func pendingMessageSuffix(_ count: Int) -> String {
        guard count > 0 else { return "" }
        if count == 1 {
            return CSMLocalization.text("messaging.trust.pending.one", fallback: " 1 zpráva zůstává jen v tomto zařízení.")
        }
        if count < 5 {
            return CSMLocalization.text("messaging.trust.pending.few", fallback: " %d zprávy zůstávají jen v tomto zařízení.", count)
        }
        return CSMLocalization.text("messaging.trust.pending.many", fallback: " %d zpráv zůstává jen v tomto zařízení.", count)
    }
}

struct ChatDeliveryPresentation: Codable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable {
        case waiting
        case warning
        case blocked
    }

    var isVisible: Bool
    var title: String
    var subtitle: String
    var detail: String
    var technicalDetail: String?
    var systemImage: String
    var canSync: Bool
    var pendingCount: Int
    var syncStatus: String
    var syncStatusText: String?
    var severity: Severity

    static func make(
        trust: MessagingTrustPresentation,
        pendingCount: Int,
        transportError: String?,
        syncStatus: String
    ) -> ChatDeliveryPresentation {
        let trimmedTransportError = normalizedOptional(transportError)
        let userFacingIssue = MessagingUserFacingIssue.make(errorText: trimmedTransportError)
        let pendingPreparationIssue = MessagingUserFacingIssue.isMissingRoomBinding(trimmedTransportError) ? userFacingIssue : nil
        let trimmedTrustMessage = normalizedOptional(trust.userMessage)
        let technicalDetail = joinedTechnicalDetails(trimmedTrustMessage, trimmedTransportError)
        let syncText = syncStatusText(for: syncStatus)

        if pendingCount > 0 {
            return ChatDeliveryPresentation(
                isVisible: true,
                title: pendingPreparationIssue?.title ?? (
                    pendingCount == 1
                        ? CSMLocalization.text("chat.delivery.pending.one.title", fallback: "Zpráva čeká v telefonu")
                        : CSMLocalization.text("chat.delivery.pending.many.title", fallback: "Zprávy čekají v telefonu")
                ),
                subtitle: pendingPreparationIssue?.message ?? (
                    pendingCount == 1
                        ? CSMLocalization.text(
                            "chat.delivery.pending.one.subtitle",
                            fallback: "Odešle se automaticky po obnovení bezpečného spojení."
                        )
                        : CSMLocalization.text(
                            "chat.delivery.pending.many.subtitle",
                            fallback: "Odešlou se automaticky po obnovení bezpečného spojení."
                        )
                ),
                detail: pendingPreparationIssue?.recoverySuggestion ?? (
                    pendingCount == 1
                        ? CSMLocalization.text(
                            "chat.delivery.pending.one.detail",
                            fallback: "Zpráva neopustila zařízení. Aplikace ji odešle znovu, jakmile bude dostupné bezpečné spojení."
                        )
                        : CSMLocalization.text(
                            "chat.delivery.pending.many.detail",
                            fallback: "Zprávy neopustily zařízení. Aplikace je odešle znovu, jakmile bude dostupné bezpečné spojení."
                        )
                ),
                technicalDetail: technicalDetail,
                systemImage: pendingPreparationIssue?.systemImage ?? "tray.full.fill",
                canSync: trust.allowsManualSync,
                pendingCount: pendingCount,
                syncStatus: syncStatus,
                syncStatusText: syncText,
                severity: trust.blocksSending ? .blocked : (pendingPreparationIssue == nil ? .waiting : .warning)
            )
        }

        if trust.blocksSending {
            return ChatDeliveryPresentation(
                isVisible: true,
                title: CSMLocalization.text("chat.delivery.blocked.title", fallback: "Bezpečný chat se připravuje"),
                subtitle: CSMLocalization.text(
                    "chat.delivery.blocked.subtitle",
                    fallback: "Obsah zůstává chráněný a aplikace nepošle zprávu nezabezpečeně."
                ),
                detail: CSMLocalization.text(
                    "chat.delivery.blocked.detail",
                    fallback: "Aplikace čeká na ověřené šifrované spojení. Zprávy zůstanou v telefonu, dokud nebude bezpečný kanál připravený."
                ),
                technicalDetail: technicalDetail,
                systemImage: trust.systemImage,
                canSync: false,
                pendingCount: 0,
                syncStatus: syncStatus,
                syncStatusText: syncText,
                severity: .blocked
            )
        }

        if trust.isQueueOnly {
            return ChatDeliveryPresentation(
                isVisible: true,
                title: CSMLocalization.text("chat.delivery.queue.title", fallback: "Chat čeká na spojení"),
                subtitle: CSMLocalization.text(
                    "chat.delivery.queue.subtitle",
                    fallback: "Nové zprávy zůstanou v telefonu a odešlou se po návratu spojení."
                ),
                detail: CSMLocalization.text(
                    "chat.delivery.queue.detail",
                    fallback: "Aplikace pracuje offline-first. Jakmile bude dostupné bezpečné spojení, čekající zprávy se odešlou automaticky."
                ),
                technicalDetail: technicalDetail,
                systemImage: trust.systemImage,
                canSync: false,
                pendingCount: 0,
                syncStatus: syncStatus,
                syncStatusText: syncText,
                severity: .waiting
            )
        }

        if let trimmedTransportError {
            return ChatDeliveryPresentation(
                isVisible: true,
                title: userFacingIssue?.title ?? CSMLocalization.text(
                    "chat.delivery.transport.title",
                    fallback: "Spojení s chatem se obnovuje"
                ),
                subtitle: userFacingIssue?.message ?? CSMLocalization.text(
                    "chat.delivery.transport.subtitle",
                    fallback: "Zprávy zůstanou chráněné a aplikace zkusí místnost znovu načíst."
                ),
                detail: userFacingIssue?.recoverySuggestion ?? CSMLocalization.text(
                    "chat.delivery.transport.detail",
                    fallback: "Chat se pokouší obnovit zabezpečené spojení. Obsah zpráv se nenačítá přes push ani nezabezpečenou zálohu."
                ),
                technicalDetail: trimmedTransportError,
                systemImage: userFacingIssue?.systemImage ?? "arrow.triangle.2.circlepath",
                canSync: false,
                pendingCount: 0,
                syncStatus: syncStatus,
                syncStatusText: syncText,
                severity: .warning
            )
        }

        return ChatDeliveryPresentation(
            isVisible: false,
            title: "",
            subtitle: "",
            detail: "",
            technicalDetail: nil,
            systemImage: "lock.shield.fill",
            canSync: false,
            pendingCount: 0,
            syncStatus: syncStatus,
            syncStatusText: syncText,
            severity: .waiting
        )
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func joinedTechnicalDetails(_ values: String?...) -> String? {
        let uniqueValues = values
            .compactMap { $0 }
            .reduce(into: [String]()) { result, value in
                guard !result.contains(value) else { return }
                result.append(value)
            }
        guard !uniqueValues.isEmpty else { return nil }
        return uniqueValues.joined(separator: "\n")
    }

    private static func syncStatusText(for syncStatus: String) -> String? {
        switch syncStatus {
        case "syncing":
            return CSMLocalization.text("chat.sync.syncing", fallback: "Zkouším odeslat")
        case "synced":
            return CSMLocalization.text("chat.sync.synced", fallback: "Odesláno")
        case "partial":
            return CSMLocalization.text("chat.sync.partial", fallback: "Část zpráv ještě čeká")
        case "failed":
            return CSMLocalization.text("chat.sync.failed", fallback: "Odeslání se nepodařilo")
        case "discarded":
            return CSMLocalization.text("chat.sync.discarded", fallback: "Čekající zprávy odstraněny")
        case "blocked_e2ee":
            return CSMLocalization.text("chat.sync.blocked_e2ee", fallback: "Bezpečný chat není připravený")
        default:
            return nil
        }
    }
}

struct MessagingUserFacingIssue: Codable, Equatable, Sendable {
    var title: String
    var message: String
    var recoverySuggestion: String
    var technicalDetail: String
    var systemImage: String

    static func make(errorText: String?) -> MessagingUserFacingIssue? {
        guard let raw = normalized(errorText) else { return nil }
        let normalizedRaw = raw.lowercased()

        if normalizedRaw.containsAny(of: homeserverReachabilityMarkers) {
            return MessagingUserFacingIssue(
                title: CSMLocalization.text(
                    "messaging.issue.homeserver.title",
                    fallback: "Skupinu teď nejde bezpečně připravit"
                ),
                message: CSMLocalization.text(
                    "messaging.issue.homeserver.message",
                    fallback: "Server chatu není z COP dostupný, proto se skupina ještě nevytvořila."
                ),
                recoverySuggestion: CSMLocalization.text(
                    "messaging.issue.homeserver.recovery",
                    fallback: "Zkuste akci zopakovat. Pokud se hláška vrací, správce musí ověřit dostupnost CSM Messaging/Matrix ze serveru COP."
                ),
                technicalDetail: raw,
                systemImage: "exclamationmark.triangle.fill"
            )
        }

        if normalizedRaw.containsAny(of: missingRoomMarkers) {
            return MessagingUserFacingIssue(
                title: CSMLocalization.text("messaging.issue.missing_room.title", fallback: "Chat se ještě připravuje"),
                message: CSMLocalization.text(
                    "messaging.issue.missing_room.message",
                    fallback: "Konverzace zatím nemá hotový bezpečný kanál. Zprávy zůstanou v telefonu a odešlou se po dokončení přípravy."
                ),
                recoverySuggestion: CSMLocalization.text(
                    "messaging.issue.missing_room.recovery",
                    fallback: "Obnovte konverzace nebo zkuste odeslání znovu. Pokud se stav nemění, správce musí zkontrolovat navázání skupiny na Matrix místnost."
                ),
                technicalDetail: raw,
                systemImage: "lock.trianglebadge.exclamationmark"
            )
        }

        if normalizedRaw.containsAny(of: authenticationMarkers) {
            return MessagingUserFacingIssue(
                title: CSMLocalization.text("messaging.issue.auth.title", fallback: "Přihlášení k chatu vypršelo"),
                message: CSMLocalization.text(
                    "messaging.issue.auth.message",
                    fallback: "Aplikace nemůže bezpečně načíst chat, dokud se znovu neověří účet."
                ),
                recoverySuggestion: CSMLocalization.text(
                    "messaging.issue.auth.recovery",
                    fallback: "Odhlaste se a znovu přihlaste. Zprávy uložené v telefonu zůstanou chráněné."
                ),
                technicalDetail: raw,
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
        }

        if normalizedRaw.containsAny(of: connectivityMarkers) {
            return MessagingUserFacingIssue(
                title: CSMLocalization.text("messaging.issue.connectivity.title", fallback: "Spojení s chatem se obnovuje"),
                message: CSMLocalization.text(
                    "messaging.issue.connectivity.message",
                    fallback: "Zprávy zůstanou v telefonu a aplikace to zkusí znovu po návratu spojení."
                ),
                recoverySuggestion: CSMLocalization.text(
                    "messaging.issue.connectivity.recovery",
                    fallback: "Není potřeba posílat stejnou zprávu znovu. Nechte aplikaci otevřenou nebo použijte tlačítko znovu odeslat."
                ),
                technicalDetail: raw,
                systemImage: "arrow.triangle.2.circlepath"
            )
        }

        return MessagingUserFacingIssue(
            title: CSMLocalization.text("messaging.issue.generic.title", fallback: "Akci se nepodařilo dokončit"),
            message: CSMLocalization.text(
                "messaging.issue.generic.message",
                fallback: "Aplikace zachová chráněná data v zařízení a dovolí pokus zopakovat."
            ),
            recoverySuggestion: CSMLocalization.text(
                "messaging.issue.generic.recovery",
                fallback: "Zkuste akci znovu. Pokud chyba trvá, předejte detail správci."
            ),
            technicalDetail: raw,
            systemImage: "exclamationmark.triangle.fill"
        )
    }

    static func isMissingRoomBinding(_ errorText: String?) -> Bool {
        guard let raw = normalized(errorText)?.lowercased() else { return false }
        return raw.containsAny(of: missingRoomMarkers)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static let homeserverReachabilityMarkers = [
        "matrix public homeserver",
        "homeserver is not reachable",
        "not reachable from cop server",
        "this operation was aborted",
        "operation was aborted"
    ]

    private static let missingRoomMarkers = [
        "missingroombinding",
        "missing room binding",
        "room binding",
        "matrix room binding",
        "matrix room",
        "nema matrix room"
    ]

    private static let authenticationMarkers = [
        "m_unknown_token",
        "unknown token",
        "access token expired",
        "unauthorized",
        "401",
        "invalid token"
    ]

    private static let connectivityMarkers = [
        "timed out",
        "timeout",
        "network",
        "internet",
        "connection",
        "connect",
        "offline",
        "dns",
        "temporarily",
        "too many requests",
        "429",
        "502",
        "503",
        "504",
        "live unavailable"
    ]
}

enum MessagingRuntimeStatusResolver {
    static func configuredStatus(bootstrap: MessagingBootstrap, serverStatus: String) -> String {
        let normalizedServerStatus = normalized(serverStatus)
        let normalizedBootstrapStatus = normalized(bootstrap.status)

        guard bootstrap.enabled, bootstrap.chatAvailable, bootstrap.tokenAvailable else {
            return normalizedServerStatus.isEmpty ? "disabled" : normalizedServerStatus
        }

        if normalizedServerStatus.isEmpty {
            return normalizedBootstrapStatus.isEmpty ? "online" : normalizedBootstrapStatus
        }

        // The server-level status can still report the old E2EE queue state while
        // the native Matrix Rust adapter has already configured successfully on
        // this device. Once the encrypted client is ready, the runtime state must
        // be driven by the local adapter, not by a stale product-level warning.
        if normalizedServerStatus == "e2ee_queue", bootstrap.e2eeRequired {
            return readyBootstrapStatus(normalizedBootstrapStatus)
        }

        return normalizedServerStatus
    }

    private static func readyBootstrapStatus(_ value: String) -> String {
        switch value {
        case "", "e2ee_queue", "degraded", "disabled", "signed_out":
            return "online"
        default:
            return value
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    func containsAny(of markers: [String]) -> Bool {
        markers.contains { contains($0) }
    }
}
