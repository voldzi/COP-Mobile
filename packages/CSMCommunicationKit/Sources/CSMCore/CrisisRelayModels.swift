import CryptoKit
import Foundation

/// Minimal storage contracts retained by preview/test infrastructure.
///
/// The native communication target does not compile the relay runtime. These
/// protocols live with the shared wire models so lightweight in-memory stores
/// used by API previews do not pull mesh networking into COP Mobile.
protocol CrisisRelayReplayProtecting: Sendable {
    func hasSeen(envelopeId: String, subjectId: String) async throws -> Bool
    func markSeen(envelopeId: String, subjectId: String, expiresAt: Date) async throws
    func clearExpired(subjectId: String, now: Date) async throws
}

protocol CrisisRelayQueueStoring: Sendable {
    func queuedEnvelopes(subjectId: String, now: Date) async throws -> [CrisisRelayEnvelope]
    func saveQueuedEnvelopes(_ envelopes: [CrisisRelayEnvelope], subjectId: String) async throws
    func clear(subjectId: String) async throws
}

enum CrisisRelayEnvelopeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case alertAcknowledgement = "alertAck"
    case reportStub
    case safetyMessage
    case inventory

    var id: String { rawValue }
}

enum CrisisRelayAudience: String, Codable, CaseIterable, Identifiable, Sendable {
    case room
    case group
    case area
    case authority

    var id: String { rawValue }
}

enum CrisisRelayPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case routine
    case important
    case critical

    var id: String { rawValue }
}

enum CrisisRelayTrustClass: String, Codable, CaseIterable, Identifiable, Sendable {
    case authoritySigned
    case organizationSigned
    case knownContact
    case localUnverified

    var id: String { rawValue }
}

struct CrisisRelayEnvelope: Codable, Identifiable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var envelopeId: String
    var kind: CrisisRelayEnvelopeKind
    var createdAt: Date
    var expiresAt: Date
    var originDeviceId: String
    var originSubjectHint: String?
    var audience: CrisisRelayAudience
    var priority: CrisisRelayPriority
    var hopCount: Int
    var maxHops: Int
    var geoScope: String?
    var payloadCiphertext: Data
    var keyId: String
    var signature: Data

    var id: String { envelopeId }

    var isExpired: Bool {
        expiresAt <= Date()
    }

    var canForward: Bool {
        !isExpired && hopCount < maxHops
    }

    func forwarded() throws -> CrisisRelayEnvelope {
        guard canForward else {
            throw CSMServiceError.invalidState("Relay envelope cannot be forwarded.")
        }
        var copy = self
        copy.hopCount += 1
        return copy
    }

    func validationFindings(now: Date = .now) -> [String] {
        var findings: [String] = []
        if schemaVersion != Self.currentSchemaVersion {
            findings.append("unsupported_schema")
        }
        if expiresAt <= now {
            findings.append("expired")
        }
        if hopCount < 0 || maxHops < 0 || hopCount > maxHops {
            findings.append("invalid_hop_count")
        }
        if payloadCiphertext.isEmpty {
            findings.append("missing_payload_ciphertext")
        }
        if keyId.isEmpty {
            findings.append("missing_key_id")
        }
        if signature.isEmpty {
            findings.append("missing_signature")
        }
        return findings
    }

    func signingPayloadData() throws -> Data {
        try CSMJSONCoding.encoder.encode(CrisisRelayEnvelopeSigningPayload(envelope: self))
    }
}

private struct CrisisRelayEnvelopeSigningPayload: Codable, Sendable {
    var schemaVersion: Int
    var envelopeId: String
    var kind: CrisisRelayEnvelopeKind
    var createdAt: Date
    var expiresAt: Date
    var originDeviceId: String
    var originSubjectHint: String?
    var audience: CrisisRelayAudience
    var priority: CrisisRelayPriority
    var maxHops: Int
    var geoScope: String?
    var payloadCiphertext: Data
    var keyId: String

    init(envelope: CrisisRelayEnvelope) {
        schemaVersion = envelope.schemaVersion
        envelopeId = envelope.envelopeId
        kind = envelope.kind
        createdAt = envelope.createdAt
        expiresAt = envelope.expiresAt
        originDeviceId = envelope.originDeviceId
        originSubjectHint = envelope.originSubjectHint
        audience = envelope.audience
        priority = envelope.priority
        maxHops = envelope.maxHops
        geoScope = envelope.geoScope
        payloadCiphertext = envelope.payloadCiphertext
        keyId = envelope.keyId
    }
}

enum CrisisRelayEnvelopeSigner {
    static func signed(
        _ envelope: CrisisRelayEnvelope,
        keyId: String,
        privateKey: Curve25519.Signing.PrivateKey
    ) throws -> CrisisRelayEnvelope {
        var signedEnvelope = envelope
        signedEnvelope.keyId = keyId
        signedEnvelope.signature = try privateKey.signature(for: signedEnvelope.signingPayloadData())
        return signedEnvelope
    }

    static func verify(
        _ envelope: CrisisRelayEnvelope,
        publicKeyData: Data
    ) throws -> Bool {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        return publicKey.isValidSignature(envelope.signature, for: try envelope.signingPayloadData())
    }
}

struct CrisisRelayTrustedSigningKey: Codable, Equatable, Hashable, Sendable {
    var keyId: String
    var trustClass: CrisisRelayTrustClass
    var publicKeyRawRepresentation: Data
    var allowedAudiences: [CrisisRelayAudience]
    var expiresAt: Date?

    init(
        keyId: String,
        trustClass: CrisisRelayTrustClass,
        publicKeyRawRepresentation: Data,
        allowedAudiences: [CrisisRelayAudience] = CrisisRelayAudience.allCases,
        expiresAt: Date? = nil
    ) {
        self.keyId = keyId
        self.trustClass = trustClass
        self.publicKeyRawRepresentation = publicKeyRawRepresentation
        self.allowedAudiences = allowedAudiences
        self.expiresAt = expiresAt
    }

    func validationFinding(for envelope: CrisisRelayEnvelope, now: Date) -> String? {
        if expiresAt.map({ $0 <= now }) == true {
            return "expired_signing_key"
        }
        if !allowedAudiences.contains(envelope.audience) {
            return "audience_not_allowed_for_key"
        }
        return nil
    }
}

protocol CrisisRelaySignatureVerifying: Sendable {
    func verify(_ envelope: CrisisRelayEnvelope, now: Date) throws -> CrisisRelayTrustClass
}

struct LocalCrisisRelaySignatureVerifier: CrisisRelaySignatureVerifying {
    private let trustedKeysById: [String: CrisisRelayTrustedSigningKey]

    init(trustedKeys: [CrisisRelayTrustedSigningKey]) {
        trustedKeysById = Dictionary(uniqueKeysWithValues: trustedKeys.map { ($0.keyId, $0) })
    }

    func verify(_ envelope: CrisisRelayEnvelope, now: Date = .now) throws -> CrisisRelayTrustClass {
        guard let key = trustedKeysById[envelope.keyId] else {
            throw CSMServiceError.invalidState("Relay envelope signature rejected: unknown_key_id")
        }
        if let finding = key.validationFinding(for: envelope, now: now) {
            throw CSMServiceError.invalidState("Relay envelope signature rejected: \(finding)")
        }
        guard try CrisisRelayEnvelopeSigner.verify(envelope, publicKeyData: key.publicKeyRawRepresentation) else {
            throw CSMServiceError.invalidState("Relay envelope signature rejected: invalid_signature")
        }
        return key.trustClass
    }
}

enum CrisisRelayTrustedKeySetBuilder {
    static func merged(
        serverKeys: [CrisisRelayTrustedSigningKey],
        managedKeys: [CrisisRelayTrustedSigningKey],
        serverRevokedKeyIds: [String],
        managedRevokedKeyIds: [String]
    ) -> [CrisisRelayTrustedSigningKey] {
        var keysById: [String: CrisisRelayTrustedSigningKey] = [:]
        for key in serverKeys {
            keysById[key.keyId] = key
        }
        for key in managedKeys {
            keysById[key.keyId] = key
        }
        for revokedKeyId in serverRevokedKeyIds + managedRevokedKeyIds {
            keysById.removeValue(forKey: revokedKeyId)
        }
        return keysById.values.sorted { $0.keyId < $1.keyId }
    }
}

struct CrisisRelayInventoryItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    var itemId: String
    var kind: CrisisRelayEnvelopeKind
    var createdAt: Date
    var expiresAt: Date
    var priority: CrisisRelayPriority

    var id: String { itemId }
}
