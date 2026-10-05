import Foundation

public enum CSMVoiceCallPhase: String, Codable, Equatable, Sendable {
    case created
    case ringing
    case accepted
    case connectingMedia = "connecting_media"
    case connected
    case declined
    case missed
    case cancelled
    case failed
    case ended

    public var isTerminal: Bool {
        switch self {
        case .declined, .missed, .cancelled, .failed, .ended:
            true
        default:
            false
        }
    }
}

public enum CSMVoiceCallDirection: String, Codable, Equatable, Sendable {
    case incoming
    case outgoing
}

public enum CSMVoiceCallKind: String, Codable, Equatable, Sendable {
    case direct
}

public enum CSMVoiceCallAction: String, Codable, Equatable, Sendable {
    case accept
    case cancel
    case decline
    case end
    case heartbeat
    case mediaConnected = "media_connected"
    case mediaFailed = "media_failed"
}

public struct CSMVoiceCallPeer: Codable, Equatable, Sendable {
    public let subjectId: String
    public let displayName: String?
    public init(subjectId: String, displayName: String?) { self.subjectId = subjectId; self.displayName = displayName }
}

public struct CSMVoiceCall: Codable, Equatable, Sendable {
    public let peer: CSMVoiceCallPeer?
    /// The shared legacy title may be the callee name. Never use it as an incoming caller.
    public var presentationTitle: String {
        let expected = direction == .incoming ? initiatorSubjectId : participantSubjectIds.count == 1 ? participantSubjectIds[0] : nil
        if let peer, peer.subjectId == expected, let name = peer.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name.count <= 160, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return name }
        return direction == .incoming ? "COP kontakt" : title
    }
    public let acceptedByEndpointId: String?
    public let callId: String
    public let connectedAt: Date?
    public let createdAt: Date
    public let direction: CSMVoiceCallDirection
    public let endedAt: Date?
    public let endReason: String?
    public let expiresAt: Date
    public let initiatorSubjectId: String
    public let kind: CSMVoiceCallKind
    public let participantSubjectIds: [String]
    public let phase: CSMVoiceCallPhase
    public let revision: Int
    public let roomId: String
    public let title: String
    public let updatedAt: Date

    public init(
        acceptedByEndpointId: String? = nil,
        peer: CSMVoiceCallPeer? = nil,
        callId: String,
        connectedAt: Date?,
        createdAt: Date,
        direction: CSMVoiceCallDirection,
        endedAt: Date?,
        endReason: String?,
        expiresAt: Date,
        initiatorSubjectId: String,
        kind: CSMVoiceCallKind,
        participantSubjectIds: [String],
        phase: CSMVoiceCallPhase,
        revision: Int,
        roomId: String,
        title: String,
        updatedAt: Date
    ) {
        self.acceptedByEndpointId = acceptedByEndpointId
        self.peer = peer
        self.callId = callId
        self.connectedAt = connectedAt
        self.createdAt = createdAt
        self.direction = direction
        self.endedAt = endedAt
        self.endReason = endReason
        self.expiresAt = expiresAt
        self.initiatorSubjectId = initiatorSubjectId
        self.kind = kind
        self.participantSubjectIds = participantSubjectIds
        self.phase = phase
        self.revision = revision
        self.roomId = roomId
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct CSMVoiceCallMediaCredentials: Codable, Equatable, Sendable {
    public let e2eeKey: String
    public let expiresAt: Date
    public let serverUrl: URL
    public let token: String

    public init(e2eeKey: String, expiresAt: Date, serverUrl: URL, token: String) {
        self.e2eeKey = e2eeKey
        self.expiresAt = expiresAt
        self.serverUrl = serverUrl
        self.token = token
    }
}

public struct CSMVoiceCallSession: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let call: CSMVoiceCall
    public let media: CSMVoiceCallMediaCredentials?

    public init(
        contractVersion: String,
        call: CSMVoiceCall,
        media: CSMVoiceCallMediaCredentials?
    ) {
        self.contractVersion = contractVersion
        self.call = call
        self.media = media
    }
}

struct CSMVoiceCallListResponse: Codable, Equatable, Sendable {
    let calls: [CSMVoiceCall]
    let contractVersion: String
}

struct CSMVoiceCallStartRequest: Codable, Sendable {
    let participantSubjectIds: [String]?
    let roomId: String
    let title: String?
}

enum CSMVoiceCallEndpointIdentity {
    private static let storageKey = "csm.voice-call.endpoint-id.v1"

    static var current: String {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           !stored.isEmpty {
            return stored
        }
        let bundle = (Bundle.main.bundleIdentifier ?? "unknown")
            .replacingOccurrences(of: "[^A-Za-z0-9._:-]", with: "-", options: .regularExpression)
        let generated = "ios:\(bundle):\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: storageKey)
        return generated
    }
}

struct CSMVoiceCallActionRequest: Codable, Sendable {
    let action: CSMVoiceCallAction
    let endpointId: String?
    let expectedRevision: Int?
    let reason: String?
}

public enum CSMVoiceCallControlError: LocalizedError, Sendable {
    case authenticationRequired
    case mediaUnavailable

    public var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Přihlášení pro hovor není dostupné."
        case .mediaUnavailable:
            "Hovorový server momentálně není dostupný."
        }
    }
}
