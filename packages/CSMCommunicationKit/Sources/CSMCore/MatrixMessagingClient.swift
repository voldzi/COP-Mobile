import Foundation
#if os(iOS)
import UIKit
#endif

protocol MatrixHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionMatrixHTTPTransport: MatrixHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

/// Live Matrix Client-Server API adapter talking directly to Synapse.
///
/// Token lifecycle: the access token comes from COP via `MessagingBootstrap`
/// (provisioned by CSM Messaging /api/v1/matrix/token). The client stores it
/// for the session duration and re-configures on bootstrap refresh.
///
/// E2EE note: this client sends and receives plaintext m.room.message events.
/// The dev server must have CSM_MESSAGING_E2EE_REQUIRED=false. Encrypted
/// rooms (Megolm) require an Olm/Megolm adapter — tracked for M2.
actor MatrixMessagingClient: MessagingClientProtocol {
    private let transport: any MatrixHTTPTransport
    private var session: MatrixSession?
    private var txnCounter: UInt64 = 0

    init(transport: any MatrixHTTPTransport = URLSessionMatrixHTTPTransport()) {
        self.transport = transport
    }

    // MARK: - MessagingClientProtocol

    func configure(with bootstrap: MessagingBootstrap) async throws {
        guard bootstrap.chatAvailable, bootstrap.tokenAvailable else {
            throw CSMServiceError.disabled("Matrix bootstrap neni dostupny.")
        }
        guard !bootstrap.e2eeRequired else {
            throw CSMServiceError.disabled("Matrix E2EE je vyzadovano; plaintext CS API adapter je z bezpecnostnich duvodu vypnuty.")
        }
        guard
            let homeserverURL = bootstrap.homeserverBaseUrl,
            let accessToken = bootstrap.accessToken,
            let userId = bootstrap.userId
        else {
            throw CSMServiceError.invalidState("Matrix bootstrap neobsahuje homeserverBaseUrl, accessToken nebo userId.")
        }
        session = MatrixSession(
            homeserverURL: homeserverURL,
            accessToken: accessToken,
            userId: userId,
            deviceId: bootstrap.deviceId ?? ""
        )
    }

    func messages(for conversation: Conversation) async throws -> [ChatMessage] {
        let session = try requireSession()
        guard let roomId = conversation.activeMatrixRoomId else {
            return []
        }
        return try await fetchRoomMessages(roomId: roomId, session: session)
    }

    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage {
        try await sendMessage(OutgoingMessageDraft(body: body), to: conversation)
    }

    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        let session = try requireSession()
        guard !draft.isEmpty else {
            throw CSMServiceError.invalidState("Zprava je prazdna.")
        }
        guard let roomId = conversation.activeMatrixRoomId else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }
        // Auto-join: accept pending invite before sending, so the user can
        // participate in rooms provisioned server-side without a separate join flow.
        try await joinRoomIfNeeded(roomId: roomId, session: session)
        return try await sendRoomMessage(draft: draft, roomId: roomId, session: session)
    }

    // MARK: - Pusher

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {
        guard let session else { return }
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/pushers/set"
        ) else { return }

        #if os(iOS)
        let deviceName = await MainActor.run { UIDevice.current.name }
        #else
        let deviceName = "CSM Messenger"
        #endif

        let pusher = MatrixPusherSetRequest(
            appId: Bundle.main.bundleIdentifier ?? "cz.zeleznalady.csm.messenger",
            appDisplayName: "CSM Messenger",
            deviceDisplayName: deviceName,
            pushkey: pushKey,
            lang: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
            kind: "http",
            data: MatrixPusherData(url: pushGatewayURL.absoluteString, format: "event_id_only")
        )

        struct PusherSetResponse: Decodable {}
        _ = try? await matrixPOST(url: url, body: pusher, session: session) as PusherSetResponse
    }

    // MARK: - Join

    /// Accepts a pending Matrix room invite (or no-ops if already joined/unknown).
    /// Called before the first send so server-provisioned rooms work without an
    /// explicit join step in the iOS UI.
    private func joinRoomIfNeeded(roomId: String, session: MatrixSession) async throws {
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/join/\(roomId.matrixEncoded)"
        ) else { throw MatrixAPIError.badURL }

        struct JoinResponse: Decodable { var room_id: String? }
        let _: JoinResponse = try await matrixPOSTEmpty(url: url, session: session)
    }

    // MARK: - Room messages

    private func fetchRoomMessages(roomId: String, session: MatrixSession) async throws -> [ChatMessage] {
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/rooms/\(roomId.matrixEncoded)/messages",
            query: "dir=b&limit=50"
        ) else { throw MatrixAPIError.badURL }

        let response: MatrixRoomMessagesResponse = try await matrixGET(url: url, session: session)
        var messagesById = Dictionary(
            uniqueKeysWithValues: response.chunk
                .filter { $0.type == "m.room.message" }
                .compactMap { chatMessage(from: $0, roomId: roomId, ownUserId: session.userId) }
                .map { ($0.id, $0) }
        )
        applyReactionEvents(response.chunk, to: &messagesById, ownUserId: session.userId)
        return messagesById.values.sorted {
            $0.sentAt == $1.sentAt ? $0.id < $1.id : $0.sentAt < $1.sentAt
        }
    }

    // MARK: - Send

    private func sendRoomMessage(
        draft: OutgoingMessageDraft,
        roomId: String,
        session: MatrixSession
    ) async throws -> ChatMessage {
        let txnId = makeTxnId(prefix: "csm")
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/rooms/\(roomId.matrixEncoded)/send/m.room.message/\(txnId)"
        ) else { throw MatrixAPIError.badURL }

        var relatesTo: MatrixSendRelatesTo?
        if let replyTo = draft.replyTo {
            relatesTo = MatrixSendRelatesTo(inReplyTo: MatrixSendInReplyTo(eventId: replyTo.messageId))
        }
        let content = MatrixSendEventRequest(msgtype: "m.text", body: draft.body, relatesTo: relatesTo)
        let response: MatrixSendEventResponse = try await matrixPUT(url: url, body: content, session: session)

        return ChatMessage(
            id: response.eventId,
            roomId: roomId,
            senderId: session.userId,
            senderDisplayName: matrixDisplayName(session.userId),
            body: draft.body,
            attachments: draft.attachments,
            replyTo: draft.replyTo,
            sentAt: .now,
            deliveryState: .sent,
            isOwnMessage: true
        )
    }

    // MARK: - Reactions

    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        let session = try requireSession()
        let key = String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        guard !key.isEmpty else { return message }
        guard message.deliveryState != .pending else {
            throw CSMServiceError.invalidState("Reakci na lokalne cekajici zpravu nelze synchronizovat s Matrix.")
        }
        guard let roomId = conversation.activeMatrixRoomId else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }

        if let reaction = message.reactions.first(where: { $0.emoji == key }), reaction.reactedByMe {
            guard let reactionEventId = reaction.ownEventId else {
                throw MatrixAPIError.missingReactionEventId(message.id)
            }
            try await redactReaction(eventId: reactionEventId, roomId: roomId, session: session)
            return message.applyingReactionToggle(key)
        }

        let reactionEventId = try await sendReaction(key, to: message.id, roomId: roomId, session: session)
        return message.applyingReactionToggle(key, ownEventId: reactionEventId)
    }

    private func sendReaction(
        _ emoji: String,
        to messageEventId: String,
        roomId: String,
        session: MatrixSession
    ) async throws -> String {
        let txnId = makeTxnId(prefix: "csm-reaction")
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/rooms/\(roomId.matrixEncoded)/send/m.reaction/\(txnId)"
        ) else { throw MatrixAPIError.badURL }

        let request = MatrixReactionEventRequest(
            relatesTo: MatrixReactionRelatesTo(eventId: messageEventId, key: emoji)
        )
        let response: MatrixSendEventResponse = try await matrixPUT(url: url, body: request, session: session)
        return response.eventId
    }

    private func redactReaction(eventId: String, roomId: String, session: MatrixSession) async throws {
        let txnId = makeTxnId(prefix: "csm-redact")
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/rooms/\(roomId.matrixEncoded)/redact/\(eventId.matrixEncoded)/\(txnId)"
        ) else { throw MatrixAPIError.badURL }

        let _: MatrixSendEventResponse = try await matrixPUT(
            url: url,
            body: MatrixRedactEventRequest(reason: "CSM reaction removed"),
            session: session
        )
    }

    func leaveConversation(_ conversation: Conversation) async throws {
        let session = try requireSession()
        guard conversation.type == .group else {
            throw CSMServiceError.invalidState("Matrix leave je dostupný jen pro skupinové konverzace.")
        }
        guard let roomId = conversation.activeMatrixRoomId else {
            throw MatrixAPIError.missingRoomBinding(conversation.conversationId)
        }
        try await leaveRoom(roomId: roomId, session: session)
    }

    // MARK: - HTTP

    private func matrixGET<T: Decodable>(url: URL, session: MatrixSession) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func matrixPUT<T: Decodable, B: Encodable>(url: URL, body: B, session: MatrixSession) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func matrixPOSTEmpty<T: Decodable>(url: URL, session: MatrixSession) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return try await perform(request)
    }

    private func matrixPOST<T: Decodable, B: Encodable>(url: URL, body: B, session: MatrixSession) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func leaveRoom(roomId: String, session: MatrixSession) async throws {
        guard let url = matrixURL(
            homeserver: session.homeserverURL,
            path: "/_matrix/client/v3/rooms/\(roomId.matrixEncoded)/leave"
        ) else { throw MatrixAPIError.badURL }

        struct LeaveResponse: Decodable {}
        let _: LeaveResponse = try await matrixPOSTEmpty(url: url, session: session)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MatrixAPIError.httpError(0, "Neocekavana odpoved serveru.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errMsg = (try? JSONDecoder().decode(MatrixErrorResponse.self, from: data))?.error
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MatrixAPIError.httpError(http.statusCode, errMsg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Mapping

    private func chatMessage(from event: MatrixRoomEvent, roomId: String, ownUserId: String) -> ChatMessage? {
        guard let body = event.content.body, !body.isEmpty else { return nil }
        let sentAt = Date(timeIntervalSince1970: Double(event.originServerTs) / 1000.0)
        let replyTo: MessageReplyReference? = event.content.relatesTo?.inReplyTo.map {
            MessageReplyReference(
                messageId: $0.eventId,
                senderDisplayName: matrixDisplayName(event.sender),
                bodyPreview: body
            )
        }
        return ChatMessage(
            id: event.eventId,
            roomId: roomId,
            senderId: event.sender,
            senderDisplayName: matrixDisplayName(event.sender),
            body: body,
            replyTo: replyTo,
            sentAt: sentAt,
            deliveryState: .read,
            isOwnMessage: event.sender == ownUserId
        )
    }

    private func applyReactionEvents(
        _ events: [MatrixRoomEvent],
        to messagesById: inout [String: ChatMessage],
        ownUserId: String
    ) {
        for event in events where event.type == "m.reaction" {
            guard
                event.content.relatesTo?.relType == "m.annotation",
                let targetEventId = event.content.relatesTo?.eventId,
                let emoji = event.content.relatesTo?.key,
                var message = messagesById[targetEventId]
            else {
                continue
            }

            if let reactionIndex = message.reactions.firstIndex(where: { $0.emoji == emoji }) {
                var reaction = message.reactions[reactionIndex]
                reaction.count += 1
                if event.sender == ownUserId {
                    reaction.reactedByMe = true
                    reaction.ownEventId = event.eventId
                }
                message.reactions[reactionIndex] = reaction
            } else {
                message.reactions.append(
                    MessageReaction(
                        emoji: emoji,
                        count: 1,
                        reactedByMe: event.sender == ownUserId,
                        ownEventId: event.sender == ownUserId ? event.eventId : nil
                    )
                )
            }

            messagesById[targetEventId] = message
        }
    }

    // MARK: - Helpers

    private func requireSession() throws -> MatrixSession {
        guard let session else { throw MatrixAPIError.missingBootstrap }
        return session
    }

    private func makeTxnId(prefix: String) -> String {
        txnCounter += 1
        return "\(prefix)-\(UInt64(Date.now.timeIntervalSince1970 * 1000))-\(txnCounter)"
    }

    /// Builds a URL from the homeserver base keeping scheme, host and port only.
    /// Avoids URLComponents.path double-encoding by constructing the string directly.
    private func matrixURL(homeserver: URL, path: String, query: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = homeserver.scheme
        components.host = homeserver.host
        components.port = homeserver.port
        components.percentEncodedPath = path
        components.percentEncodedQuery = query
        return components.url
    }

    private func matrixDisplayName(_ matrixUserId: String) -> String {
        guard matrixUserId.hasPrefix("@") else { return matrixUserId }
        let localpart = String(matrixUserId.dropFirst().split(separator: ":").first ?? Substring(matrixUserId))
        return localpart.hasPrefix("cop_") ? String(localpart.dropFirst(4)) : localpart
    }
}

// MARK: - Private helpers

private struct MatrixSession: Sendable {
    let homeserverURL: URL
    let accessToken: String
    let userId: String
    let deviceId: String
}

private extension String {
    /// Percent-encodes a Matrix room ID for use in a URL path segment.
    /// Encodes everything except alphanumerics and unreserved characters so that
    /// `!room123:server` becomes `%21room123%3Aserver`.
    var matrixEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics
            .union(.init(charactersIn: "-._~"))) ?? self
    }
}
