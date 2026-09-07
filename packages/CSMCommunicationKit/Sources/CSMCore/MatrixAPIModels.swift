import Foundation

// MARK: - Room messages

struct MatrixRoomMessagesResponse: Decodable, Sendable {
    var chunk: [MatrixRoomEvent]
    var start: String?
    var end: String?
}

struct MatrixRoomEvent: Decodable, Sendable {
    var eventId: String
    var sender: String
    var originServerTs: Int64
    var type: String
    var content: MatrixEventContent

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case sender
        case originServerTs = "origin_server_ts"
        case type
        case content
    }
}

struct MatrixEventContent: Decodable, Sendable {
    var msgtype: String?
    var body: String?
    var relatesTo: MatrixRelatesTo?

    enum CodingKeys: String, CodingKey {
        case msgtype
        case body
        case relatesTo = "m.relates_to"
    }
}

struct MatrixRelatesTo: Decodable, Sendable {
    var inReplyTo: MatrixInReplyTo?
    var relType: String?
    var eventId: String?
    var key: String?

    enum CodingKeys: String, CodingKey {
        case inReplyTo = "m.in_reply_to"
        case relType = "rel_type"
        case eventId = "event_id"
        case key
    }
}

struct MatrixInReplyTo: Decodable, Sendable {
    var eventId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
    }
}

// MARK: - Send event

struct MatrixSendEventRequest: Encodable, Sendable {
    var msgtype: String
    var body: String
    var relatesTo: MatrixSendRelatesTo?

    enum CodingKeys: String, CodingKey {
        case msgtype
        case body
        case relatesTo = "m.relates_to"
    }
}

struct MatrixSendRelatesTo: Encodable, Sendable {
    var inReplyTo: MatrixSendInReplyTo

    enum CodingKeys: String, CodingKey {
        case inReplyTo = "m.in_reply_to"
    }
}

struct MatrixSendInReplyTo: Encodable, Sendable {
    var eventId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
    }
}

struct MatrixSendEventResponse: Decodable, Sendable {
    var eventId: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
    }
}

// MARK: - Reactions

struct MatrixReactionEventRequest: Encodable, Sendable {
    var relatesTo: MatrixReactionRelatesTo

    enum CodingKeys: String, CodingKey {
        case relatesTo = "m.relates_to"
    }
}

struct MatrixReactionRelatesTo: Encodable, Sendable {
    var relType: String = "m.annotation"
    var eventId: String
    var key: String

    enum CodingKeys: String, CodingKey {
        case relType = "rel_type"
        case eventId = "event_id"
        case key
    }
}

struct MatrixRedactEventRequest: Encodable, Sendable {
    var reason: String?
}

// MARK: - Error

struct MatrixErrorResponse: Decodable, Sendable {
    var errcode: String?
    var error: String?
}

// MARK: - Pusher

struct MatrixPusherData: Encodable, Sendable {
    var url: String
    var format: String
}

struct MatrixPusherSetRequest: Encodable, Sendable {
    var appId: String
    var appDisplayName: String
    var deviceDisplayName: String
    var pushkey: String
    var lang: String
    var kind: String
    var data: MatrixPusherData

    enum CodingKeys: String, CodingKey {
        case appId = "app_id"
        case appDisplayName = "app_display_name"
        case deviceDisplayName = "device_display_name"
        case pushkey
        case lang
        case kind
        case data
    }
}

enum MatrixAPIError: LocalizedError, Sendable {
    case missingBootstrap
    case missingRoomBinding(String)
    case missingReactionEventId(String)
    case httpError(Int, String)
    case badURL

    var errorDescription: String? {
        switch self {
        case .missingBootstrap:
            return "Matrix klient neni konfigurovan. Prihlaste se znovu."
        case .missingRoomBinding(let id):
            return "Konverzace \(id) nema Matrix room binding. Obnovte konverzace."
        case .missingReactionEventId(let messageId):
            return "Reakci u zpravy \(messageId) nelze odstranit bez Matrix event id."
        case let .httpError(code, message):
            return "Matrix API chyba \(code): \(message)"
        case .badURL:
            return "Neplatna URL Matrix serveru."
        }
    }
}
