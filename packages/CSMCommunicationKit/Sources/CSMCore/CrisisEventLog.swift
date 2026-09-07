import CryptoKit
import Foundation

enum CrisisEventKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sessionBootstrapSucceeded
    case sessionBootstrapFailed
    case offlineSnapshotLoaded
    case messageSendRequested
    case messageSendConfirmed
    case messageSendFailed
    case messageReceived
    case messageQueuedOffline
    case messageOutboxSynced
    case messageOutboxSyncFailed
    case messageOutboxDiscarded
    case messageReactionUpdated
    case messageDeleted
    case messageForwarded
    case messagePinned
    case conversationCreated
    case conversationMatrixRoomBound
    case conversationMembersUpdated
    case favoriteConversationUpdated
    case reportDraftSaved
    case reportDraftPreparedFromChat
    case reportSubmitRequested
    case reportSubmitted
    case reportSubmitFailed
    case alertAcknowledgeRequested
    case alertAcknowledged
    case devicePostureEvaluated
    case deviceRegistered
    case messagingDeviceRegistered
    case messagingDeviceRegistrationFailed
    case messagingTransportQueued
    case mobilePairingClaimed
    case mobilePairingConfirmed
    case mobilePairingFailed
    case conversationMetadataFallback
    case notificationPreferencesUpdated
    case pushDeepLinkReceived
    case offlineMapPackPrepared
    case offlineMapPackLoaded
    case offlineMapPackCleared
    case relayPermissionUpdated
    case localUnlockRequired
    case localUnlockSucceeded
    case localUnlockFailed
    case pushRegistrationUpdated
    case relayEnvelopeReceived
    case relayEnvelopeForwarded
    case remoteWipeRequested
    case remoteWipeCompleted
    case watchActionReceived
    case watchQuickStatusQueued
    case watchSnapshotSynced
    case localAISuggestionCreated
    case localAISummaryCreated

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        if rawValue == "messagingMetadataFallback" {
            self = .conversationMetadataFallback
            return
        }

        guard let kind = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown crisis event kind: \(rawValue)"
            )
        }
        self = kind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CrisisEventLogEntry: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var kind: CrisisEventKind
    var subjectId: String
    var createdAt: Date
    var relatedId: String?
    var idempotencyKey: String
    var summary: String
    var connectionMode: ConnectionMode
    var relayEnvelopeId: String?
    var metadata: [String: String]

    init(
        id: String = UUID().uuidString,
        kind: CrisisEventKind,
        subjectId: String,
        createdAt: Date = .now,
        relatedId: String? = nil,
        idempotencyKey: String? = nil,
        summary: String,
        connectionMode: ConnectionMode,
        relayEnvelopeId: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.subjectId = subjectId
        self.createdAt = createdAt
        self.relatedId = relatedId
        self.idempotencyKey = idempotencyKey ?? Self.makeIdempotencyKey(kind: kind, subjectId: subjectId, relatedId: relatedId, createdAt: createdAt)
        self.summary = summary
        self.connectionMode = connectionMode
        self.relayEnvelopeId = relayEnvelopeId
        self.metadata = metadata
    }

    private static func makeIdempotencyKey(
        kind: CrisisEventKind,
        subjectId: String,
        relatedId: String?,
        createdAt: Date
    ) -> String {
        let timeBucket = Int(createdAt.timeIntervalSince1970.rounded(.down))
        return "\(subjectId):\(kind.rawValue):\(relatedId ?? "none"):\(timeBucket)"
    }
}

struct SecurityDiagnosticExportContext: Codable, Equatable, Sendable {
    var appVersion: String
    var buildNumber: String
    var buildConfiguration: String
    var connectionMode: ConnectionMode
    var messagingStatus: String
    var relayMode: String
    var localAIStatus: String
    var devicePosture: MobileDevicePosture
    var managedPolicy: MobileManagedAppPolicy
}

struct SecurityDiagnosticExport: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var generatedAt: Date
    var subjectHash: String
    var context: SecurityDiagnosticExportContext
    var eventCount: Int
    var exportedEventCount: Int
    var redaction: SecurityDiagnosticRedactionSummary
    var events: [SecurityDiagnosticEvent]
}

struct SecurityDiagnosticRedactionSummary: Codable, Equatable, Sendable {
    var policy: String
    var redactedMetadataValues: Int
    var hashedIdentifiers: Int
}

struct SecurityDiagnosticEvent: Codable, Equatable, Sendable {
    var kind: CrisisEventKind
    var createdAt: Date
    var relatedIdHash: String?
    var idempotencyKeyHash: String
    var summary: String
    var connectionMode: ConnectionMode
    var relayEnvelopeIdHash: String?
    var metadata: [String: String]
}

enum SecurityDiagnosticExporter {
    static func makeExport(
        entries: [CrisisEventLogEntry],
        subjectId: String,
        context: SecurityDiagnosticExportContext,
        generatedAt: Date = .now,
        limit: Int = 200
    ) -> SecurityDiagnosticExport {
        var redactedMetadataValues = 0
        var hashedIdentifiers = 0
        let exportedEvents = entries.suffix(max(0, limit)).map { entry in
            let metadataResult = sanitizedMetadata(entry.metadata)
            redactedMetadataValues += metadataResult.redactedValues
            hashedIdentifiers += metadataResult.hashedIdentifiers

            return SecurityDiagnosticEvent(
                kind: entry.kind,
                createdAt: entry.createdAt,
                relatedIdHash: entry.relatedId.map { hash($0) },
                idempotencyKeyHash: hash(entry.idempotencyKey),
                summary: sanitizedSummary(entry.summary),
                connectionMode: entry.connectionMode,
                relayEnvelopeIdHash: entry.relayEnvelopeId.map { hash($0) },
                metadata: metadataResult.metadata
            )
        }

        hashedIdentifiers += exportedEvents.reduce(0) { count, event in
            count + (event.relatedIdHash == nil ? 0 : 1) + (event.relayEnvelopeIdHash == nil ? 0 : 1) + 1
        } + 1

        return SecurityDiagnosticExport(
            schemaVersion: 1,
            generatedAt: generatedAt,
            subjectHash: hash(subjectId),
            context: context,
            eventCount: entries.count,
            exportedEventCount: exportedEvents.count,
            redaction: SecurityDiagnosticRedactionSummary(
                policy: "no_tokens_no_message_bodies_no_report_descriptions_no_raw_media_identifiers_hashed",
                redactedMetadataValues: redactedMetadataValues,
                hashedIdentifiers: hashedIdentifiers
            ),
            events: exportedEvents
        )
    }

    private static func sanitizedMetadata(_ metadata: [String: String]) -> (metadata: [String: String], redactedValues: Int, hashedIdentifiers: Int) {
        var sanitized: [String: String] = [:]
        var redactedValues = 0
        var hashedIdentifiers = 0

        for (key, value) in metadata {
            if shouldRedact(key: key, value: value) {
                sanitized[key] = "[redacted]"
                redactedValues += 1
            } else if shouldHashIdentifier(key: key) {
                sanitized[key] = hash(value)
                hashedIdentifiers += 1
            } else {
                sanitized[key] = boundedValue(value)
            }
        }

        return (sanitized, redactedValues, hashedIdentifiers)
    }

    private static func sanitizedSummary(_ summary: String) -> String {
        shouldRedact(key: "summary", value: summary) ? "[redacted]" : boundedValue(summary)
    }

    private static func shouldRedact(key: String, value: String) -> Bool {
        let normalizedKey = key.lowercased()
        let sensitiveKeyFragments = [
            "token",
            "authorization",
            "secret",
            "password",
            "credential",
            "payload",
            "ciphertext",
            "rawmedia",
            "mediaPayload",
            "messagebody",
            "body",
            "description",
            "reporttext",
            "note",
            "refresh"
        ].map { $0.lowercased() }

        if sensitiveKeyFragments.contains(where: { normalizedKey.contains($0) }) {
            return true
        }

        let normalizedValue = value.lowercased()
        if normalizedValue.contains("bearer ") || normalizedValue.contains("authorization:") {
            return true
        }
        if value.hasPrefix("eyJ") && value.split(separator: ".").count >= 2 {
            return true
        }
        if looksLikeLongSecret(value) {
            return true
        }
        return false
    }

    private static func shouldHashIdentifier(key: String) -> Bool {
        let normalizedKey = key.lowercased()
        if normalizedKey == "provider" || normalizedKey == "platform" || normalizedKey == "status" {
            return false
        }
        if normalizedKey.hasSuffix("count") || normalizedKey.contains("count") {
            return false
        }
        return normalizedKey.hasSuffix("id") ||
            normalizedKey.contains("userid") ||
            normalizedKey.contains("subject") ||
            normalizedKey.contains("device") ||
            normalizedKey.contains("room") ||
            normalizedKey.contains("conversation") ||
            normalizedKey.contains("message") ||
            normalizedKey.contains("alert") ||
            normalizedKey.contains("report")
    }

    private static func boundedValue(_ value: String) -> String {
        guard value.count > 160 else { return value }
        return String(value.prefix(120)) + "...[truncated]"
    }

    private static func looksLikeLongSecret(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 32 else { return false }
        let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return trimmed.unicodeScalars.allSatisfy { hexCharacters.contains($0) }
    }

    private static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
