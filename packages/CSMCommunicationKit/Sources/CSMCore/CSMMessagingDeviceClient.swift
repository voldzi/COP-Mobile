import Foundation

struct CSMMessagingDeviceClient: CSMMessagingDeviceRegistering {
    var http: HTTPClient

    func registerDevice(
        _ request: CSMMessagingDeviceRegistrationRequest,
        authorizationTicket: String?
    ) async throws -> CSMMessagingDeviceRegistrationResponse {
        try await http.post(
            "/api/v1/devices",
            body: request,
            authorizationBearerToken: authorizationTicket
        )
    }

    func updatePreferences(
        deviceId: String,
        preferences: CSMNotificationPreferences,
        subscriptions: CSMNotificationSubscriptions
    ) async throws -> CSMMessagingDeviceRegistrationResponse {
        let body = CSMMessagingDevicePreferenceUpdateRequest(
            preferences: .init(categories: preferences.categories),
            subscriptions: .init(groupIds: subscriptions.groupIds, areaIds: subscriptions.areaIds)
        )
        return try await http.put("/api/v1/devices/\(Self.pathSegment(deviceId))/preferences", body: body)
    }

    func deleteDevice(deviceId: String) async throws {
        try await http.delete("/api/v1/devices/\(Self.pathSegment(deviceId))")
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

struct PreviewCSMMessagingDeviceClient: CSMMessagingDeviceRegistering, ConversationMetadataProviding {
    func registerDevice(
        _ request: CSMMessagingDeviceRegistrationRequest,
        authorizationTicket: String?
    ) async throws -> CSMMessagingDeviceRegistrationResponse {
        CSMMessagingDeviceRegistrationResponse(
            contractVersion: "csm-messaging-provider-v1",
            providerId: "csm.messaging.preview",
            device: CSMMessagingRegisteredDevice(
                deviceId: "preview-ios-device",
                userId: "preview-subject",
                platform: request.platform,
                status: "active",
                locale: request.locale,
                timezone: request.timezone,
                preferences: CSMMessagingDevicePreferences(categories: request.preferences.categories),
                subscriptions: CSMMessagingDeviceSubscriptions(
                    groupIds: request.subscriptions.groupIds,
                    areaIds: request.subscriptions.areaIds
                )
            )
        )
    }

    func updatePreferences(
        deviceId: String,
        preferences: CSMNotificationPreferences,
        subscriptions: CSMNotificationSubscriptions
    ) async throws -> CSMMessagingDeviceRegistrationResponse {
        CSMMessagingDeviceRegistrationResponse(
            contractVersion: "csm-messaging-provider-v1",
            providerId: "csm.messaging.preview",
            device: CSMMessagingRegisteredDevice(
                deviceId: deviceId,
                userId: "preview-subject",
                platform: "ios",
                status: "active",
                locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
                timezone: TimeZone.current.identifier,
                preferences: CSMMessagingDevicePreferences(categories: preferences.categories),
                subscriptions: CSMMessagingDeviceSubscriptions(groupIds: subscriptions.groupIds, areaIds: subscriptions.areaIds)
            )
        )
    }

    func deleteDevice(deviceId: String) async throws {
    }

    func conversations() async throws -> [Conversation] {
        try await PreviewCopAPIClient().conversations()
    }

    func conversation(id: String) async throws -> Conversation {
        guard let conversation = try await conversations().first(where: { conversation in
            conversation.conversationId == id || conversation.matrix?.roomId == id
        }) else {
            throw CSMServiceError.unavailable("Conversation not found.")
        }
        return conversation
    }

    func createConversation(_ draft: ConversationDraft) async throws -> Conversation {
        guard draft.isValid else {
            throw CSMServiceError.invalidState("Konverzace nema platny nazev nebo cleny.")
        }
        return Conversation(
            conversationId: "preview-\(draft.type.rawValue)-\(UUID().uuidString)",
            conversationKind: draft.conversationKind,
            title: draft.title,
            type: draft.type,
            status: "metadata_ready",
            encrypted: true,
            e2eeRequired: true,
            matrix: MessagingMatrixRoom(state: "pending_matrix_integration", encrypted: true),
            memberCount: max(draft.members.count, draft.type == .direct ? 2 : draft.members.count + 1),
            mapLinkCount: draft.mapLinks.count,
            members: draft.members.map {
                ConversationMember(userId: $0.userId, displayName: $0.displayName, role: $0.role ?? "member")
            },
            mapLinks: draft.mapLinks,
            metadata: draft.metadata,
            updatedAt: .now
        )
    }

    func addConversationMembers(conversationId: String, members: [ConversationMemberDraft]) async throws -> Conversation {
        var conversation = try await conversation(id: conversationId)
        let existingIds = Set(conversation.members.map { $0.userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        var seen = existingIds
        let additions = members.compactMap { draft -> ConversationMember? in
            let normalizedId = draft.userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedId.isEmpty, !seen.contains(normalizedId) else { return nil }
            seen.insert(normalizedId)
            return ConversationMember(userId: draft.userId, displayName: draft.displayName, role: draft.role ?? "member")
        }

        conversation.members.append(contentsOf: additions)
        conversation.memberCount = max(conversation.memberCount, conversation.members.count)
        conversation.updatedAt = .now
        return conversation
    }

    func ensureMatrixRoom(conversationId: String) async throws -> Conversation {
        var conversation = try await conversation(id: conversationId)
        if conversation.matrix?.roomId == nil {
            conversation.matrix = MessagingMatrixRoom(
                roomId: "!preview-\(conversation.conversationId):msg.zeleznalady.cz",
                state: "room_bound",
                encrypted: true,
                e2eeAlgorithm: "m.megolm.v1.aes-sha2",
                homeserverBaseUrl: URL(string: "https://msg.zeleznalady.cz"),
                serverName: "msg.zeleznalady.cz"
            )
            conversation.status = "room_bound"
            conversation.updatedAt = .now
        }
        return conversation
    }
}

private struct CSMMessagingDevicePreferenceUpdateRequest: Encodable, Sendable {
    var preferences: CSMMessagingDeviceRegistrationRequest.Preferences
    var subscriptions: CSMMessagingDeviceRegistrationRequest.Subscriptions
}
