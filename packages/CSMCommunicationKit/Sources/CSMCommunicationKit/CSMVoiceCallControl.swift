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

public struct CSMVoiceCall: Codable, Equatable, Sendable {
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
    public let expiresAt: Date
    public let serverUrl: URL
    public let token: String

    public init(expiresAt: Date, serverUrl: URL, token: String) {
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

struct CSMVoiceCallActionRequest: Codable, Sendable {
    let action: CSMVoiceCallAction
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
