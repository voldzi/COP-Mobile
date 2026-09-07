import CryptoKit
import Foundation

struct ProductionCopAPIClient: CopAPIClientProtocol {
    var http: HTTPClient

    func bootstrap(seconds: Int) async throws -> MobileBootstrap {
        try await http.get(
            "/api/v1/mobile/bootstrap",
            queryItems: [URLQueryItem(name: "seconds", value: "\(seconds)")]
        )
    }

    func offlineSnapshot(seconds: Int) async throws -> MobileOfflineSnapshot {
        try await http.get(
            "/api/v1/mobile/offline-snapshot",
            queryItems: [URLQueryItem(name: "seconds", value: "\(seconds)")]
        )
    }

    func mapCatalog(locale: String, includeDiagnostics: Bool, includePartner: Bool) async throws -> MapLayerCatalog {
        try await http.get(
            "/api/v1/map/catalog",
            queryItems: [
                URLQueryItem(name: "locale", value: locale),
                URLQueryItem(name: "includeDiagnostics", value: includeDiagnostics ? "true" : "false"),
                URLQueryItem(name: "includePartner", value: includePartner ? "true" : "false")
            ]
        )
    }

    func mapFeatures(_ request: MapFeatureQueryRequest) async throws -> MapFeatureQueryResponse {
        try await http.post("/api/v1/map/query", body: request)
    }

    func transitVehicleDetail(featureId: String, sourceId: String?) async throws -> TransitVehicleDetail {
        let normalizedFeatureId = featureId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFeatureId.isEmpty else {
            throw CSMServiceError.invalidState("Transit vehicle feature id is empty.")
        }

        var queryItems: [URLQueryItem] = []
        if let sourceId = sourceId?.trimmingCharacters(in: .whitespacesAndNewlines), !sourceId.isEmpty {
            queryItems.append(URLQueryItem(name: "source", value: sourceId))
        }

        return try await http.get(
            "/api/v1/transit/vehicles/\(Self.pathSegment(normalizedFeatureId))/detail",
            queryItems: queryItems
        )
    }

    func mapRasterOverlayImage(url: String) async throws -> Data {
        try await http.getData(
            "/api/v1/map/raster-overlay",
            queryItems: [URLQueryItem(name: "url", value: Self.normalizedRasterOverlayURL(url))],
            accept: "image/*"
        )
    }

    func weatherWebcamResource(url: String) async throws -> Data {
        try await http.getData(
            "/api/v1/weather/webcam-proxy",
            queryItems: [URLQueryItem(name: "url", value: url)],
            accept: "image/*, application/json"
        )
    }

    func weatherRadarFrames(product: String, hours: Int, limit: Int) async throws -> WeatherRadarFrameCatalog {
        try await http.get(
            "/api/v1/weather-radar/frames",
            queryItems: [
                URLQueryItem(name: "product", value: product),
                URLQueryItem(name: "hours", value: "\(max(1, min(24, hours)))"),
                URLQueryItem(name: "limit", value: "\(max(1, min(48, limit)))")
            ]
        )
    }

    func sketchPalettes() async throws -> SketchPaletteCatalog {
        try await http.get("/api/v1/sketch/palettes")
    }

    func sketchDrawings(bbox: MapFeatureBoundingBox?, limit: Int) async throws -> SketchDrawingCollection {
        var queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(1_000, limit)))")
        ]
        if let bbox {
            queryItems.append(URLQueryItem(
                name: "bbox",
                value: bbox.asArray
                    .map { String(format: "%.6f", $0) }
                    .joined(separator: ",")
            ))
        }
        return try await http.get("/api/v1/sketch/drawings", queryItems: queryItems)
    }

    func sketchDrawing(drawingId: String) async throws -> SketchDrawing {
        try await http.get("/api/v1/sketch/drawings/\(Self.pathSegment(drawingId))")
    }

    func createSketchDrawing(_ request: SketchDrawingCreateRequest) async throws -> SketchDrawing {
        try await http.post("/api/v1/sketch/drawings", body: request)
    }

    func updateSketchDrawing(drawingId: String, request: SketchDrawingUpdateRequest) async throws -> SketchDrawing {
        try await http.patch("/api/v1/sketch/drawings/\(Self.pathSegment(drawingId))", body: request)
    }

    func deleteSketchDrawing(drawingId: String) async throws {
        try await http.delete("/api/v1/sketch/drawings/\(Self.pathSegment(drawingId))")
    }

    func userPreferenceProfile() async throws -> UserPreferenceProfile {
        try await http.get("/api/v1/me/preferences")
    }

    func updateUserPreferences(_ update: UserPreferenceUpdate) async throws -> UserPreferenceProfile {
        try await http.put("/api/v1/me/preferences", body: update)
    }

    func alerts(includeAcknowledged: Bool) async throws -> [CopAlert] {
        let response: CopAlertListResponse = try await http.get(
            "/api/v1/cop/alerts",
            queryItems: [URLQueryItem(name: "includeAcknowledged", value: includeAcknowledged ? "true" : "false")]
        )
        return response.items
    }

    func acknowledgeAlert(alertId: String, note: String?) async throws -> CopAlert {
        let body = AlertAcknowledgementRequest(note: note)
        return try await http.post("/api/v1/cop/alerts/\(Self.pathSegment(alertId))/acknowledge", body: body)
    }

    func messagingStatus() async throws -> MessagingStatus {
        try await http.get("/api/v1/messaging/status")
    }

    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap {
        try await http.post("/api/v1/messaging/bootstrap", body: MessagingBootstrapRequest(deviceId: deviceId))
    }

    func startVoiceCall(_ request: CSMVoiceCallStartRequest) async throws -> CSMVoiceCallSession {
        try await http.post("/api/v1/messaging/calls", body: request, transientRetryCount: 3)
    }

    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int) async throws -> [CSMVoiceCall] {
        var queryItems = [
            URLQueryItem(name: "activeOnly", value: activeOnly ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(max(1, min(limit, 200))))
        ]
        if let roomId, !roomId.isEmpty {
            queryItems.append(URLQueryItem(name: "roomId", value: roomId))
        }
        let response: CSMVoiceCallListResponse = try await http.get(
            "/api/v1/messaging/calls",
            queryItems: queryItems,
            transientRetryCount: 3
        )
        return response.calls
    }

    func voiceCall(callId: String) async throws -> CSMVoiceCallSession {
        try await http.get(
            "/api/v1/messaging/calls/\(Self.pathSegment(callId))",
            transientRetryCount: 3
        )
    }

    func transitionVoiceCall(
        callId: String,
        request: CSMVoiceCallActionRequest
    ) async throws -> CSMVoiceCallSession {
        try await http.post(
            "/api/v1/messaging/calls/\(Self.pathSegment(callId))/actions",
            body: request,
            transientRetryCount: 3
        )
    }

    func mobilePairingSession(code: String) async throws -> MobilePairingSessionResponse {
        try await http.get("/api/v1/mobile/pairing/sessions/\(Self.pathSegment(code))")
    }

    func claimMobilePairingSession(
        code: String,
        request: MobilePairingClaimRequest
    ) async throws -> MobilePairingSessionResponse {
        try await http.post("/api/v1/mobile/pairing/sessions/\(Self.pathSegment(code))/claim", body: request)
    }

    func conversations() async throws -> [Conversation] {
        let response: MessagingConversationListResponse = try await http.get("/api/v1/messaging/conversations")
        return response.conversations
    }

    func queryAIChatAgent(_ request: CopAIChatAgentRequest) async throws -> CopAIChatAgentResponse {
        let started: CopAIChatAgentJobResponse = try await http.post(
            "/api/v1/ai/chat-agent/jobs",
            body: request
        )
        if let response = try Self.completedAIResponse(from: started) {
            return response
        }

        for attempt in 0..<90 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
            let job: CopAIChatAgentJobResponse = try await http.get(
                "/api/v1/ai/chat-agent/jobs/\(Self.pathSegment(started.jobId))"
            )
            if let response = try Self.completedAIResponse(from: job) {
                return response
            }
        }
        throw CSMServiceError.unavailable(
            "AI agent stále zpracovává dotaz. Zkuste výsledek znovu za chvíli nebo dotaz zkraťte."
        )
    }

    private static func completedAIResponse(
        from job: CopAIChatAgentJobResponse
    ) throws -> CopAIChatAgentResponse? {
        switch job.status {
        case "completed":
            guard let response = job.response else {
                throw CSMServiceError.unavailable("Dokončená AI úloha neobsahuje odpověď.")
            }
            return response
        case "failed":
            throw CSMServiceError.unavailable(job.error?.message ?? "AI agent dotaz selhal.")
        default:
            return nil
        }
    }

    func registerDevice(_ registration: MobileDeviceRegistration) async throws -> MobileDeviceRegistrationResponse {
        let response: MobileDeviceRegistrationAPIResponse = try await http.post("/api/v1/mobile/devices", body: registration)
        return MobileDeviceRegistrationResponse(
            deviceSessionId: response.device.deviceSessionId,
            pushTokenRegistered: response.device.pushTokenRegistered,
            policy: response.policy,
            serverTimestamp: response.serverTimestamp
        )
    }

    func deviceRegistrationTicket(
        appInstanceId: String,
        bundleId: String
    ) async throws -> MobileDeviceRegistrationTicketResponse {
        try await http.post(
            "/api/v1/mobile/device-registration-tickets",
            body: MobileDeviceRegistrationTicketRequest(
                appInstanceId: appInstanceId,
                bundleId: bundleId
            )
        )
    }

    func communityReports() async throws -> [CommunityReport] {
        let response: CommunityReportListResponse = try await http.get("/api/v1/community/reports")
        return response.items
    }

    func submitCommunityReport(_ draft: CommunityReportDraft) async throws -> CommunityReportSubmission {
        let createRequest = CommunityReportCreateRequest(draft: draft)
        let created: CommunityReportAPIResponse = try await http.post("/api/v1/community/reports", body: createRequest)
        let uploadedAttachmentCount = try await uploadAttachments(draft.attachments, reportId: created.reportId)
        try await http.post("/api/v1/community/reports/\(Self.pathSegment(created.reportId))/submit")
        return CommunityReportSubmission(
            reportId: created.reportId,
            status: "submitted",
            submittedAt: .now,
            uploadedAttachmentCount: uploadedAttachmentCount
        )
    }

    private func uploadAttachments(
        _ attachments: [CommunityReportAttachmentDraft],
        reportId: String
    ) async throws -> Int {
        let reportPath = "/api/v1/community/reports/\(Self.pathSegment(reportId))"
        var uploadedCount = 0

        for attachment in attachments {
            let slotRequest = CommunityReportAttachmentCreateRequest(attachment: attachment)
            let slot: CommunityReportAttachmentSlotResponse = try await http.post(
                "\(reportPath)/attachments",
                body: slotRequest
            )
            let attachmentId = slot.attachment.attachmentId
            let uploadPath = "\(reportPath)/attachments/\(Self.pathSegment(attachmentId))"

            if let uploadURL = slot.upload.uploadUrl, uploadURL.scheme?.lowercased() == "https" {
                do {
                    try await http.putData(
                        to: uploadURL,
                        data: attachment.payload,
                        contentType: attachment.contentType,
                        headers: slot.upload.headers
                    )
                    let body = CommunityReportAttachmentCompleteRequest(
                        byteSize: attachment.byteSize,
                        checksumSha256: Self.sha256Hex(attachment.payload)
                    )
                    let _: CommunityReportAttachmentAPIItem = try await http.post("\(uploadPath)/complete", body: body)
                    uploadedCount += 1
                    continue
                } catch {
                    // Fall through to the COP binary proxy. The proxy keeps uploads working
                    // when a presigned media endpoint is internal-only or temporarily blocked.
                }
            }

            try await http.postData(
                "\(uploadPath)/upload",
                data: attachment.payload,
                contentType: attachment.contentType,
                headers: ["X-COP-Upload-Mode": "binary"]
            )
            uploadedCount += 1
        }

        return uploadedCount
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func normalizedRasterOverlayURL(_ value: String) -> String {
        guard let components = URLComponents(string: value),
              components.path == "/api/v1/map/raster-overlay",
              let proxiedURL = components.queryItems?.first(where: { $0.name == "url" })?.value,
              !proxiedURL.isEmpty
        else {
            return value
        }
        return proxiedURL
    }
}

/// COP-owned conversation metadata boundary.
///
/// CSM Messenger keeps CSM Messaging as the device/APNs registry only. Group,
/// direct-conversation and Matrix-room metadata stays behind COP, which is the
/// map and decision authority for the wider COP/CSM system.
struct CopConversationMetadataClient: ConversationMetadataProviding {
    var http: HTTPClient

    func conversations() async throws -> [Conversation] {
        let response: MessagingConversationListResponse = try await http.get("/api/v1/messaging/conversations")
        return response.conversations
    }

    func conversation(id: String) async throws -> Conversation {
        let normalizedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedId.isEmpty else {
            throw CSMServiceError.invalidState("Identifikator konverzace neni platny.")
        }

        if Self.looksLikeMatrixRoomId(normalizedId) {
            return try await resolveConversation(roomId: normalizedId)
        }

        let response: MessagingConversationResponse = try await http.get(
            "/api/v1/messaging/conversations/\(Self.pathSegment(normalizedId))"
        )
        return response.conversation
    }

    func createConversation(_ draft: ConversationDraft) async throws -> Conversation {
        guard draft.isValid else {
            throw CSMServiceError.invalidState("Konverzace nema platny nazev nebo cleny.")
        }
        let response: MessagingConversationResponse = try await http.post(
            "/api/v1/messaging/conversations",
            body: MessagingConversationCreateRequest(draft: draft)
        )
        return response.conversation
    }

    func searchUserDirectory(query: String, limit: Int) async throws -> [ConversationRecipient] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedQuery.count >= 2 else { return [] }

        let response: UserDirectorySearchResponse = try await http.get(
            "/api/v1/users/search",
            queryItems: [
                URLQueryItem(name: "q", value: normalizedQuery),
                URLQueryItem(name: "limit", value: "\(max(1, min(25, limit)))")
            ]
        )
        guard response.contractVersion == "cop-user-directory-v1" else {
            throw CSMServiceError.invalidState("COP user directory contract is not supported.")
        }
        return response.items.compactMap(\.recipient)
    }

    func addConversationMembers(conversationId: String, members: [ConversationMemberDraft]) async throws -> Conversation {
        let uniqueMembers = Self.uniqueMembers(members)
        guard !conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !uniqueMembers.isEmpty else {
            throw CSMServiceError.invalidState("Konverzace nebo seznam clenu neni platny.")
        }

        let response: MessagingConversationResponse = try await http.post(
            "/api/v1/messaging/conversations/\(Self.pathSegment(conversationId))/members",
            body: MessagingConversationMembersRequest(members: uniqueMembers)
        )
        return response.conversation
    }

    func ensureMatrixRoom(conversationId: String) async throws -> Conversation {
        guard !conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CSMServiceError.invalidState("Identifikator konverzace neni platny.")
        }
        let response: MessagingConversationResponse = try await http.post(
            "/api/v1/messaging/conversations/\(Self.pathSegment(conversationId))/matrix-room"
        )
        return response.conversation
    }

    private func resolveConversation(roomId: String) async throws -> Conversation {
        let response: MessagingConversationResponse = try await http.get(
            "/api/v1/messaging/conversations/resolve",
            queryItems: [URLQueryItem(name: "roomId", value: roomId)]
        )
        return response.conversation
    }

    private static func looksLikeMatrixRoomId(_ value: String) -> Bool {
        value.hasPrefix("!") && value.contains(":")
    }

    private static func pathSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func uniqueMembers(_ members: [ConversationMemberDraft]) -> [ConversationMemberDraft] {
        var seen = Set<String>()
        return members.filter { member in
            let normalizedId = member.userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedId.isEmpty, !seen.contains(normalizedId) else { return false }
            seen.insert(normalizedId)
            return true
        }
    }
}

private struct AlertAcknowledgementRequest: Encodable, Sendable {
    var note: String?
}

private struct MessagingBootstrapRequest: Encodable, Sendable {
    var deviceId: String
}

private struct CopAlertListResponse: Decodable, Sendable {
    var items: [CopAlert]
    var serverTimestamp: Date
}

private struct MessagingConversationListResponse: Decodable, Sendable {
    var conversations: [Conversation]
}

private struct MessagingConversationResponse: Decodable, Sendable {
    var conversation: Conversation
}

private struct MessagingConversationCreateRequest: Encodable, Sendable {
    var type: ConversationType
    var conversationKind: ConversationKind
    var title: String
    var members: [ConversationMemberDraft]
    var mapLinks: [MessagingMapLink]
    var metadata: [String: String]

    init(draft: ConversationDraft) {
        type = draft.type
        conversationKind = draft.conversationKind
        title = draft.title
        members = draft.members
        mapLinks = draft.mapLinks
        metadata = draft.metadata
    }
}

private struct MessagingConversationMembersRequest: Encodable, Sendable {
    var members: [ConversationMemberDraft]
}

private struct UserDirectorySearchResponse: Decodable, Sendable {
    var contractVersion: String
    var items: [UserDirectoryEntry]
    var serverTimestamp: Date?
}

private struct UserDirectoryEntry: Decodable, Sendable {
    var subjectId: String
    var username: String
    var displayName: String?
    var email: String?
    var avatarDataUrl: String?
    var avatarUrl: String?

    var recipient: ConversationRecipient? {
        let userId = subjectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userId.isEmpty else { return nil }
        let display = Self.firstNonEmpty(displayName, username, email)
        let handle = Self.firstNonEmpty(username, email)
        return ConversationRecipient(
            userId: userId,
            displayName: display,
            role: nil,
            handle: handle,
            avatarDataUrl: Self.nonEmpty(avatarDataUrl),
            avatarUrl: Self.nonEmpty(avatarUrl),
            sourceConversationTitle: "COP"
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap(nonEmpty).first
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct MobileDeviceRegistrationAPIResponse: Decodable, Sendable {
    var device: Device
    var policy: MobileNativePolicy
    var serverTimestamp: Date

    struct Device: Decodable, Sendable {
        var deviceSessionId: String
        var pushTokenRegistered: Bool
    }
}

private struct CommunityReportCreateRequest: Encodable, Sendable {
    var category: ReportCategory
    var title: String
    var description: String
    var location: GeoPoint
    var observedAt: Date
    var hazardSeverity: String
    var visibility: String
    var groupId: String?
    var groupName: String

    init(draft: CommunityReportDraft) {
        category = draft.category
        title = draft.title
        description = draft.description
        location = draft.location
        observedAt = draft.createdAt
        hazardSeverity = draft.severity.communityReportHazardSeverity
        visibility = "community"
        groupId = draft.groupId
        groupName = draft.groupName
    }
}

private struct CommunityReportAPIResponse: Decodable, Sendable {
    var reportId: String
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportId
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let reportId = try container.decodeIfPresent(String.self, forKey: .reportId) {
            self.reportId = reportId
        } else if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            reportId = id
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.reportId,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing report id.")
            )
        }
        status = try container.decodeIfPresent(String.self, forKey: .status)
    }
}

private struct CommunityReportListResponse: Decodable, Sendable {
    var items: [CommunityReport]
}

private struct CommunityReportAttachmentCreateRequest: Encodable, Sendable {
    var byteSize: Int
    var captureLocation: GeoPoint?
    var contentType: String
    var fileName: String
    var kind: CommunityAttachmentKind
    var metadata: CommunityReportAttachmentMetadata

    init(attachment: CommunityReportAttachmentDraft) {
        byteSize = attachment.byteSize
        captureLocation = attachment.captureLocation
        contentType = attachment.contentType
        fileName = attachment.fileName
        kind = attachment.kind
        metadata = CommunityReportAttachmentMetadata(attachment: attachment)
    }
}

private struct CommunityReportAttachmentMetadata: Encodable, Sendable {
    var access: CommunityMediaAccessPolicy
    var clientRetentionExpiresAt: Date
    var imageMetadataPolicy: String?
    var spatialVideo: CommunityReportSpatialVideoMetadata?
    var uploadHint: CommunityReportUploadHint
    var source: String

    init(attachment: CommunityReportAttachmentDraft) {
        access = attachment.access
        clientRetentionExpiresAt = CommunityReportMediaPolicy.standard.retentionExpiresAt(for: attachment)
        imageMetadataPolicy = attachment.kind == .photo ? "stripped_on_import" : nil
        spatialVideo = attachment.kind == .video ? CommunityReportSpatialVideoMetadata(attachment: attachment) : nil
        uploadHint = CommunityReportUploadHint(fileName: attachment.fileName, byteSize: attachment.byteSize)
        source = "ios_native"
    }
}

private struct CommunityReportSpatialVideoMetadata: Encodable, Sendable {
    var browserPlayback: String
    var contentType: String
    var mode: CommunitySpatialVideoMode
    var source: String
    var storage: String
    var stereoLayout: String?

    init(attachment: CommunityReportAttachmentDraft) {
        contentType = attachment.contentType
        mode = attachment.spatialVideo.mode
        source = "user_declared"
        storage = "original"
        switch attachment.spatialVideo.mode {
        case .sideBySide:
            browserPlayback = "webxr_stereo"
            stereoLayout = "side_by_side"
        case .overUnder:
            browserPlayback = "webxr_stereo"
            stereoLayout = "over_under"
        case .appleMVHEVC:
            browserPlayback = "2d_fallback"
            stereoLayout = nil
        case .none:
            browserPlayback = "html5_2d"
            stereoLayout = nil
        }
    }
}

private struct CommunityReportUploadHint: Encodable, Sendable {
    var fileName: String
    var byteSize: Int
}

private struct CommunityReportAttachmentSlotResponse: Decodable, Sendable {
    var attachment: CommunityReportAttachmentAPIItem
    var upload: CommunityReportUploadDescriptor
}

private struct CommunityReportAttachmentAPIItem: Decodable, Sendable {
    var attachmentId: String
}

private struct CommunityReportUploadDescriptor: Decodable, Sendable {
    var uploadUrl: URL?
    var method: String
    var headers: [String: String]

    enum CodingKeys: String, CodingKey {
        case uploadUrl
        case method
        case headers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadUrl = try container.decodeIfPresent(URL.self, forKey: .uploadUrl)
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? "PUT"
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    }
}

private struct CommunityReportAttachmentCompleteRequest: Encodable, Sendable {
    var byteSize: Int
    var checksumSha256: String?
}

private extension AlertSeverity {
    var communityReportHazardSeverity: String {
        switch self {
        case .info:
            return "advisory"
        case .warning:
            return "warning"
        case .critical:
            return "critical"
        }
    }
}
