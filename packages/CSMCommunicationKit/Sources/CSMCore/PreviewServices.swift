import Foundation

struct PreviewCopAPIClient: CopAPIClientProtocol, Sendable {
    func bootstrap(seconds: Int) async throws -> MobileBootstrap {
        MobileBootstrap.preview(historySeconds: seconds)
    }

    func offlineSnapshot(seconds: Int) async throws -> MobileOfflineSnapshot {
        MobileBootstrap.preview(historySeconds: seconds).snapshot
    }

    func mapCatalog(locale: String, includeDiagnostics: Bool, includePartner: Bool) async throws -> MapLayerCatalog {
        MapLayerCatalog.nativeFallback
    }

    func mapFeatures(_ request: MapFeatureQueryRequest) async throws -> MapFeatureQueryResponse {
        MapFeatureQueryResponse.preview(for: request)
    }

    func transitVehicleDetail(featureId: String, sourceId: String?) async throws -> TransitVehicleDetail {
        TransitVehicleDetail(
            contractVersion: "sim-public-transit-vehicle-detail-v1",
            featureId: featureId,
            generatedAt: .now,
            observedAt: .now.addingTimeInterval(-18),
            vehicle: TransitVehicle(
                id: featureId,
                vehicleId: "preview-bus-4069",
                label: "Bus 4069",
                operatorName: "PID",
                routeShortName: "119",
                destination: "Letiště",
                transportMode: "bus",
                currentStatus: "IN_TRANSIT_TO",
                status: "active",
                delaySeconds: 45,
                occupancyStatus: nil,
                occupancyPercent: nil,
                currentStopSequence: 6,
                observedAt: .now.addingTimeInterval(-18),
                position: TransitVehiclePosition(lat: 50.101, lon: 14.394, speedMps: 8.4, headingDeg: 282, observedAt: .now.addingTimeInterval(-18))
            ),
            trip: TransitTrip(
                tripId: "preview-trip-119",
                routeId: "pid-119",
                routeShortName: "119",
                destination: "Letiště",
                headsign: "Letiště",
                status: "scheduled",
                vehicleId: "preview-bus-4069"
            ),
            route: TransitRoute(
                routeId: "pid-119",
                routeShortName: "119",
                routeLongName: "Nádraží Veleslavín - Letiště",
                destination: "Letiště",
                direction: "outbound",
                headsign: "Letiště",
                transportMode: "bus",
                shape: nil
            ),
            routeShape: TransitRouteShape(coordinates: [
                [14.3892, 50.0950],
                [14.3972, 50.1007],
                [14.4088, 50.1033],
                [14.4210, 50.1017],
                [14.4350, 50.0980]
            ]),
            stopTimes: [
                TransitStopTime(sequence: 5, stopSequence: 5, stopId: "pid-veleslavin", stopName: "Nádraží Veleslavín", name: nil, scheduledArrival: nil, scheduledDeparture: nil, realtimeArrival: nil, realtimeDeparture: nil, arrivalTime: nil, departureTime: nil, delaySeconds: 45, status: "departed", relationToVehicle: "behind"),
                TransitStopTime(sequence: 6, stopSequence: 6, stopId: "pid-divoka-sarka", stopName: "Divoká Šárka", name: nil, scheduledArrival: nil, scheduledDeparture: nil, realtimeArrival: nil, realtimeDeparture: nil, arrivalTime: nil, departureTime: nil, delaySeconds: 45, status: "current", relationToVehicle: "current"),
                TransitStopTime(sequence: 7, stopSequence: 7, stopId: "pid-airport", stopName: "Terminál 1", name: nil, scheduledArrival: nil, scheduledDeparture: nil, realtimeArrival: nil, realtimeDeparture: nil, arrivalTime: nil, departureTime: nil, delaySeconds: 45, status: "upcoming", relationToVehicle: "ahead")
            ],
            quality: TransitDetailQuality(
                staticModelAvailable: true,
                vehiclePositionAvailable: true,
                realtimeVehicleAvailable: true,
                tripScheduleAvailable: true,
                tripUpdateAvailable: true,
                routeShapeAvailable: true,
                shapeAvailable: true,
                stale: false,
                warnings: []
            ),
            serviceAlerts: [],
            warnings: []
        )
    }

    func mapRasterOverlayImage(url: String) async throws -> Data {
        Data(base64Encoded: Self.transparentPNGBase64) ?? Data()
    }

    func weatherWebcamResource(url: String) async throws -> Data {
        Data(base64Encoded: Self.transparentPNGBase64) ?? Data()
    }

    func weatherRadarFrames(product: String, hours: Int, limit: Int) async throws -> WeatherRadarFrameCatalog {
        let frameCount = min(max(limit, 1), 8)
        let now = Date()
        let bounds = MapFeatureBoundingBox(west: 12.09, south: 48.55, east: 18.86, north: 51.06)
        let frames = (0..<frameCount).map { index in
            let observedAt = now.addingTimeInterval(Double(index - frameCount + 1) * 15 * 60)
            return WeatherRadarFrame(
                id: "preview-radar-\(index)",
                cleanURL: "/api/v1/weather-radar/clean/merge1h/preview-\(index).png",
                bounds: bounds,
                observedAt: observedAt,
                validAt: observedAt,
                label: observedAt.formatted(date: .omitted, time: .shortened),
                opacity: 0.52
            )
        }
        return WeatherRadarFrameCatalog(product: product, generatedAt: now, frames: frames)
    }

    func sketchPalettes() async throws -> SketchPaletteCatalog {
        SketchPaletteCatalog(
            generatedAt: .now,
            modes: [
                SketchPaletteMode.civil.rawValue: SketchPaletteModeDefinition(
                    label: CSMLocalization.text("preview.map.sketch.palette.civil", fallback: "Civilní"),
                    symbols: [
                        SketchPaletteSymbol(iconId: "warning", label: CSMLocalization.text("preview.map.sketch.symbol.warning", fallback: "Varování"), description: nil, sidc: nil, palette: .civil),
                        SketchPaletteSymbol(iconId: "route", label: CSMLocalization.text("preview.map.sketch.symbol.route", fallback: "Trasa"), description: nil, sidc: nil, palette: .civil),
                        SketchPaletteSymbol(iconId: "closure", label: CSMLocalization.text("preview.map.sketch.symbol.closure", fallback: "Uzávěra"), description: nil, sidc: nil, palette: .civil)
                    ]
                ),
                SketchPaletteMode.professional.rawValue: SketchPaletteModeDefinition(
                    label: CSMLocalization.text("preview.map.sketch.palette.professional", fallback: "Profesionální"),
                    symbols: [
                        SketchPaletteSymbol(iconId: "control-point", label: CSMLocalization.text("preview.map.sketch.symbol.control_point", fallback: "Kontrolní bod"), description: nil, sidc: "GFGPGPP---", palette: .professional),
                        SketchPaletteSymbol(iconId: "assembly-area", label: CSMLocalization.text("preview.map.sketch.symbol.assembly_area", fallback: "Shromaždiště"), description: nil, sidc: "GFGPGAA---", palette: .professional)
                    ]
                )
            ]
        )
    }

    func sketchDrawings(bbox: MapFeatureBoundingBox?, limit: Int) async throws -> SketchDrawingCollection {
        let now = Date()
        let drawings = [
            SketchDrawing(
                id: "preview-sketch-line",
                geometry: .lineString([
                    [14.4108, 50.0849],
                    [14.4214, 50.0887],
                    [14.4351, 50.0864]
                ]),
                properties: SketchDrawingProperties(
                    drawingId: "preview-sketch-line",
                    kind: .measurement,
                    visibility: .group,
                    label: CSMLocalization.text("preview.map.sketch.line", fallback: "Přístupová trasa"),
                    ownerSubjectId: "preview-subject",
                    ownerUsername: "operator",
                    ownerDisplayName: CSMLocalization.text("preview.person.operator", fallback: "Operátor"),
                    style: SketchDrawingStyle(stroke: "#27AE60", fill: nil, opacity: 0.88, lineWidth: 3),
                    symbol: SketchDrawingSymbol(palette: SketchPaletteMode.civil.rawValue, iconId: "route", sidc: nil),
                    properties: ["source": .string("preview")],
                    revision: 1,
                    createdAt: now.addingTimeInterval(-600),
                    updatedAt: now.addingTimeInterval(-360)
                )
            ),
            SketchDrawing(
                id: "preview-sketch-polygon",
                geometry: .polygon([[
                    [14.3920, 50.0750],
                    [14.4055, 50.0738],
                    [14.4084, 50.0838],
                    [14.3957, 50.0871],
                    [14.3920, 50.0750]
                ]]),
                properties: SketchDrawingProperties(
                    drawingId: "preview-sketch-polygon",
                    kind: .polygon,
                    visibility: .event,
                    label: CSMLocalization.text("preview.map.sketch.area", fallback: "Uzavřená zóna"),
                    ownerSubjectId: "preview-commander",
                    ownerUsername: "commander",
                    ownerDisplayName: CSMLocalization.text("preview.conversation.shift_commander", fallback: "Velitel směny"),
                    style: SketchDrawingStyle(stroke: "#F2994A", fill: "#F2994A", opacity: 0.22, lineWidth: 2.5),
                    symbol: SketchDrawingSymbol(palette: SketchPaletteMode.civil.rawValue, iconId: "closure", sidc: nil),
                    properties: ["source": .string("preview")],
                    revision: 1,
                    createdAt: now.addingTimeInterval(-1_200),
                    updatedAt: now.addingTimeInterval(-480)
                )
            )
        ]
        return SketchDrawingCollection(generatedAt: now, features: Array(drawings.prefix(max(0, min(limit, drawings.count)))))
    }

    func sketchDrawing(drawingId: String) async throws -> SketchDrawing {
        let drawings = try await sketchDrawings(bbox: nil, limit: 20).features
        guard let drawing = drawings.first(where: { $0.id == drawingId || $0.drawingId == drawingId }) else {
            throw CSMServiceError.unavailable("Sketch drawing not found.")
        }
        return drawing
    }

    func createSketchDrawing(_ request: SketchDrawingCreateRequest) async throws -> SketchDrawing {
        let drawingId = "preview-sketch-\(UUID().uuidString)"
        return SketchDrawing(
            id: drawingId,
            geometry: request.geometry,
            properties: SketchDrawingProperties(
                drawingId: drawingId,
                kind: request.kind,
                visibility: request.visibility,
                label: request.label ?? "",
                groupId: request.groupId,
                eventId: request.eventId,
                ownerSubjectId: "preview-subject",
                ownerUsername: "operator",
                ownerDisplayName: CSMLocalization.text("preview.person.operator", fallback: "Operátor"),
                style: request.style,
                symbol: request.symbol,
                properties: request.properties ?? [:],
                locked: request.locked ?? false,
                revision: 1,
                createdAt: .now,
                updatedAt: .now
            )
        )
    }

    func updateSketchDrawing(drawingId: String, request: SketchDrawingUpdateRequest) async throws -> SketchDrawing {
        var drawing = try await sketchDrawing(drawingId: drawingId)
        drawing.geometry = request.geometry ?? drawing.geometry
        drawing.properties.label = request.label ?? drawing.properties.label
        drawing.properties.style = request.style ?? drawing.properties.style
        drawing.properties.symbol = request.symbol ?? drawing.properties.symbol
        drawing.properties.properties = request.properties ?? drawing.properties.properties
        drawing.properties.locked = request.locked ?? drawing.properties.locked
        drawing.properties.revision = (drawing.properties.revision ?? 0) + 1
        drawing.properties.updatedAt = .now
        return drawing
    }

    func deleteSketchDrawing(drawingId: String) async throws {}

    func userPreferenceProfile() async throws -> UserPreferenceProfile {
        MobileBootstrap.preview(historySeconds: 180).preferenceProfile
    }

    func updateUserPreferences(_ update: UserPreferenceUpdate) async throws -> UserPreferenceProfile {
        let bootstrap = MobileBootstrap.preview(historySeconds: 180)
        return UserPreferenceProfile(
            actor: bootstrap.actor,
            alertPreferences: update.alertPreferences ?? bootstrap.profile.alertPreferences,
            preferences: update.preferences,
            updatedAt: .now
        )
    }

    func alerts(includeAcknowledged: Bool) async throws -> [CopAlert] {
        let alerts = MobileBootstrap.preview(historySeconds: 180).snapshot.alerts
        return includeAcknowledged ? alerts : alerts.filter { $0.status == .active }
    }

    func acknowledgeAlert(alertId: String, note: String?) async throws -> CopAlert {
        let existingAlert = MobileBootstrap.preview(historySeconds: 180).snapshot.alerts.first { $0.alertId == alertId }
        guard var alert = existingAlert else {
            throw CSMServiceError.unavailable("Alert not found.")
        }
        alert.status = .acknowledged
        alert.acknowledgedAt = .now
        alert.updatedAt = .now
        return alert
    }

    func messagingStatus() async throws -> MessagingStatus {
        MessagingStatus(
            chatAvailable: true,
            checkedAt: .now,
            contractVersion: "cop-messaging-status-v1",
            enabled: true,
            providerId: "csm.messaging",
            serviceName: "CSM Messaging",
            status: "online",
            warnings: []
        )
    }

    func messagingBootstrap(deviceId: String) async throws -> MessagingBootstrap {
        MessagingBootstrap(
            accessToken: "preview-token",
            chatAvailable: true,
            contractVersion: "cop-messaging-bootstrap-v1",
            deviceId: deviceId,
            e2eeRequired: true,
            enabled: true,
            expiresAt: Calendar.current.date(byAdding: .minute, value: 30, to: .now),
            homeserverBaseUrl: URL(string: "https://msg.zeleznalady.cz"),
            providerId: "csm.messaging",
            serverName: "msg.zeleznalady.cz",
            status: "online",
            tokenAvailable: true,
            userId: "@preview:msg.zeleznalady.cz",
            warnings: []
        )
    }

    func startVoiceCall(_ request: CSMVoiceCallStartRequest) async throws -> CSMVoiceCallSession {
        Self.previewVoiceCallSession(
            callId: UUID().uuidString.lowercased(),
            roomId: request.roomId,
            title: request.title ?? "Ukázkový hovor",
            phase: .ringing,
            revision: 1
        )
    }

    func voiceCalls(roomId: String?, activeOnly: Bool, limit: Int) async throws -> [CSMVoiceCall] {
        []
    }

    func voiceCall(callId: String) async throws -> CSMVoiceCallSession {
        Self.previewVoiceCallSession(
            callId: callId,
            roomId: "!preview:msg.zeleznalady.cz",
            title: "Ukázkový hovor",
            phase: .connected,
            revision: 3
        )
    }

    func transitionVoiceCall(
        callId: String,
        request: CSMVoiceCallActionRequest
    ) async throws -> CSMVoiceCallSession {
        let phase: CSMVoiceCallPhase = switch request.action {
        case .accept:
            .accepted
        case .mediaConnected, .heartbeat:
            .connected
        case .decline:
            .declined
        case .cancel:
            .cancelled
        case .end:
            .ended
        case .mediaFailed:
            .failed
        }
        return Self.previewVoiceCallSession(
            callId: callId,
            roomId: "!preview:msg.zeleznalady.cz",
            title: "Ukázkový hovor",
            phase: phase,
            revision: (request.expectedRevision ?? 0) + 1
        )
    }

    func mobilePairingSession(code: String) async throws -> MobilePairingSessionResponse {
        makeMobilePairingSessionResponse(code: code, status: .pending)
    }

    func claimMobilePairingSession(
        code: String,
        request: MobilePairingClaimRequest
    ) async throws -> MobilePairingSessionResponse {
        makeMobilePairingSessionResponse(
            code: code,
            status: .confirmed,
            claimedDevice: MobilePairingClaimedDevice(
                deviceId: request.deviceId,
                platform: request.platform,
                appVersion: request.appVersion,
                buildNumber: request.buildNumber,
                deviceModel: request.deviceModel,
                osVersion: request.osVersion,
                matrixDeviceId: request.matrixDeviceId,
                pushTokenRegistered: request.pushTokenRegistered
            )
        )
    }

    func conversations() async throws -> [Conversation] {
        [
            Conversation(
                conversationId: "conv-fire-vrbno",
                title: CSMLocalization.text("preview.conversation.fire_vrbno.title", fallback: "Požár u Vrbna"),
                type: .group,
                status: "online",
                encrypted: true,
                e2eeRequired: true,
                matrix: MessagingMatrixRoom(
                    roomId: "!vrbna:msg.zeleznalady.cz",
                    state: "room_bound",
                    encrypted: true,
                    e2eeAlgorithm: "m.megolm.v1.aes-sha2",
                    homeserverBaseUrl: URL(string: "https://msg.zeleznalady.cz"),
                    serverName: "msg.zeleznalady.cz",
                    boundAt: .now,
                    boundBy: "preview"
                ),
                memberCount: 8,
                mapLinkCount: 2,
                members: [
                    ConversationMember(userId: "u-001", displayName: CSMLocalization.text("preview.person.operator", fallback: "Operátor"), role: "owner"),
                    ConversationMember(
                        userId: "u-002",
                        displayName: CSMLocalization.text("preview.person.patrol2", fallback: "Hlídka 2"),
                        role: "member"
                    )
                ],
                mapLinks: [
                    MessagingMapLink(targetId: "report-fire-001", layerId: "user.community.reports", label: "Report", bbox: nil)
                ],
                metadata: [
                    "source": "cop.community",
                    "externalId": "group-vrbno"
                ],
                unreadCount: 2,
                lastActivityPreview: CSMLocalization.text("preview.conversation.fire_vrbno.last_activity", fallback: "Nová zpráva ve skupině"),
                lastActivityAt: Calendar.current.date(byAdding: .minute, value: -2, to: .now),
                updatedAt: .now
            ),
            Conversation(
                conversationId: "conv-ops-direct",
                title: CSMLocalization.text("preview.conversation.shift_commander", fallback: "Velitel směny"),
                type: .direct,
                status: "online",
                encrypted: true,
                e2eeRequired: true,
                memberCount: 2,
                mapLinkCount: 0,
                members: [
                    ConversationMember(userId: "u-001", displayName: CSMLocalization.text("preview.person.operator", fallback: "Operátor"), role: "member"),
                    ConversationMember(
                        userId: "u-003",
                        displayName: CSMLocalization.text("preview.conversation.shift_commander", fallback: "Velitel směny"),
                        role: "member",
                        avatarDataUrl: MobileBootstrap.previewAvatarDataUrl
                    )
                ],
                mapLinks: [],
                unreadCount: 0,
                lastActivityPreview: CSMLocalization.text("preview.conversation.direct.last_activity", fallback: "Poslední aktivita v přímé zprávě"),
                lastActivityAt: Calendar.current.date(byAdding: .minute, value: -8, to: .now),
                updatedAt: Calendar.current.date(byAdding: .minute, value: -8, to: .now)
            ),
            Conversation(
                conversationId: "conv-vodvaz",
                title: "VODVAZ",
                type: .group,
                status: "online",
                encrypted: true,
                e2eeRequired: true,
                memberCount: 3,
                mapLinkCount: 0,
                members: [
                    ConversationMember(userId: "u-001", displayName: "Operátor", role: "member"),
                    ConversationMember(userId: "u-004", displayName: "Jiřina Volková", role: "member")
                ],
                mapLinks: [],
                unreadCount: 0,
                lastActivityPreview: "Jiřina: Kontrola úseku dokončena",
                lastActivityAt: Calendar.current.date(byAdding: .minute, value: -16, to: .now),
                updatedAt: Calendar.current.date(byAdding: .minute, value: -16, to: .now)
            ),
            Conversation(
                conversationId: "conv-ai-test",
                title: "AI test",
                type: .group,
                status: "online",
                encrypted: true,
                e2eeRequired: true,
                memberCount: 4,
                mapLinkCount: 1,
                members: [
                    ConversationMember(userId: "u-001", displayName: "Operátor", role: "owner")
                ],
                mapLinks: [],
                unreadCount: 0,
                lastActivityPreview: "Petr: Podklady jsou připravené",
                lastActivityAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now),
                updatedAt: Calendar.current.date(byAdding: .hour, value: -1, to: .now)
            ),
            Conversation(
                conversationId: "conv-event-bebicko",
                title: "Událost: Bebíčko",
                type: .group,
                status: "online",
                encrypted: true,
                e2eeRequired: true,
                memberCount: 2,
                mapLinkCount: 2,
                members: [
                    ConversationMember(userId: "u-001", displayName: "Operátor", role: "member")
                ],
                mapLinks: [],
                unreadCount: 0,
                lastActivityPreview: "Velitel: Situace je stabilní",
                lastActivityAt: Calendar.current.date(byAdding: .hour, value: -3, to: .now),
                updatedAt: Calendar.current.date(byAdding: .hour, value: -3, to: .now)
            )
        ]
    }

    private func makeMobilePairingSessionResponse(
        code: String,
        status: MobilePairingSessionStatus,
        claimedDevice: MobilePairingClaimedDevice? = nil
    ) -> MobilePairingSessionResponse {
        let now = Date()
        return MobilePairingSessionResponse(
            contractVersion: "cop-mobile-pairing-v1",
            device: status == .confirmed ? MobilePairedDevice(
                deviceId: claimedDevice?.deviceId ?? "preview-ios-device",
                deviceSessionId: "preview-device-session",
                platform: "ios",
                status: "active",
                subjectId: "preview-subject",
                pushTokenRegistered: claimedDevice?.pushTokenRegistered,
                pairedAt: now,
                registeredAt: now
            ) : nil,
            pairing: MobilePairingSession(
                code: code,
                status: status,
                expiresAt: now.addingTimeInterval(10 * 60),
                links: MobilePairingLinks(
                    customSchemeUrl: URL(string: "csm://pair?code=\(code)")!,
                    universalLink: URL(string: "https://cop.zeleznalady.cz/mobile/pair/\(code)")!
                ),
                createdBy: MobilePairingActor(subjectId: "preview-subject", username: "operator", displayName: "COP Operator"),
                claimedBy: status == .pending ? nil : MobilePairingActor(subjectId: "preview-subject", username: "operator", displayName: "COP Operator"),
                claimedDevice: claimedDevice,
                claimedAt: status == .pending ? nil : now,
                confirmedAt: status == .confirmed ? now : nil,
                createdAt: now.addingTimeInterval(-60)
            ),
            policy: nil,
            security: MobilePairingSecurity(
                containsAccessToken: false,
                containsRecoveryKey: false,
                containsRoomKeys: false,
                confirmationRequired: true
            ),
            serverTimestamp: now
        )
    }

    func registerDevice(_ registration: MobileDeviceRegistration) async throws -> MobileDeviceRegistrationResponse {
        MobileDeviceRegistrationResponse(
            deviceSessionId: UUID().uuidString,
            pushTokenRegistered: false,
            policy: MobileBootstrap.preview(historySeconds: 180).policy,
            serverTimestamp: .now
        )
    }

    func communityReports() async throws -> [CommunityReport] {
        [
            CommunityReport(
                reportId: "community-fire-vrbno",
                category: .fire,
                title: CSMLocalization.text("preview.report.smoke_north.title", fallback: "Kouř u severní cesty"),
                description: CSMLocalization.text("preview.report.smoke_north.description", fallback: "Občan hlásí viditelný kouř a zhoršenou průjezdnost."),
                location: GeoPoint(lat: 50.121, lon: 17.383, accuracyM: 18, source: "device"),
                severity: .warning,
                status: "submitted",
                groupId: "group-vrbno",
                groupName: CSMLocalization.text("preview.conversation.fire_vrbno.title", fallback: "Požár u Vrbna"),
                attachmentCount: 2,
                observedAt: Calendar.current.date(byAdding: .minute, value: -14, to: .now) ?? .now
            ),
            CommunityReport(
                reportId: "community-road-bridge",
                category: .roadBlockage,
                title: CSMLocalization.text("preview.report.fallen_tree.title", fallback: "Padlý strom přes cestu"),
                description: CSMLocalization.text("preview.report.fallen_tree.description", fallback: "Místní obyvatel označil neprůjezdný úsek."),
                location: GeoPoint(lat: 50.094, lon: 14.466, accuracyM: 30, source: "manual"),
                severity: .info,
                status: "published",
                groupId: nil,
                groupName: CSMLocalization.text("preview.report.traffic_group", fallback: "Doprava"),
                attachmentCount: 1,
                observedAt: Calendar.current.date(byAdding: .minute, value: -45, to: .now) ?? .now
            )
        ]
    }

    func submitCommunityReport(_ draft: CommunityReportDraft) async throws -> CommunityReportSubmission {
        CommunityReportSubmission(
            reportId: draft.id,
            status: "submitted",
            submittedAt: .now,
            uploadedAttachmentCount: draft.attachments.count
        )
    }

    private static func previewVoiceCallSession(
        callId: String,
        roomId: String,
        title: String,
        phase: CSMVoiceCallPhase,
        revision: Int
    ) -> CSMVoiceCallSession {
        let now = Date()
        return CSMVoiceCallSession(
            contractVersion: "cop-voice-call-v1",
            call: CSMVoiceCall(
                callId: callId,
                connectedAt: phase == .connected ? now : nil,
                createdAt: now.addingTimeInterval(-5),
                direction: .outgoing,
                endedAt: phase.isTerminal ? now : nil,
                endReason: nil,
                expiresAt: now.addingTimeInterval(45),
                initiatorSubjectId: "preview-subject",
                kind: .direct,
                participantSubjectIds: ["preview-subject", "preview-contact"],
                phase: phase,
                revision: revision,
                roomId: roomId,
                title: title,
                updatedAt: now
            ),
            media: nil
        )
    }

    private static let transparentPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
}

actor PreviewMessagingClient: MessagingClientProtocol {
    private var configured = false
    private var messagesByConversation: [String: [ChatMessage]] = [:]

    func configure(with bootstrap: MessagingBootstrap) async throws {
        guard bootstrap.chatAvailable, bootstrap.tokenAvailable else {
            throw CSMServiceError.disabled("Messaging bootstrap is not available.")
        }
        configured = true
    }

    func messages(for conversation: Conversation) async throws -> [ChatMessage] {
        guard configured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        if let messages = messagesByConversation[conversation.conversationId] {
            return messages
        }
        let seeded = [
            ChatMessage(
                id: "preview-message-smoke-\(conversation.conversationId)",
                roomId: conversation.conversationId,
                senderId: "u-002",
                senderDisplayName: conversation.type == .direct ? conversation.title : CSMLocalization.text("preview.person.patrol2", fallback: "Hlídka 2"),
                body: conversation.type == .direct
                    ? CSMLocalization.text("preview.message.connection_ready", fallback: "Spojení je připravené.")
                    : CSMLocalization.text("preview.message.smoke_visible", fallback: "Kouř je vidět od severní cesty."),
                reactions: conversation.type == .group ? [MessageReaction(emoji: "!", count: 2)] : [],
                sentAt: Calendar.current.date(byAdding: .minute, value: -12, to: .now) ?? .now,
                deliveryState: .read,
                isOwnMessage: false
            ),
            ChatMessage(
                id: "preview-message-context-\(conversation.conversationId)",
                roomId: conversation.conversationId,
                senderId: "u-001",
                senderDisplayName: CSMLocalization.text("preview.person.operator", fallback: "Operátor"),
                body: CSMLocalization.text("preview.message.confirm_map_context", fallback: "Potvrzuji, připojuji mapový kontext."),
                replyTo: conversation.type == .group
                    ? MessageReplyReference(
                        messageId: "preview-context",
                        senderDisplayName: CSMLocalization.text("preview.person.patrol2", fallback: "Hlídka 2"),
                        bodyPreview: CSMLocalization.text("preview.message.smoke_visible", fallback: "Kouř je vidět od severní cesty.")
                    )
                    : nil,
                sentAt: Calendar.current.date(byAdding: .minute, value: -10, to: .now) ?? .now,
                deliveryState: .read,
                isOwnMessage: true
            ),
            ChatMessage(
                id: "preview-message-attachments-\(conversation.conversationId)",
                roomId: conversation.conversationId,
                senderId: "u-002",
                senderDisplayName: conversation.type == .direct ? conversation.title : CSMLocalization.text("preview.person.patrol2", fallback: "Hlídka 2"),
                body: conversation.type == .direct
                    ? CSMLocalization.text("preview.message.direct_followup", fallback: "Posílám potvrzení pro směnu.")
                    : CSMLocalization.text("preview.message.field_documents", fallback: "Posílám podklady k zásahu a objektu."),
                attachments: conversation.type == .group ? Self.previewFieldDocumentAttachments() : [],
                sentAt: Calendar.current.date(byAdding: .minute, value: -7, to: .now) ?? .now,
                deliveryState: .read,
                isOwnMessage: false
            )
        ]
        messagesByConversation[conversation.conversationId] = seeded
        return seeded
    }

    func sendMessage(_ body: String, to conversation: Conversation) async throws -> ChatMessage {
        try await sendMessage(OutgoingMessageDraft(body: body), to: conversation)
    }

    func sendMessage(_ draft: OutgoingMessageDraft, to conversation: Conversation) async throws -> ChatMessage {
        guard configured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        guard !draft.isEmpty else {
            throw CSMServiceError.invalidState("Message draft is empty.")
        }
        if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
            throw CSMServiceError.invalidState(validationError)
        }
        let message = ChatMessage(
            id: UUID().uuidString,
            roomId: conversation.conversationId,
            senderId: "u-001",
            senderDisplayName: "Operator",
            body: draft.body,
            attachments: draft.attachments,
            replyTo: draft.replyTo,
            sentAt: .now,
            deliveryState: .sent,
            isOwnMessage: true
        )
        var messages = messagesByConversation[conversation.conversationId, default: []]
        messages.append(message)
        messagesByConversation[conversation.conversationId] = messages
        return message
    }

    func leaveConversation(_ conversation: Conversation) async throws {
        guard configured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        messagesByConversation.removeValue(forKey: conversation.conversationId)
    }

    private static func previewFieldDocumentAttachments() -> [MessageAttachment] {
        [
            MessageAttachment(
                id: "preview-attachment-pdf",
                kind: .document,
                title: "zasahovy-plan.pdf",
                mimeType: "application/pdf",
                byteCount: 248_000,
                localOnly: false
            ),
            MessageAttachment(
                id: "preview-attachment-xlsx",
                kind: .document,
                title: "evakuacni-seznam.xlsx",
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                byteCount: 64_000,
                localOnly: false
            ),
            MessageAttachment(
                id: "preview-attachment-pptx",
                kind: .document,
                title: "situacni-brief.pptx",
                mimeType: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                byteCount: 320_000,
                localOnly: false
            ),
            MessageAttachment(
                id: "preview-attachment-ifc",
                kind: .document,
                title: "budova-sever.ifc",
                mimeType: "application/x-step",
                byteCount: 1_280_000,
                localOnly: false
            ),
            MessageAttachment(
                id: "preview-attachment-zip",
                kind: .document,
                title: "foto-dokumentace.zip",
                mimeType: "application/zip",
                byteCount: 840_000,
                localOnly: false
            )
        ]
    }

    func toggleReaction(_ emoji: String, on message: ChatMessage, in conversation: Conversation) async throws -> ChatMessage {
        guard configured else {
            throw CSMServiceError.invalidState("Messaging client is not configured.")
        }
        let updated = message.applyingReactionToggle(emoji, ownEventId: "preview-\(UUID().uuidString)")
        var messages = messagesByConversation[conversation.conversationId, default: []]
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = updated
        } else {
            messages.append(updated)
        }
        messagesByConversation[conversation.conversationId] = messages
        return updated
    }

    func registerPusher(pushKey: String, pushGatewayURL: URL) async {}
}

actor InMemoryOfflineStore: SecureSnapshotStoring {
    private var snapshots: [String: MobileOfflineSnapshot] = [:]

    func loadSnapshot(for subjectId: String) async throws -> MobileOfflineSnapshot? {
        snapshots[subjectId]
    }

    func saveSnapshot(_ snapshot: MobileOfflineSnapshot, subjectId: String) async throws {
        snapshots[subjectId] = snapshot
    }

    func clear(for subjectId: String) async throws {
        snapshots.removeValue(forKey: subjectId)
    }
}

actor InMemoryOfflineMapPackStore: OfflineMapPackStoring {
    private var packsBySubject: [String: [OfflineMapPack]] = [:]

    func loadPacks(for subjectId: String) async throws -> [OfflineMapPack] {
        packsBySubject[subjectId, default: []]
    }

    func savePacks(_ packs: [OfflineMapPack], subjectId: String) async throws {
        packsBySubject[subjectId] = packs
    }

    func clear(for subjectId: String) async throws {
        packsBySubject.removeValue(forKey: subjectId)
    }
}

actor InMemoryMessagingBootstrapStore: MessagingBootstrapStoring {
    private var records: [String: MessagingBootstrap] = [:]

    func load(subjectId: String, deviceId: String) async throws -> MessagingBootstrap? {
        records[Self.recordId(subjectId: subjectId, deviceId: deviceId)]
    }

    func save(_ bootstrap: MessagingBootstrap, subjectId: String, deviceId: String) async throws {
        records[Self.recordId(subjectId: subjectId, deviceId: deviceId)] = bootstrap
    }

    func clear(subjectId: String, deviceId: String?) async throws {
        guard let deviceId else {
            records = records.filter { !$0.key.hasPrefix("\(subjectId)|") }
            return
        }
        records.removeValue(forKey: Self.recordId(subjectId: subjectId, deviceId: deviceId))
    }

    private static func recordId(subjectId: String, deviceId: String) -> String {
        "\(subjectId)|\(deviceId)"
    }
}

actor InMemoryOfflineMapTileStore: OfflineMapTileStoring {
    private var tiles: [String: Data] = [:]
    private var summariesBySubject: [String: [OfflineMapTileCacheSummary]] = [:]

    func saveTile(_ data: Data, coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws {
        tiles[Self.tileId(coordinate: coordinate, packId: packId, subjectId: subjectId)] = data
    }

    func loadTile(coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws -> Data? {
        tiles[Self.tileId(coordinate: coordinate, packId: packId, subjectId: subjectId)]
    }

    func saveSummary(_ summary: OfflineMapTileCacheSummary, subjectId: String) async throws {
        var summaries = summariesBySubject[subjectId, default: []]
        summaries.removeAll { $0.packId == summary.packId }
        summaries.append(summary)
        summariesBySubject[subjectId] = summaries
    }

    func loadSummary(packId: String, subjectId: String) async throws -> OfflineMapTileCacheSummary? {
        summariesBySubject[subjectId, default: []].first { $0.packId == packId }
    }

    func clear(for subjectId: String) async throws {
        summariesBySubject.removeValue(forKey: subjectId)
        tiles = tiles.filter { !$0.key.hasPrefix("\(subjectId):") }
    }

    private static func tileId(coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) -> String {
        "\(subjectId):\(packId):\(coordinate.id)"
    }
}

struct PreviewOfflineMapTileFetcher: OfflineMapTileFetching {
    func data(for url: URL) async throws -> Data {
        Data(base64Encoded: Self.transparentPNGBase64) ?? Data()
    }

    private static let transparentPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
}

actor InMemoryCommunityOutbox: CommunityOutboxStoring {
    private var drafts: [CommunityReportDraft] = []
    private let mediaPolicy: CommunityReportMediaPolicy

    init(mediaPolicy: CommunityReportMediaPolicy = .standard) {
        self.mediaPolicy = mediaPolicy
    }

    func enqueue(_ draft: CommunityReportDraft) async throws {
        drafts = mediaPolicy.retentionResult(for: drafts).retainedDrafts
        try mediaPolicy.validateDraft(draft, existingDrafts: drafts)
        drafts.append(draft)
    }

    func pendingDrafts() async throws -> [CommunityReportDraft] {
        drafts = mediaPolicy.retentionResult(for: drafts).retainedDrafts
        return drafts
    }

    func removeDraft(id: String) async throws {
        drafts.removeAll { $0.id == id }
    }

    func clear() async throws {
        drafts = []
    }
}

actor InMemoryMessageOutbox: MessageOutboxStoring {
    private var recordsByConversation: [String: [PendingMessageRecord]] = [:]

    func enqueue(_ message: ChatMessage, conversation: Conversation) async throws {
        var records = recordsByConversation[conversation.conversationId, default: []]
        records.removeAll { $0.message.id == message.id }
        records.append(PendingMessageRecord(conversationId: conversation.conversationId, message: message))
        recordsByConversation[conversation.conversationId] = records.sorted { $0.queuedAt < $1.queuedAt }
    }

    func pendingMessages(for conversationId: String) async throws -> [ChatMessage] {
        recordsByConversation[conversationId, default: []].map(\.message)
    }

    func pendingRecords(for conversationId: String) async throws -> [PendingMessageRecord] {
        recordsByConversation[conversationId, default: []]
    }

    func pendingMessageCount() async throws -> Int {
        recordsByConversation.values.reduce(0) { $0 + $1.count }
    }

    func recordAttempt(messageId: String, conversationId: String, error: String, retryAfter: TimeInterval) async throws {
        let now = Date()
        recordsByConversation[conversationId, default: []] = recordsByConversation[conversationId, default: []].map { record in
            guard record.message.id == messageId else { return record }
            var updated = record
            updated.attemptCount += 1
            updated.lastAttemptAt = now
            updated.nextRetryAt = now.addingTimeInterval(retryAfter)
            updated.lastError = error
            if updated.attemptCount >= 3 {
                updated.message.deliveryState = .failed
            }
            return updated
        }
    }

    func removeMessage(id: String, conversationId: String) async throws {
        recordsByConversation[conversationId, default: []].removeAll { $0.message.id == id }
        if recordsByConversation[conversationId]?.isEmpty == true {
            recordsByConversation.removeValue(forKey: conversationId)
        }
    }

    @discardableResult
    func discardPendingMessages(for conversationId: String) async throws -> Int {
        let removed = recordsByConversation[conversationId, default: []].count
        recordsByConversation.removeValue(forKey: conversationId)
        return removed
    }

    func clear() async throws {
        recordsByConversation = [:]
    }
}

actor InMemoryMessageHistoryStore: MessageHistoryStoring {
    private var messagesByConversation: [String: [ChatMessage]] = [:]
    private let maxMessagesPerConversation: Int

    init(maxMessagesPerConversation: Int = 500) {
        self.maxMessagesPerConversation = maxMessagesPerConversation
    }

    func messages(for conversationId: String) async throws -> [ChatMessage] {
        messagesByConversation[conversationId, default: []]
    }

    func saveMessages(_ messages: [ChatMessage], conversationId: String) async throws {
        messagesByConversation[conversationId] = trimmed(merged(existing: [], incoming: messages))
    }

    func appendMessage(_ message: ChatMessage, conversationId: String) async throws {
        let existing = messagesByConversation[conversationId, default: []]
        messagesByConversation[conversationId] = trimmed(merged(existing: existing, incoming: [message]))
    }

    func removeMessages(for conversationId: String) async throws {
        messagesByConversation.removeValue(forKey: conversationId)
    }

    func clear() async throws {
        messagesByConversation = [:]
    }

    private func merged(existing: [ChatMessage], incoming: [ChatMessage]) -> [ChatMessage] {
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for message in incoming {
            byId[message.id] = message
        }
        return byId.values.sorted { $0.sentAt < $1.sentAt }
    }

    private func trimmed(_ messages: [ChatMessage]) -> [ChatMessage] {
        Array(messages.suffix(maxMessagesPerConversation))
    }
}

actor InMemoryCrisisEventLog: CrisisEventLogging {
    private var eventsBySubject: [String: [CrisisEventLogEntry]] = [:]

    func append(_ entry: CrisisEventLogEntry) async throws {
        var events = eventsBySubject[entry.subjectId, default: []]
        events.append(entry)
        eventsBySubject[entry.subjectId] = Array(events.suffix(500))
    }

    func entries(for subjectId: String, limit: Int) async throws -> [CrisisEventLogEntry] {
        let events = eventsBySubject[subjectId, default: []]
        guard limit < events.count else { return events }
        return Array(events.suffix(max(0, limit)))
    }

    func clear(for subjectId: String) async throws {
        eventsBySubject.removeValue(forKey: subjectId)
    }
}

actor InMemoryCrisisRelayReplayStore: CrisisRelayReplayProtecting {
    private var seenBySubject: [String: [String: Date]] = [:]

    func hasSeen(envelopeId: String, subjectId: String) async throws -> Bool {
        guard let expiresAt = seenBySubject[subjectId]?[envelopeId] else { return false }
        return expiresAt > Date()
    }

    func markSeen(envelopeId: String, subjectId: String, expiresAt: Date) async throws {
        var seen = seenBySubject[subjectId, default: [:]]
        seen = seen.filter { $0.value > Date() }
        seen[envelopeId] = expiresAt
        seenBySubject[subjectId] = seen
    }

    func clearExpired(subjectId: String, now: Date) async throws {
        seenBySubject[subjectId] = seenBySubject[subjectId, default: [:]]
            .filter { $0.value > now }
    }
}

actor InMemoryCrisisRelayQueueStore: CrisisRelayQueueStoring {
    private var envelopesBySubject: [String: [CrisisRelayEnvelope]] = [:]

    func queuedEnvelopes(subjectId: String, now: Date) async throws -> [CrisisRelayEnvelope] {
        let retained = envelopesBySubject[subjectId, default: []]
            .filter { $0.expiresAt > now }
        envelopesBySubject[subjectId] = retained
        return retained
    }

    func saveQueuedEnvelopes(_ envelopes: [CrisisRelayEnvelope], subjectId: String) async throws {
        envelopesBySubject[subjectId] = Array(envelopes.suffix(256))
    }

    func clear(subjectId: String) async throws {
        envelopesBySubject.removeValue(forKey: subjectId)
    }
}

extension MobileBootstrap {
    static func preview(historySeconds: Int) -> MobileBootstrap {
        let now = Date()
        let actor = AuthenticatedActor(
            subjectId: "preview-subject",
            username: "operator",
            displayName: "Operator",
            roles: ["mobile-user", "community-reporter"],
            picture: "data:image/png;base64,\(Self.previewAvatarPNGBase64)",
            email: "operator@example.cz"
        )
        let alerts = [
            CopAlert(
                alertId: "alert-source-degraded",
                type: .sourceDegraded,
                severity: .warning,
                status: .active,
                title: "Source degraded",
                detail: "SIM safety data has delayed updates.",
                objectId: nil,
                sourceSystemId: "sim.safety-data",
                observedAt: now.addingTimeInterval(-180),
                updatedAt: now.addingTimeInterval(-90),
                acknowledgedAt: nil,
                map: AlertMapArea(lat: 50.086, lon: 14.421, radiusKm: 1.2)
            ),
            CopAlert(
                alertId: "alert-proximity",
                type: .aoiEntry,
                severity: .critical,
                status: .active,
                title: "Proximity alert",
                detail: "Observed object entered the selected area.",
                objectId: "track-rescue-01",
                sourceSystemId: nil,
                observedAt: now.addingTimeInterval(-70),
                updatedAt: now.addingTimeInterval(-70),
                acknowledgedAt: nil,
                map: AlertMapArea(lat: 50.091, lon: 14.432, radiusKm: 0.7)
            )
        ]
        let objects = [
            ObservedObject(
                objectId: "track-rescue-01",
                label: "Rescue 01",
                objectType: "RESCUE_ASSET",
                affiliation: "FRIENDLY",
                position: GeoPoint(lat: 50.091, lon: 14.432, accuracyM: 12, source: "stream"),
                confidence: 0.92,
                updatedAt: now.addingTimeInterval(-20)
            ),
            ObservedObject(
                objectId: "report-fire-001",
                label: CSMLocalization.text("preview.map.smoke_forest", fallback: "Kouř u lesa"),
                objectType: "REPORT",
                affiliation: nil,
                position: GeoPoint(lat: 50.086, lon: 14.421, accuracyM: 8, source: "community"),
                confidence: 0.78,
                updatedAt: now.addingTimeInterval(-240)
            )
        ]
        let snapshot = MobileOfflineSnapshot(
            alerts: alerts,
            cachePolicy: MobileCachePolicy(
                apiResponses: "network-only",
                maxHistoryPointsPerObject: 120,
                maxHistorySeconds: historySeconds,
                mode: "read-only",
                offlineCacheTtlSeconds: 900,
                recommendedStorage: "encrypted-device-storage"
            ),
            healthStatus: "ok",
            objects: objects,
            serverTimestamp: now,
            snapshotId: "preview-\(Int(now.timeIntervalSince1970))",
            sourceHealth: [
                SourceHealthItem(sourceSystemId: "sim.safety-data", label: "Safety data", status: "degraded", updatedAt: now.addingTimeInterval(-90)),
                SourceHealthItem(sourceSystemId: "csm.messaging", label: "CSM Messaging", status: "online", updatedAt: now)
            ],
            sources: ["sim.safety-data", "cop.community", "csm.messaging"],
            streamHealthStatus: "LIVE",
            trackHistory: objects.map { object in
                TrackHistory(
                    objectId: object.objectId,
                    points: [
                        TrackHistoryPoint(lat: object.position.lat - 0.005, lon: object.position.lon - 0.004, observedAt: now.addingTimeInterval(-Double(historySeconds))),
                        TrackHistoryPoint(lat: object.position.lat - 0.002, lon: object.position.lon - 0.002, observedAt: now.addingTimeInterval(-90)),
                        TrackHistoryPoint(lat: object.position.lat, lon: object.position.lon, observedAt: now)
                    ]
                )
            }
        )
        return MobileBootstrap(
            actor: actor,
            auth: MobileAuthConfig(
                mode: "oidc",
                issuer: "https://auth.zeleznalady.cz/realms/cop",
                clientId: "csm-mobile",
                redirectUriScheme: "csm",
                scope: "openid profile offline_access"
            ),
            capabilities: MobileCapabilities(
                alertAcknowledgement: true,
                aoiAlerts: true,
                bootstrap: true,
                communityReportUploads: true,
                communityReports: true,
                deviceRegistration: true,
                offlineSnapshot: true,
                pushNotifications: false,
                serverUserProfile: true,
                sseStream: true,
                trackHistory: true
            ),
            endpoints: [
                "bootstrap": "/api/v1/mobile/bootstrap",
                "messagingStatus": "/api/v1/messaging/status",
                "messagingBootstrap": "/api/v1/messaging/bootstrap",
                "stream": "/api/v1/stream/cop/live"
            ],
            map: MobileMapConfig(
                attribution: "OpenStreetMap contributors",
                defaultCenter: [14.421, 50.086],
                defaultZoom: 12,
                glyphsTemplateUrl: "/fonts/{fontstack}/{range}.pbf",
                styleUrl: nil,
                tileTemplateUrl: "https://tiles.zeleznalady.cz/{z}/{x}/{y}.png"
            ),
            policy: MobileNativePolicy(
                minimumAppVersion: "0.1.0",
                offlineCacheTtlSeconds: 900,
                pushNotifications: "not_configured",
                requireBiometricUnlock: false,
                requireManagedDevice: false
            ),
            profile: UserProfile(
                alertRadiusKm: 1.0,
                preferredHistorySeconds: historySeconds,
                preferredLayerIds: ["user.community.reports", "public.safety.warnings"],
                updatedAt: now,
                alertPreferences: [:],
                preferences: UserDisplayPreferences(values: [
                    "operatorProfile": (try? CSMJSONValue.encodable(OperatorProfilePreferences(
                        avatarDataUrl: "data:image/png;base64,\(Self.previewAvatarPNGBase64)",
                        contactNote: "Dostupný pro koordinaci v terénu.",
                        displayName: "COP Operátor",
                        email: "operator@example.cz",
                        organization: "CSM",
                        phone: "+420 000 000 000",
                        publicContact: true,
                        role: "Koordinátor"
                    ))) ?? .null,
                    "safetyLayerIds": .array([
                        .string("user.community.reports"),
                        .string("public.safety.warnings")
                    ]),
                    "trackHistoryWindowSeconds": .number(Double(historySeconds)),
                    "workspaceSkin": .string("field")
                ])
            ),
            snapshot: snapshot,
            serverTimestamp: now
        )
    }

    var preferenceProfile: UserPreferenceProfile {
        UserPreferenceProfile(
            actor: actor,
            alertPreferences: profile.alertPreferences,
            preferences: profile.preferences,
            updatedAt: profile.updatedAt
        )
    }

    private static let previewAvatarPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAQAAAAAYLlVAAAAa0lEQVR42u3XsQnAIBAF0P//a9eCk5mQgSHCcs46JgZ01w7DMEwDYK3PZq9j2q2xvN6fc7MBgGrP8rUCAIAAAQIECBAgQIAAAQIECBAgQIAAAQIECBAgQIAAAQIECLjMx2m8wHo8B+heQAECAAAECBAgQIECAAAECBAgQIECAAAGCjwLM+QET5rQFxwAAAABJRU5ErkJggg=="
    static var previewAvatarDataUrl: String {
        "data:image/png;base64,\(previewAvatarPNGBase64)"
    }
}

private extension MapFeatureQueryResponse {
    static func preview(for request: MapFeatureQueryRequest) -> MapFeatureQueryResponse {
        let requestedLayers = Set(request.layerIds)
        let now = Date()
        let situationFeatures = requestedLayers.contains("public.mobile.network")
            ? [Self.mobileNetworkPreviewFeature(now: now)]
            : []
        let safetyFeatures = Self.previewSafetyFeatures(requestedLayers: requestedLayers, now: now)
        let communityFeatures = requestedLayers.contains("user.community.reports")
            ? [Self.communityReportPreviewFeature(now: now)]
            : []
        let featureCount = situationFeatures.count + safetyFeatures.count + communityFeatures.count

        return MapFeatureQueryResponse(
            contractVersion: "cop-map-query-v1",
            generatedAt: now,
            query: MapFeatureQueryEcho(
                bbox: request.bbox,
                layerIds: request.layerIds,
                limit: request.limit
            ),
            situation: situationFeatures.isEmpty ? nil : MapFeatureCollection(
                contractVersion: "cop-situation-source-v1",
                generatedAt: now,
                features: situationFeatures,
                summary: MapFeatureCollectionSummary(featureCount: situationFeatures.count, layerCount: 1, warningCount: 0)
            ),
            safety: safetyFeatures.isEmpty ? nil : MapFeatureCollection(
                contractVersion: "cop-safety-source-v1",
                generatedAt: now,
                features: safetyFeatures,
                summary: MapFeatureCollectionSummary(featureCount: safetyFeatures.count, layerCount: 1, warningCount: 0)
            ),
            flight: nil,
            community: communityFeatures.isEmpty ? nil : MapFeatureCollection(
                contractVersion: "cop-community-map-v1",
                generatedAt: now,
                features: communityFeatures,
                summary: MapFeatureCollectionSummary(featureCount: communityFeatures.count, layerCount: 1, warningCount: 0)
            ),
            missionArena: nil,
            tak: nil,
            summary: MapFeatureQuerySummary(
                featureCount: featureCount,
                layerCount: request.layerIds.count,
                warningCount: 0
            ),
            warnings: []
        )
    }

    static func mobileNetworkPreviewFeature(now: Date) -> MapFeature {
        MapFeature(
            id: "preview-mobile-network",
            type: "Feature",
            geometry: .polygon([[
                [14.39, 50.07],
                [14.46, 50.07],
                [14.46, 50.11],
                [14.39, 50.11],
                [14.39, 50.07]
            ]]),
            properties: MapFeatureProperties(
                featureId: "preview-mobile-network",
                layerId: "public.mobile.network",
                layer: "mobile_network",
                providerId: "sim.situation-data",
                providerLayerId: "mobile_network",
                sourceId: "mobile_network_model",
                category: "mobile_network",
                label: CSMLocalization.text("map.catalog.mobile_network.label", fallback: "Mobilní síť"),
                observedAt: now.addingTimeInterval(-180),
                stale: false,
                confidence: 0.74,
                severity: "info",
                metrics: [
                    "technology": .string("4G"),
                    "estimatedSignalDbm": .number(-92)
                ],
                legal: [
                    "attribution": .string("Preview COP")
                ]
            )
        )
    }

    static func previewSafetyFeatures(requestedLayers: Set<String>, now: Date) -> [MapFeature] {
        var features: [MapFeature] = []
        if requestedLayers.contains("public.safety.weather_alerts") {
            features.append(weatherAlertPreviewFeature(now: now))
        }
        if requestedLayers.contains("public.safety.warnings") {
            features.append(crisisWarningPreviewFeature(now: now))
        }
        if features.isEmpty,
           !requestedLayers.intersection(["public.safety.flood", "public.safety.fire"]).isEmpty {
            features.append(crisisWarningPreviewFeature(now: now))
        }
        return features
    }

    static func crisisWarningPreviewFeature(now: Date) -> MapFeature {
        MapFeature(
            id: "preview-crisis-warning",
            type: "Feature",
            geometry: .point([14.432, 50.091]),
            properties: MapFeatureProperties(
                featureId: "preview-crisis-warning",
                layerId: "public.safety.warnings",
                layer: "warnings",
                providerId: "sim.safety-data",
                providerLayerId: "warnings",
                sourceId: "hzs_incidents",
                category: "crisis_warning",
                label: CSMLocalization.text("preview.alert.proximity.title", fallback: "Aktivní výstraha"),
                sourceName: "HZS incident feed",
                observedAt: now.addingTimeInterval(-90),
                stale: false,
                confidence: 0.9,
                severity: "warning",
                status: "active",
                typeCode: "public_safety.incident",
                sourceSystem: "HZS",
                areaName: "Pilot area",
                basis: ["hzs_incidents", "warnings"]
            )
        )
    }

    static func weatherAlertPreviewFeature(now: Date) -> MapFeature {
        MapFeature(
            id: "preview-weather-alert",
            type: "Feature",
            geometry: .point([14.442, 50.101]),
            properties: MapFeatureProperties(
                featureId: "preview-weather-alert",
                layerId: "public.safety.weather_alerts",
                layer: "weather_alerts",
                providerId: "sim.safety-data",
                providerLayerId: "safety.weather_alerts",
                sourceId: "chmi_alerts",
                category: "weather_warning",
                label: CSMLocalization.text("map.catalog.safety_weather_alerts.label", fallback: "Meteorologická výstraha"),
                sourceName: "CHMI CAP weather warnings",
                observedAt: now.addingTimeInterval(-120),
                effectiveAt: now.addingTimeInterval(-60),
                expiresAt: now.addingTimeInterval(7_200),
                stale: false,
                confidence: 0.92,
                severity: "advisory",
                status: "active",
                recommendedAction: CSMLocalization.text("preview.alert.weather_action", fallback: "Sledujte vývoj počasí a zabezpečte volné předměty."),
                typeCode: "weather.wind.gust",
                sourceCode: "I.2",
                sourceSystem: "CHMI_CAP",
                hazardType: "wind",
                areaName: "Pilot area",
                basis: ["chmi_cap", "weather_alerts"],
                providerProperties: [
                    "notification": .object([
                        "eligible": .bool(true),
                        "reason": .string("official_warning")
                    ])
                ]
            )
        )
    }

    static func communityReportPreviewFeature(now: Date) -> MapFeature {
        MapFeature(
            id: "preview-community-report",
            type: "Feature",
            geometry: .point([14.421, 50.086]),
            properties: MapFeatureProperties(
                featureId: "preview-community-report",
                layerId: "user.community.reports",
                layer: "community",
                providerId: "cop.community",
                providerLayerId: "reports",
                sourceId: "cop.community",
                category: "community_report",
                label: CSMLocalization.text("preview.map.smoke_forest", fallback: "Kouř u lesa"),
                observedAt: now.addingTimeInterval(-240),
                stale: false,
                confidence: 0.78,
                severity: "warning"
            )
        )
    }
}
