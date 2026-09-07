import Foundation

enum ConnectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case online = "ONLINE"
    case degraded = "DEGRADED"
    case offline = "OFFLINE"

    var id: String { rawValue }
}

enum AlertSeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case info
    case warning
    case critical

    var id: String { rawValue }
}

enum AlertStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case acknowledged = "ACKNOWLEDGED"
}

enum CopAlertType: String, Codable, Sendable {
    case aoiEntry = "AOI_ENTRY"
    case lowConfidence = "LOW_CONFIDENCE"
    case sourceDegraded = "SOURCE_DEGRADED"
    case trackConflict = "TRACK_CONFLICT"
    case trackLost = "TRACK_LOST"
    case trackStale = "TRACK_STALE"

    var isDataQualityLifecycleSignal: Bool {
        switch self {
        case .lowConfidence, .sourceDegraded, .trackLost, .trackStale:
            true
        case .aoiEntry, .trackConflict:
            false
        }
    }
}

struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var accuracyM: Double?
    var source: String?
}

struct AlertMapArea: Codable, Equatable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var radiusKm: Double
}

enum OfflineMapPackStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case ready
    case stale
    case expired
    case unavailable

    var id: String { rawValue }
}

enum OfflineMapTileCacheStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case planned
    case partial
    case ready
    case expired
    case unavailable

    var id: String { rawValue }
}

struct OfflineMapPackRegion: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var label: String
    var center: GeoPoint
    var radiusKm: Double
    /// Bounding box in WGS84 order: west, south, east, north.
    var bbox: [Double]
    var reason: String
}

struct OfflineMapTileCoordinate: Codable, Identifiable, Equatable, Hashable, Sendable {
    var z: Int
    var x: Int
    var y: Int

    var id: String { "\(z)/\(x)/\(y)" }
}

struct OfflineMapTileRequest: Codable, Identifiable, Equatable, Hashable, Sendable {
    var coordinate: OfflineMapTileCoordinate
    var url: URL

    var id: String { coordinate.id }
}

struct OfflineMapTilePlan: Codable, Equatable, Hashable, Sendable {
    var packId: String
    var subjectId: String
    var generatedAt: Date
    var expiresAt: Date
    var minZoom: Int
    var maxZoom: Int
    var requests: [OfflineMapTileRequest]
}

struct OfflineMapTileCacheSummary: Codable, Equatable, Hashable, Sendable {
    var packId: String
    var subjectId: String
    var plannedTileCount: Int
    var cachedTileCount: Int
    var failedTileCount: Int
    var byteCount: Int
    var minZoom: Int
    var maxZoom: Int
    var updatedAt: Date
    var expiresAt: Date

    func status(now: Date = .now) -> OfflineMapTileCacheStatus {
        if now >= expiresAt { return .expired }
        guard plannedTileCount > 0 else { return .unavailable }
        if cachedTileCount >= plannedTileCount { return .ready }
        if cachedTileCount > 0 || failedTileCount > 0 { return .partial }
        return .planned
    }

    static func planned(from plan: OfflineMapTilePlan, updatedAt: Date = .now) -> OfflineMapTileCacheSummary {
        OfflineMapTileCacheSummary(
            packId: plan.packId,
            subjectId: plan.subjectId,
            plannedTileCount: plan.requests.count,
            cachedTileCount: 0,
            failedTileCount: 0,
            byteCount: 0,
            minZoom: plan.minZoom,
            maxZoom: plan.maxZoom,
            updatedAt: updatedAt,
            expiresAt: plan.expiresAt
        )
    }
}

struct OfflineMapPack: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var subjectId: String
    var title: String
    var sourceSnapshotId: String
    var generatedAt: Date
    var staleAt: Date
    var expiresAt: Date
    var attribution: String
    var styleURL: URL?
    var tileTemplateURL: String
    var storageMode: String
    var layerIds: [String]
    var regions: [OfflineMapPackRegion]
    /// Bounding box in WGS84 order: west, south, east, north.
    var bbox: [Double]
    var estimatedTileBudget: Int

    func status(now: Date = .now) -> OfflineMapPackStatus {
        guard !tileTemplateURL.isEmpty, !regions.isEmpty else { return .unavailable }
        if now >= expiresAt { return .expired }
        if now >= staleAt { return .stale }
        return .ready
    }
}

enum OfflineMapTilePlanner {
    static func plan(
        for pack: OfflineMapPack,
        minZoom: Int = 10,
        maxZoom: Int = 13,
        maxTiles: Int = 512,
        generatedAt: Date = .now
    ) -> OfflineMapTilePlan {
        let safeMinZoom = max(0, min(minZoom, maxZoom))
        let safeMaxZoom = min(18, max(maxZoom, safeMinZoom))
        var seen: Set<OfflineMapTileCoordinate> = []
        var requests: [OfflineMapTileRequest] = []

        for zoom in safeMinZoom...safeMaxZoom {
            for region in pack.regions {
                let coordinates = tileCoordinates(for: region.bbox, zoom: zoom)
                for coordinate in coordinates where !seen.contains(coordinate) {
                    guard requests.count < maxTiles else {
                        return OfflineMapTilePlan(
                            packId: pack.id,
                            subjectId: pack.subjectId,
                            generatedAt: generatedAt,
                            expiresAt: pack.expiresAt,
                            minZoom: safeMinZoom,
                            maxZoom: zoom,
                            requests: requests
                        )
                    }
                    guard let url = tileURL(template: pack.tileTemplateURL, coordinate: coordinate) else {
                        continue
                    }
                    seen.insert(coordinate)
                    requests.append(OfflineMapTileRequest(coordinate: coordinate, url: url))
                }
            }
        }

        return OfflineMapTilePlan(
            packId: pack.id,
            subjectId: pack.subjectId,
            generatedAt: generatedAt,
            expiresAt: pack.expiresAt,
            minZoom: safeMinZoom,
            maxZoom: safeMaxZoom,
            requests: requests
        )
    }

    private static func tileCoordinates(for bbox: [Double], zoom: Int) -> [OfflineMapTileCoordinate] {
        guard bbox.count == 4 else { return [] }
        let west = bbox[0]
        let south = bbox[1]
        let east = bbox[2]
        let north = bbox[3]
        let minTile = tileCoordinate(lat: north, lon: west, zoom: zoom)
        let maxTile = tileCoordinate(lat: south, lon: east, zoom: zoom)
        let xRange = min(minTile.x, maxTile.x)...max(minTile.x, maxTile.x)
        let yRange = min(minTile.y, maxTile.y)...max(minTile.y, maxTile.y)
        return xRange.flatMap { x in
            yRange.map { y in OfflineMapTileCoordinate(z: zoom, x: x, y: y) }
        }
    }

    private static func tileCoordinate(lat: Double, lon: Double, zoom: Int) -> OfflineMapTileCoordinate {
        let lat = min(85.05112878, max(-85.05112878, lat))
        let lon = min(180.0, max(-180.0, lon))
        let n = pow(2.0, Double(zoom))
        let x = Int(((lon + 180.0) / 360.0 * n).rounded(.down))
        let latRad = lat * .pi / 180.0
        let y = Int(((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * n).rounded(.down))
        let maxTile = max(0, Int(n) - 1)
        return OfflineMapTileCoordinate(
            z: zoom,
            x: min(maxTile, max(0, x)),
            y: min(maxTile, max(0, y))
        )
    }

    private static func tileURL(template: String, coordinate: OfflineMapTileCoordinate) -> URL? {
        let value = template
            .replacingOccurrences(of: "{z}", with: "\(coordinate.z)")
            .replacingOccurrences(of: "{x}", with: "\(coordinate.x)")
            .replacingOccurrences(of: "{y}", with: "\(coordinate.y)")
        return URL(string: value)
    }
}

enum OfflineMapPackPlanner {
    static func recommendedPack(for bootstrap: MobileBootstrap, generatedAt: Date = .now) -> OfflineMapPack {
        let snapshot = bootstrap.snapshot
        let ttlSeconds = max(
            300,
            bootstrap.policy.offlineCacheTtlSeconds > 0
                ? bootstrap.policy.offlineCacheTtlSeconds
                : snapshot.cachePolicy.offlineCacheTtlSeconds
        )
        let staleAt = snapshot.serverTimestamp.addingTimeInterval(Double(ttlSeconds) * 0.5)
        let expiresAt = snapshot.serverTimestamp.addingTimeInterval(Double(ttlSeconds))
        let regions = recommendedRegions(for: bootstrap)
        let bbox = unionBBox(regions.map(\.bbox))
        let layerIds = bootstrap.profile.preferredLayerIds.isEmpty
            ? ["cop.alerts", "cop.objects", "cop.community.reports"]
            : bootstrap.profile.preferredLayerIds

        return OfflineMapPack(
            id: "offline-map:\(bootstrap.actor.subjectId):\(snapshot.snapshotId)",
            subjectId: bootstrap.actor.subjectId,
            title: "COP crisis context",
            sourceSnapshotId: snapshot.snapshotId,
            generatedAt: generatedAt,
            staleAt: staleAt,
            expiresAt: expiresAt,
            attribution: bootstrap.map.attribution,
            styleURL: bootstrap.map.styleUrl.flatMap(URL.init(string:)),
            tileTemplateURL: bootstrap.map.tileTemplateUrl,
            storageMode: "encrypted-manifest",
            layerIds: layerIds,
            regions: regions,
            bbox: bbox,
            estimatedTileBudget: estimatedTileBudget(for: regions)
        )
    }

    private static func recommendedRegions(for bootstrap: MobileBootstrap) -> [OfflineMapPackRegion] {
        let alertRegions = bootstrap.snapshot.alerts
            .filter { $0.status == .active }
            .compactMap(alertRegion)
        let objectRegion = observedObjectRegion(for: bootstrap.snapshot.objects)
        let defaultRegion = defaultCenterRegion(for: bootstrap)

        var regions = alertRegions
        if let objectRegion {
            regions.append(objectRegion)
        }
        if regions.isEmpty {
            regions.append(defaultRegion)
        }
        return Array(regions.prefix(8))
    }

    private static func alertRegion(_ alert: CopAlert) -> OfflineMapPackRegion? {
        guard let map = alert.map else { return nil }
        let center = GeoPoint(lat: map.lat, lon: map.lon, accuracyM: nil, source: "cop.alert")
        let radiusKm = max(0.5, map.radiusKm)
        return OfflineMapPackRegion(
            id: "alert:\(alert.alertId)",
            label: alert.title,
            center: center,
            radiusKm: radiusKm,
            bbox: bbox(center: center, radiusKm: radiusKm),
            reason: alert.severity == .critical ? "critical_alert" : "active_alert"
        )
    }

    private static func observedObjectRegion(for objects: [ObservedObject]) -> OfflineMapPackRegion? {
        guard !objects.isEmpty else { return nil }
        let points = objects.map(\.position)
        let bounds = unionBBox(points.map { bbox(center: $0, radiusKm: 0.6) })
        let center = centerPoint(for: bounds, source: "cop.snapshot.objects")
        return OfflineMapPackRegion(
            id: "snapshot:objects",
            label: "Observed objects",
            center: center,
            radiusKm: max(0.8, radiusKm(for: bounds)),
            bbox: bounds,
            reason: "policy_filtered_objects"
        )
    }

    private static func defaultCenterRegion(for bootstrap: MobileBootstrap) -> OfflineMapPackRegion {
        let center = defaultCenter(from: bootstrap.map)
        let radiusKm = max(1.0, bootstrap.profile.alertRadiusKm)
        return OfflineMapPackRegion(
            id: "default:center",
            label: "Default map context",
            center: center,
            radiusKm: radiusKm,
            bbox: bbox(center: center, radiusKm: radiusKm),
            reason: "default_context"
        )
    }

    private static func defaultCenter(from map: MobileMapConfig) -> GeoPoint {
        guard map.defaultCenter.count >= 2 else {
            return GeoPoint(lat: 50.086, lon: 14.421, accuracyM: nil, source: "default")
        }
        return GeoPoint(lat: map.defaultCenter[1], lon: map.defaultCenter[0], accuracyM: nil, source: "cop.map.defaultCenter")
    }

    private static func bbox(center: GeoPoint, radiusKm: Double) -> [Double] {
        let safeRadius = max(0.1, radiusKm)
        let latDelta = safeRadius / 111.0
        let lonScale = max(0.25, cos(center.lat * .pi / 180.0))
        let lonDelta = safeRadius / (111.0 * lonScale)
        return [
            clampedLongitude(center.lon - lonDelta),
            clampedLatitude(center.lat - latDelta),
            clampedLongitude(center.lon + lonDelta),
            clampedLatitude(center.lat + latDelta)
        ]
    }

    private static func unionBBox(_ boxes: [[Double]]) -> [Double] {
        let validBoxes = boxes.filter { $0.count == 4 }
        guard let first = validBoxes.first else { return [] }
        return validBoxes.dropFirst().reduce(first) { current, next in
            [
                min(current[0], next[0]),
                min(current[1], next[1]),
                max(current[2], next[2]),
                max(current[3], next[3])
            ]
        }
    }

    private static func centerPoint(for bbox: [Double], source: String) -> GeoPoint {
        guard bbox.count == 4 else {
            return GeoPoint(lat: 50.086, lon: 14.421, accuracyM: nil, source: source)
        }
        return GeoPoint(
            lat: (bbox[1] + bbox[3]) / 2.0,
            lon: (bbox[0] + bbox[2]) / 2.0,
            accuracyM: nil,
            source: source
        )
    }

    private static func radiusKm(for bbox: [Double]) -> Double {
        guard bbox.count == 4 else { return 1.0 }
        let latKm = abs(bbox[3] - bbox[1]) * 111.0
        let lonKm = abs(bbox[2] - bbox[0]) * 111.0
        return max(latKm, lonKm) / 2.0
    }

    private static func estimatedTileBudget(for regions: [OfflineMapPackRegion]) -> Int {
        regions.reduce(0) { result, region in
            let areaWeight = max(16.0, min(512.0, region.radiusKm * region.radiusKm * 24.0))
            return result + Int(areaWeight.rounded(.up))
        }
    }

    private static func clampedLatitude(_ value: Double) -> Double {
        min(85.0, max(-85.0, value))
    }

    private static func clampedLongitude(_ value: Double) -> Double {
        min(180.0, max(-180.0, value))
    }
}

struct CopAlert: Codable, Identifiable, Equatable, Hashable, Sendable {
    var alertId: String
    var type: CopAlertType
    var severity: AlertSeverity
    var status: AlertStatus
    var title: String
    var detail: String
    var objectId: String?
    var sourceSystemId: String?
    var observedAt: Date
    var updatedAt: Date
    var acknowledgedAt: Date?
    var map: AlertMapArea?

    var id: String { alertId }

    var isDataQualityLifecycleSignal: Bool {
        type.isDataQualityLifecycleSignal
    }

    var isPublicAlertSurfaceEligible: Bool {
        !isDataQualityLifecycleSignal
    }
}

enum ConversationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case group

    var id: String { rawValue }
}

enum ConversationKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct
    case group
    case personalAI = "personal_ai"

    var id: String { rawValue }
}

/// One COP person is represented by an OIDC subject in conversation metadata
/// and by a Matrix user id in the encrypted room. Presentation code must not
/// treat those transport-specific spellings as separate people.
enum ConversationIdentity {
    static func canonicalKey(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return "" }

        guard normalized.hasPrefix("@") else { return normalized }
        normalized.removeFirst()
        if let serverSeparator = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<serverSeparator])
        }
        if normalized.hasPrefix("cop_") {
            normalized.removeFirst(4)
        }
        return normalized
    }

    static func variants(_ value: String) -> Set<String> {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonical = canonicalKey(value)
        return Set([normalized, canonical].filter { !$0.isEmpty })
    }

    static func matches(_ left: String, _ right: String) -> Bool {
        let leftKey = canonicalKey(left)
        return !leftKey.isEmpty && leftKey == canonicalKey(right)
    }

    static func preferredPersistentId(_ left: String, _ right: String) -> String {
        let leftIsMatrix = left.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
        let rightIsMatrix = right.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
        if leftIsMatrix != rightIsMatrix {
            return leftIsMatrix ? right : left
        }
        return left
    }
}

struct ConversationMember: Codable, Identifiable, Equatable, Hashable, Sendable {
    var userId: String
    var displayName: String?
    var role: String?
    var avatarDataUrl: String?
    var avatarUrl: String?

    var id: String { userId }

    init(
        userId: String,
        displayName: String? = nil,
        role: String? = nil,
        avatarDataUrl: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.avatarDataUrl = avatarDataUrl
        self.avatarUrl = avatarUrl
    }
}

struct ConversationRecipient: Identifiable, Equatable, Hashable, Sendable {
    var userId: String
    var displayName: String?
    var role: String?
    var handle: String?
    var avatarDataUrl: String?
    var avatarUrl: String?
    var sourceConversationTitle: String?

    var id: String { userId }

    var title: String {
        let normalizedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedName?.isEmpty == false ? normalizedName! : userId
    }

    var subtitle: String {
        var parts: [String] = []
        if let handle = handle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !handle.isEmpty,
           handle != title {
            parts.append(handle)
        } else if shouldShowUserIdInSubtitle {
            parts.append(userId)
        }
        if let sourceConversationTitle, !sourceConversationTitle.isEmpty {
            parts.append(sourceConversationTitle)
        }
        return parts.joined(separator: " • ")
    }

    var draft: ConversationMemberDraft {
        ConversationMemberDraft(userId: userId, displayName: displayName, role: role)
    }

    private var shouldShowUserIdInSubtitle: Bool {
        let normalizedId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != normalizedId else { return false }
        if normalizedId.contains("@") || normalizedId.contains(".") || normalizedId.contains(":") {
            return true
        }
        guard normalizedId.count >= 12 else { return true }
        let opaqueCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return !normalizedId.unicodeScalars.allSatisfy { opaqueCharacters.contains($0) }
    }
}

struct MessagingMapLink: Codable, Identifiable, Equatable, Hashable, Sendable {
    var targetId: String
    var layerId: String?
    var label: String?
    var bbox: [Double]?

    var id: String { targetId }
}

struct ConversationMemberDraft: Codable, Identifiable, Equatable, Hashable, Sendable {
    var userId: String
    var displayName: String?
    var role: String?

    var id: String { userId }

    init(userId: String, displayName: String? = nil, role: String? = nil) {
        self.userId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = normalizedDisplayName?.isEmpty == false ? normalizedDisplayName : nil
        self.role = role
    }
}

struct ConversationDraft: Codable, Equatable, Hashable, Sendable {
    var type: ConversationType
    var conversationKind: ConversationKind
    var title: String
    var members: [ConversationMemberDraft]
    var mapLinks: [MessagingMapLink]
    var metadata: [String: String]

    init(
        type: ConversationType,
        conversationKind: ConversationKind? = nil,
        title: String,
        members: [ConversationMemberDraft] = [],
        mapLinks: [MessagingMapLink] = [],
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.conversationKind = conversationKind ?? (type == .direct ? .direct : .group)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.members = Self.uniqueMembers(members)
        self.mapLinks = mapLinks
        self.metadata = metadata
    }

    var isValid: Bool {
        !title.isEmpty && (type == .group || !members.isEmpty)
    }

    private static func uniqueMembers(_ members: [ConversationMemberDraft]) -> [ConversationMemberDraft] {
        var seen = Set<String>()
        return members.filter { member in
            guard !member.userId.isEmpty, !seen.contains(member.userId) else { return false }
            seen.insert(member.userId)
            return true
        }
    }
}

struct Conversation: Codable, Identifiable, Equatable, Hashable, Sendable {
    var conversationId: String
    var conversationKind: ConversationKind
    var canonicalKey: String?
    var title: String
    var type: ConversationType
    var status: String?
    var encrypted: Bool
    var e2eeRequired: Bool
    var matrix: MessagingMatrixRoom?
    var memberCount: Int
    var mapLinkCount: Int
    var members: [ConversationMember]
    var mapLinks: [MessagingMapLink]
    var unreadCount: Int
    var lastActivityPreview: String?
    var lastActivityAt: Date?
    var metadata: [String: String]
    var conversationAvatarDataUrl: String?
    var conversationAvatarUrl: String?
    var updatedAt: Date?

    var id: String { conversationId }

    var hasUnreadMessages: Bool {
        unreadCount > 0
    }

    var avatarDataUrl: String? {
        conversationAvatarDataUrl ??
            metadata["avatarDataUrl"] ??
            metadata["avatarDataURL"] ??
            metadata["pictureDataUrl"]
    }

    var avatarUrl: String? {
        conversationAvatarUrl ??
            metadata["avatarUrl"] ??
            metadata["avatarURL"] ??
            metadata["pictureUrl"]
    }

    var linkedCommunityGroupId: String? {
        guard metadata["source"] == "cop.community" else { return nil }
        let externalId = metadata["externalId"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return externalId?.isEmpty == false ? externalId : nil
    }

    var notificationGroupSubscriptionId: String? {
        guard type == .group else { return nil }
        if let linkedCommunityGroupId,
           let normalized = CSMNotificationSubscriptions.normalizedIdentifier(linkedCommunityGroupId) {
            return normalized
        }
        return CSMNotificationSubscriptions.normalizedIdentifier(conversationId)
    }

    var activeMatrixRoomId: String? {
        let candidates = [
            matrix?.roomId,
            metadata["matrixRoomId"],
            metadata["roomId"],
            conversationId
        ]
        return candidates.compactMap { candidate -> String? in
            guard let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  normalized.hasPrefix("!"),
                  normalized.contains(":"),
                  normalized.count <= 512 else {
                return nil
            }
            return normalized
        }.first
    }

    var isAIAssistantConversation: Bool {
        conversationKind == .personalAI
    }

    enum CodingKeys: String, CodingKey {
        case conversationId
        case conversationKind
        case canonicalKey
        case title
        case type
        case status
        case encrypted
        case e2eeRequired
        case matrix
        case memberCount
        case mapLinkCount
        case members
        case mapLinks
        case unreadCount
        case lastActivityPreview
        case lastActivityAt
        case metadata
        case avatarDataUrl
        case avatarUrl
        case updatedAt
    }

    init(
        conversationId: String,
        conversationKind: ConversationKind? = nil,
        canonicalKey: String? = nil,
        title: String,
        type: ConversationType,
        status: String?,
        encrypted: Bool,
        e2eeRequired: Bool,
        matrix: MessagingMatrixRoom? = nil,
        memberCount: Int,
        mapLinkCount: Int,
        members: [ConversationMember],
        mapLinks: [MessagingMapLink],
        metadata: [String: String] = [:],
        conversationAvatarDataUrl: String? = nil,
        conversationAvatarUrl: String? = nil,
        unreadCount: Int = 0,
        lastActivityPreview: String? = nil,
        lastActivityAt: Date? = nil,
        updatedAt: Date?
    ) {
        self.conversationId = conversationId
        self.conversationKind = conversationKind ?? (type == .direct ? .direct : .group)
        self.canonicalKey = canonicalKey
        self.title = title
        self.type = type
        self.status = status
        self.encrypted = encrypted
        self.e2eeRequired = e2eeRequired
        self.matrix = matrix
        self.memberCount = memberCount
        self.mapLinkCount = mapLinkCount
        self.members = members
        self.mapLinks = mapLinks
        self.unreadCount = max(0, unreadCount)
        self.lastActivityPreview = lastActivityPreview
        self.lastActivityAt = lastActivityAt
        self.metadata = metadata
        self.conversationAvatarDataUrl = conversationAvatarDataUrl
        self.conversationAvatarUrl = conversationAvatarUrl
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decodeIfPresent(ConversationType.self, forKey: .type) ?? .group
        conversationKind = try container.decodeIfPresent(ConversationKind.self, forKey: .conversationKind) ??
            (type == .direct ? .direct : .group)
        canonicalKey = try container.decodeIfPresent(String.self, forKey: .canonicalKey)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        encrypted = try container.decodeIfPresent(Bool.self, forKey: .encrypted) ?? true
        e2eeRequired = try container.decodeIfPresent(Bool.self, forKey: .e2eeRequired) ?? true
        matrix = try container.decodeIfPresent(MessagingMatrixRoom.self, forKey: .matrix)
        members = try container.decodeIfPresent([ConversationMember].self, forKey: .members) ?? []
        memberCount = try container.decodeIfPresent(Int.self, forKey: .memberCount) ?? members.count
        mapLinks = try container.decodeIfPresent([MessagingMapLink].self, forKey: .mapLinks) ?? []
        mapLinkCount = try container.decodeIfPresent(Int.self, forKey: .mapLinkCount) ?? mapLinks.count
        unreadCount = max(0, try container.decodeIfPresent(Int.self, forKey: .unreadCount) ?? 0)
        lastActivityPreview = try container.decodeIfPresent(String.self, forKey: .lastActivityPreview)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        metadata = (try? container.decode([String: String].self, forKey: .metadata)) ?? [:]
        conversationAvatarDataUrl = try container.decodeIfPresent(String.self, forKey: .avatarDataUrl)
        conversationAvatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(conversationKind, forKey: .conversationKind)
        try container.encodeIfPresent(canonicalKey, forKey: .canonicalKey)
        try container.encode(title, forKey: .title)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encode(encrypted, forKey: .encrypted)
        try container.encode(e2eeRequired, forKey: .e2eeRequired)
        try container.encodeIfPresent(matrix, forKey: .matrix)
        try container.encode(memberCount, forKey: .memberCount)
        try container.encode(mapLinkCount, forKey: .mapLinkCount)
        try container.encode(members, forKey: .members)
        try container.encode(mapLinks, forKey: .mapLinks)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(lastActivityPreview, forKey: .lastActivityPreview)
        try container.encodeIfPresent(lastActivityAt, forKey: .lastActivityAt)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeIfPresent(conversationAvatarDataUrl, forKey: .avatarDataUrl)
        try container.encodeIfPresent(conversationAvatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

struct MessagingMatrixRoom: Codable, Equatable, Hashable, Sendable {
    var roomId: String?
    var state: String?
    var encrypted: Bool?
    var e2eeAlgorithm: String?
    var homeserverBaseUrl: URL?
    var serverName: String?
    var boundAt: Date?
    var boundBy: String?

    init(
        roomId: String? = nil,
        state: String? = nil,
        encrypted: Bool? = nil,
        e2eeAlgorithm: String? = nil,
        homeserverBaseUrl: URL? = nil,
        serverName: String? = nil,
        boundAt: Date? = nil,
        boundBy: String? = nil
    ) {
        self.roomId = roomId
        self.state = state
        self.encrypted = encrypted
        self.e2eeAlgorithm = e2eeAlgorithm
        self.homeserverBaseUrl = homeserverBaseUrl
        self.serverName = serverName
        self.boundAt = boundAt
        self.boundBy = boundBy
    }
}

enum MessageDeliveryState: String, Codable, Sendable {
    case pending
    case sent
    case delivered
    case read
    case failed
}

enum MessageAttachmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case image
    case video
    case document
    case voiceNote
    case sticker
    case location
    case safetyStatus

    var id: String { rawValue }
}

enum CrisisQuickStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case safe
    case needsHelp
    case enRoute
    case onScene

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safe:
            return CSMLocalization.text("quick.status.safe", fallback: "Jsem v pořádku")
        case .needsHelp:
            return CSMLocalization.text("quick.status.help", fallback: "Potřebuji pomoc")
        case .enRoute:
            return CSMLocalization.text("quick.status.enroute", fallback: "Na cestě")
        case .onScene:
            return CSMLocalization.text("quick.status.onsite", fallback: "Na místě")
        }
    }

    var systemImage: String {
        switch self {
        case .safe:
            return "checkmark.shield.fill"
        case .needsHelp:
            return "exclamationmark.triangle.fill"
        case .enRoute:
            return "figure.walk.motion"
        case .onScene:
            return "mappin.and.ellipse"
        }
    }

    func messageBody(source: String? = nil) -> String {
        let sourcePrefix = source
            .map { "\($0): " } ?? CSMLocalization.text("quick.status.prefix", fallback: "Rychlý status: ")
        switch self {
        case .safe:
            return CSMLocalization.text("quick.status.safe.body", fallback: "%@jsem v pořádku.", sourcePrefix)
        case .needsHelp:
            return CSMLocalization.text("quick.status.help.body", fallback: "%@potřebuji pomoc.", sourcePrefix)
        case .enRoute:
            return CSMLocalization.text("quick.status.enroute.body", fallback: "%@jsem na cestě.", sourcePrefix)
        case .onScene:
            return CSMLocalization.text("quick.status.onsite.body", fallback: "%@jsem na místě.", sourcePrefix)
        }
    }

    func messageAttachment(localOnly: Bool = true) -> MessageAttachment {
        MessageAttachment(
            kind: .safetyStatus,
            title: label,
            localOnly: localOnly
        )
    }
}

struct MessageAttachment: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var kind: MessageAttachmentKind
    var title: String
    var mimeType: String?
    var byteCount: Int?
    var durationSeconds: Double?
    var location: GeoPoint?
    var liveLocationShare: LiveLocationShareMetadata?
    var payloadData: Data?
    var localFileURL: URL?
    var createdAt: Date
    var localOnly: Bool

    init(
        id: String = UUID().uuidString,
        kind: MessageAttachmentKind,
        title: String,
        mimeType: String? = nil,
        byteCount: Int? = nil,
        durationSeconds: Double? = nil,
        location: GeoPoint? = nil,
        liveLocationShare: LiveLocationShareMetadata? = nil,
        payloadData: Data? = nil,
        localFileURL: URL? = nil,
        createdAt: Date = .now,
        localOnly: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.mimeType = mimeType
        self.byteCount = byteCount ?? payloadData?.count
        self.durationSeconds = durationSeconds
        self.location = location
        self.liveLocationShare = liveLocationShare
        self.payloadData = payloadData
        self.localFileURL = localFileURL
        self.createdAt = createdAt
        self.localOnly = localOnly
    }
}

struct LiveLocationShareMetadata: Codable, Equatable, Hashable, Sendable {
    var isLive: Bool
    var startedAt: Date
    var expiresAt: Date
    var updatedAt: Date?

    var durationSeconds: TimeInterval {
        max(0, expiresAt.timeIntervalSince(startedAt))
    }
}

struct ActiveLiveLocationShare: Equatable, Sendable {
    var conversationId: String
    var startedAt: Date
    var expiresAt: Date

    var isActive: Bool {
        expiresAt > .now
    }
}

struct MessageReplyReference: Codable, Equatable, Hashable, Sendable {
    var messageId: String
    var senderDisplayName: String
    var bodyPreview: String

    init(messageId: String, senderDisplayName: String, bodyPreview: String) {
        self.messageId = messageId
        self.senderDisplayName = senderDisplayName
        self.bodyPreview = String(bodyPreview.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
    }
}

struct MessageReaction: Codable, Identifiable, Equatable, Hashable, Sendable {
    var emoji: String
    var count: Int
    var reactedByMe: Bool
    var ownEventId: String?

    var id: String { emoji }

    init(emoji: String, count: Int = 1, reactedByMe: Bool = false, ownEventId: String? = nil) {
        self.emoji = String(emoji.prefix(8))
        self.count = max(0, count)
        self.reactedByMe = reactedByMe
        self.ownEventId = ownEventId
    }
}

struct OutgoingMessageDraft: Codable, Equatable, Hashable, Sendable {
    var body: String
    var attachments: [MessageAttachment]
    var replyTo: MessageReplyReference?

    init(
        body: String,
        attachments: [MessageAttachment] = [],
        replyTo: MessageReplyReference? = nil
    ) {
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        self.attachments = attachments
        self.replyTo = replyTo
    }

    var isEmpty: Bool {
        body.isEmpty && attachments.isEmpty
    }
}

enum MessageAttachmentPolicy {
    static let maxAttachmentCount = 8
    static let maxSingleAttachmentBytes = 20 * 1_024 * 1_024
    static let maxTotalAttachmentBytes = 30 * 1_024 * 1_024

    static func validationError(for draft: OutgoingMessageDraft) -> String? {
        guard draft.attachments.count <= maxAttachmentCount else {
            return CSMLocalization.text("message.validation.too_many_attachments", fallback: "Zpráva má příliš mnoho příloh.")
        }
        let byteCounts = draft.attachments.map { $0.byteCount ?? $0.payloadData?.count ?? 0 }
        guard byteCounts.allSatisfy({ $0 <= maxSingleAttachmentBytes }) else {
            return CSMLocalization.text(
                "message.validation.attachment_too_large",
                fallback: "Příloha je příliš velká pro bezpečné odeslání z telefonu."
            )
        }
        guard byteCounts.reduce(0, +) <= maxTotalAttachmentBytes else {
            return CSMLocalization.text("message.validation.draft_too_large", fallback: "Přílohy překročily limit jedné zprávy.")
        }
        return nil
    }
}

struct ChatMessage: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var roomId: String
    var senderId: String
    var senderDisplayName: String
    var senderAvatarDataUrl: String?
    var senderAvatarUrl: String?
    var body: String
    var attachments: [MessageAttachment]
    var replyTo: MessageReplyReference?
    var reactions: [MessageReaction]
    var isPinned: Bool
    var isDeleted: Bool
    var sentAt: Date
    var deliveryState: MessageDeliveryState
    var isOwnMessage: Bool

    init(
        id: String,
        roomId: String,
        senderId: String,
        senderDisplayName: String,
        senderAvatarDataUrl: String? = nil,
        senderAvatarUrl: String? = nil,
        body: String,
        attachments: [MessageAttachment] = [],
        replyTo: MessageReplyReference? = nil,
        reactions: [MessageReaction] = [],
        isPinned: Bool = false,
        isDeleted: Bool = false,
        sentAt: Date,
        deliveryState: MessageDeliveryState,
        isOwnMessage: Bool
    ) {
        self.id = id
        self.roomId = roomId
        self.senderId = senderId
        self.senderDisplayName = senderDisplayName
        self.senderAvatarDataUrl = senderAvatarDataUrl
        self.senderAvatarUrl = senderAvatarUrl
        self.body = body
        self.attachments = attachments
        self.replyTo = replyTo
        self.reactions = reactions
        self.isPinned = isPinned
        self.isDeleted = isDeleted
        self.sentAt = sentAt
        self.deliveryState = deliveryState
        self.isOwnMessage = isOwnMessage
    }

    var replyReference: MessageReplyReference {
        MessageReplyReference(
            messageId: id,
            senderDisplayName: senderDisplayName,
            bodyPreview: replyPreview
        )
    }

    private var replyPreview: String {
        if isDeleted {
            return "Smazana zprava"
        }
        if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body
        }
        if let attachment = attachments.first {
            return attachment.title
        }
        return "Zprava"
    }

    func applyingReactionToggle(_ emoji: String, ownEventId: String? = nil) -> ChatMessage {
        let key = String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        guard !key.isEmpty else { return self }

        var updated = self
        if let reactionIndex = updated.reactions.firstIndex(where: { $0.emoji == key }) {
            var reaction = updated.reactions[reactionIndex]
            if reaction.reactedByMe {
                reaction.reactedByMe = false
                reaction.ownEventId = nil
                reaction.count = max(0, reaction.count - 1)
            } else {
                reaction.reactedByMe = true
                reaction.ownEventId = ownEventId
                reaction.count += 1
            }

            if reaction.count == 0 {
                updated.reactions.remove(at: reactionIndex)
            } else {
                updated.reactions[reactionIndex] = reaction
            }
        } else {
            updated.reactions.append(MessageReaction(emoji: key, count: 1, reactedByMe: true, ownEventId: ownEventId))
        }
        return updated
    }

    func markedDeleted() -> ChatMessage {
        var updated = self
        updated.body = ""
        updated.attachments = []
        updated.replyTo = nil
        updated.reactions = []
        updated.isPinned = false
        updated.isDeleted = true
        updated.deliveryState = deliveryState == .pending ? .failed : deliveryState
        return updated
    }

    func settingPinned(_ pinned: Bool) -> ChatMessage {
        var updated = self
        updated.isPinned = pinned
        return updated
    }

    enum CodingKeys: String, CodingKey {
        case id
        case roomId
        case senderId
        case senderDisplayName
        case senderAvatarDataUrl
        case senderAvatarUrl
        case body
        case attachments
        case replyTo
        case reactions
        case isPinned
        case isDeleted
        case sentAt
        case deliveryState
        case isOwnMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        roomId = try container.decode(String.self, forKey: .roomId)
        senderId = try container.decode(String.self, forKey: .senderId)
        senderDisplayName = try container.decode(String.self, forKey: .senderDisplayName)
        senderAvatarDataUrl = try container.decodeIfPresent(String.self, forKey: .senderAvatarDataUrl)
        senderAvatarUrl = try container.decodeIfPresent(String.self, forKey: .senderAvatarUrl)
        body = try container.decode(String.self, forKey: .body)
        attachments = try container.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        replyTo = try container.decodeIfPresent(MessageReplyReference.self, forKey: .replyTo)
        reactions = try container.decodeIfPresent([MessageReaction].self, forKey: .reactions) ?? []
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        sentAt = try container.decode(Date.self, forKey: .sentAt)
        deliveryState = try container.decode(MessageDeliveryState.self, forKey: .deliveryState)
        isOwnMessage = try container.decode(Bool.self, forKey: .isOwnMessage)
    }
}

extension ChatMessage {
    var isAIAgentFallbackResponse: Bool {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
        return normalized == "cop ai agent" || normalized.hasPrefix("cop ai agent\n")
    }

    var presentationIsOwnMessage: Bool {
        isOwnMessage && !isAIAgentFallbackResponse
    }

    var presentationSenderId: String {
        isAIAgentFallbackResponse ? "cop.ai.agent" : senderId
    }

    var presentationSenderDisplayName: String {
        isAIAgentFallbackResponse ? "COP AI Assistant" : senderDisplayName
    }

    var presentationBody: String {
        guard isAIAgentFallbackResponse else { return body }
        var lines = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard !lines.isEmpty else { return body }
        lines.removeFirst()

        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Dotaz:") == true {
            if let separator = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                lines.removeSubrange(lines.startIndex ... separator)
            } else {
                lines.removeFirst()
            }
        }
        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Matrix Rust can briefly expose the same own send first under its local
    /// transaction id and then under the server event id. Reconcile the pair
    /// one-to-one so the encrypted history and SwiftUI timeline never retain
    /// both bubbles, while still preserving repeated intentional messages.
    static func removingSupersededLocalEchoes(from messages: [ChatMessage]) -> [ChatMessage] {
        // The immediate send result and the live Matrix timeline can race and
        // both publish the same server event. Collapse identical event ids
        // first, keeping the latest/richest snapshot in the original position.
        var uniqueMessages: [ChatMessage] = []
        var indexById: [String: Int] = [:]
        for message in messages {
            if let existingIndex = indexById[message.id] {
                uniqueMessages[existingIndex] = message
            } else {
                indexById[message.id] = uniqueMessages.count
                uniqueMessages.append(message)
            }
        }

        let confirmedIndices = uniqueMessages.indices.filter { index in
            uniqueMessages[index].isOwnMessage && uniqueMessages[index].id.hasPrefix("$")
        }
        var availableLocalIndices = Set(uniqueMessages.indices.filter { index in
            uniqueMessages[index].isOwnMessage && !uniqueMessages[index].id.hasPrefix("$")
        })
        var removedLocalIndices: Set<Int> = []

        for confirmedIndex in confirmedIndices {
            let confirmed = uniqueMessages[confirmedIndex]
            let bestLocalIndex = availableLocalIndices
                .filter { localIndex in
                    localEcho(uniqueMessages[localIndex], matches: confirmed)
                }
                .min { leftIndex, rightIndex in
                    abs(uniqueMessages[leftIndex].sentAt.timeIntervalSince(confirmed.sentAt)) <
                        abs(uniqueMessages[rightIndex].sentAt.timeIntervalSince(confirmed.sentAt))
                }
            guard let bestLocalIndex else { continue }
            removedLocalIndices.insert(bestLocalIndex)
            availableLocalIndices.remove(bestLocalIndex)
        }

        return uniqueMessages.enumerated().compactMap { index, message in
            removedLocalIndices.contains(index) ? nil : message
        }
    }

    private static func localEcho(_ local: ChatMessage, matches confirmed: ChatMessage) -> Bool {
        let confirmationDelay = confirmed.sentAt.timeIntervalSince(local.sentAt)
        guard local.body.trimmingCharacters(in: .whitespacesAndNewlines) ==
                confirmed.body.trimmingCharacters(in: .whitespacesAndNewlines),
              attachmentSignature(local.attachments) == attachmentSignature(confirmed.attachments),
              confirmationDelay >= -2,
              confirmationDelay <= 120 else {
            return false
        }
        return true
    }

    private static func attachmentSignature(_ attachments: [MessageAttachment]) -> [String] {
        attachments.map { attachment in
            [
                attachment.kind.rawValue,
                attachment.title.trimmingCharacters(in: .whitespacesAndNewlines),
                attachment.mimeType ?? "",
                attachment.byteCount.map(String.init) ?? ""
            ].joined(separator: "|")
        }
    }
}

struct CopAIChatAgentRequest: Encodable, Equatable, Sendable {
    var question: String
    var language = "cs"
    var chatContext: CopAIChatAgentContextSnapshot?
    var conversationId: String?
    var groupId: String? = nil
    var modelPreference = "auto"
    var maxObjects = 40
    var currentLocation: CopAIChatAgentLocation? = nil
    var place: String? = nil
    var placeQuery: String? = nil
    var timeWindow: CopAIChatAgentTimeWindow? = nil
    var maxAgeSeconds: Int? = nil
    var lookbackSeconds: Int? = nil
}

struct CopAIChatAgentLocation: Encodable, Equatable, Sendable {
    var lat: Double
    var lon: Double
    var radiusKm: Double? = nil
    var label: String? = nil
}

struct CopAIChatAgentTimeWindow: Encodable, Equatable, Sendable {
    var from: Date? = nil
    var since: Date? = nil
    var to: Date? = nil
    var maxAgeSeconds: Int? = nil
}

struct CopAIChatAgentContextSnapshot: Encodable, Equatable, Sendable {
    var roomId: String?
    var encrypted: Bool
    var visibleMessageCount: Int
    var includedMessageCount: Int
    var messages: [CopAIChatAgentContextMessage]
}

struct CopAIChatAgentContextMessage: Encodable, Equatable, Sendable {
    var body: String
    var eventId: String?
    var kind: String
    var own: Bool
    var replyToEventId: String? = nil
    var sender: String
    var senderDisplayName: String
    var timestamp: Date
}

struct CopAIChatAgentResponse: Decodable, Equatable, Sendable {
    var status: String
    var result: [String: CSMJSONValue]
    var auditId: String? = nil
    var requestId: String? = nil
    var provider: String? = nil
    var model: String? = nil
    var policy: [String: CSMJSONValue]? = nil
    var routing: [String: CSMJSONValue]? = nil

    var summary: String? {
        result["summary"]?.trimmedStringValue
    }

    var structured: [String: CSMJSONValue]? {
        guard case .object(let value) = result["structured"] else { return nil }
        return value
    }

    var mapActions: [[String: CSMJSONValue]] {
        guard case .array(let values) = structured?["mapActions"] else { return [] }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }
}

struct CopAIChatAgentJobResponse: Decodable, Equatable, Sendable {
    struct Failure: Decodable, Equatable, Sendable {
        var message: String?
        var statusCode: Int?
    }

    var contractVersion: String
    var jobId: String
    var requestId: String?
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var expiresAt: Date
    var response: CopAIChatAgentResponse?
    var error: Failure?
}

struct PendingMessageRecord: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String { message.id }
    var transactionId: String?
    var conversationId: String
    var message: ChatMessage
    var queuedAt: Date
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextRetryAt: Date?
    var lastError: String?

    init(
        conversationId: String,
        message: ChatMessage,
        transactionId: String? = nil,
        queuedAt: Date = .now,
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil,
        nextRetryAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.conversationId = conversationId
        self.message = message
        self.transactionId = transactionId ?? message.id
        self.queuedAt = queuedAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.lastError = lastError
    }

    var isRetryDue: Bool {
        guard let nextRetryAt else { return true }
        return nextRetryAt <= .now
    }

    var stableTransactionId: String {
        transactionId ?? message.id
    }
}

enum ReportCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case fire
    case flood
    case bridgeDamage = "bridge_damage"
    case roadBlockage = "road_blockage"
    case infrastructureDamage = "infrastructure_damage"
    case medical
    case utilityOutage = "utility_outage"
    case hazard
    case other

    var id: String { rawValue }
}

enum CommunityMediaAudience: String, Codable, CaseIterable, Identifiable, Sendable {
    case publicRead = "public"
    case privateRead = "private"
    case users
    case groups

    var id: String { rawValue }
}

enum CommunityAttachmentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo
    case video
    case document

    var id: String { rawValue }
}

enum CommunitySpatialVideoMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case sideBySide = "side_by_side"
    case overUnder = "over_under"
    case appleMVHEVC = "apple_mv_hevc"

    var id: String { rawValue }
}

struct CommunityMediaAccessPolicy: Codable, Equatable, Hashable, Sendable {
    var audience: CommunityMediaAudience
    var userSubjectIds: [String]
    var groupIds: [String]

    static let publicRead = CommunityMediaAccessPolicy(audience: .publicRead, userSubjectIds: [], groupIds: [])
    static let privateRead = CommunityMediaAccessPolicy(audience: .privateRead, userSubjectIds: [], groupIds: [])

    static func groups(_ groupIds: [String]) -> CommunityMediaAccessPolicy {
        CommunityMediaAccessPolicy(audience: .groups, userSubjectIds: [], groupIds: groupIds)
    }
}

struct CommunitySpatialVideoMetadata: Codable, Equatable, Hashable, Sendable {
    var mode: CommunitySpatialVideoMode

    static let none = CommunitySpatialVideoMetadata(mode: .none)
}

struct CommunityReportAttachmentDraft: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var fileName: String
    var contentType: String
    var byteSize: Int
    var kind: CommunityAttachmentKind
    var payload: Data
    var captureLocation: GeoPoint?
    var access: CommunityMediaAccessPolicy
    var spatialVideo: CommunitySpatialVideoMetadata
    var createdAt: Date
}

struct CommunityReportDraft: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var category: ReportCategory
    var title: String
    var description: String
    var location: GeoPoint
    var severity: AlertSeverity
    var groupId: String?
    var groupName: String
    var createdAt: Date
    var attachments: [CommunityReportAttachmentDraft] = []
}

struct CommunityReportDraftSeed: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var description: String
    var location: GeoPoint?
    var groupId: String?
    var groupName: String?
    var conversationId: String?
    var roomId: String?
    var source: String

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        location: GeoPoint? = nil,
        groupId: String? = nil,
        groupName: String? = nil,
        conversationId: String? = nil,
        roomId: String? = nil,
        source: String
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = location
        self.groupId = groupId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.conversationId = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.roomId = roomId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func chatSeed(
        conversation: Conversation,
        location: GeoPoint?
    ) -> CommunityReportDraftSeed {
        CommunityReportDraftSeed(
            title: CSMLocalization.text("report.seed.chat_title", fallback: "Hlášení: %@", conversation.title),
            description: CSMLocalization.text("report.seed.chat_description", fallback: "Zdroj: chat %@.", conversation.title),
            location: location,
            groupId: conversation.linkedCommunityGroupId,
            groupName: conversation.title,
            conversationId: conversation.conversationId,
            roomId: conversation.matrix?.roomId,
            source: "chat"
        )
    }
}

struct CommunityReportSubmission: Codable, Identifiable, Equatable, Hashable, Sendable {
    var reportId: String
    var status: String
    var submittedAt: Date
    var uploadedAttachmentCount: Int = 0

    var id: String { reportId }
}

struct CommunityReport: Decodable, Identifiable, Equatable, Hashable, Sendable {
    var reportId: String
    var category: ReportCategory
    var title: String
    var description: String?
    var location: GeoPoint
    var severity: AlertSeverity
    var status: String
    var groupId: String?
    var groupName: String?
    var attachmentCount: Int
    var observedAt: Date

    var id: String { reportId }

    enum CodingKeys: String, CodingKey {
        case reportId
        case category
        case title
        case description
        case location
        case severity
        case hazardSeverity
        case status
        case groupId
        case groupName
        case attachmentCount
        case attachments
        case observedAt
        case properties
    }

    init(
        reportId: String,
        category: ReportCategory,
        title: String,
        description: String?,
        location: GeoPoint,
        severity: AlertSeverity,
        status: String,
        groupId: String?,
        groupName: String?,
        attachmentCount: Int,
        observedAt: Date
    ) {
        self.reportId = reportId
        self.category = category
        self.title = title
        self.description = description
        self.location = location
        self.severity = severity
        self.status = status
        self.groupId = groupId
        self.groupName = groupName
        self.attachmentCount = attachmentCount
        self.observedAt = observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let properties = try container.decodeIfPresent(CommunityReportProperties.self, forKey: .properties)
        reportId = try container.decode(String.self, forKey: .reportId)
        category = try container.decode(ReportCategory.self, forKey: .category)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        location = try container.decode(GeoPoint.self, forKey: .location)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId) ?? properties?.groupId
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName) ?? properties?.groupName
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt) ?? .distantPast

        if let severity = try container.decodeIfPresent(AlertSeverity.self, forKey: .severity) {
            self.severity = severity
        } else {
            let hazardSeverity = try container.decodeIfPresent(String.self, forKey: .hazardSeverity) ?? properties?.hazardSeverity
            self.severity = AlertSeverity(communityHazardSeverity: hazardSeverity)
        }

        if let attachmentCount = try container.decodeIfPresent(Int.self, forKey: .attachmentCount) {
            self.attachmentCount = attachmentCount
        } else {
            attachmentCount = (try container.decodeIfPresent([CommunityReportAttachmentSummary].self, forKey: .attachments))?.count ?? 0
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct CommunityReportProperties: Decodable {
    var groupId: String?
    var groupName: String?
    var hazardSeverity: String?
}

private struct CommunityReportAttachmentSummary: Decodable {
    var attachmentId: String?
}

private extension AlertSeverity {
    init(communityHazardSeverity: String?) {
        switch communityHazardSeverity?.lowercased() {
        case "critical":
            self = .critical
        case "warning":
            self = .warning
        default:
            self = .info
        }
    }
}

struct SourceHealthItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    var sourceSystemId: String
    var label: String
    var status: String
    var updatedAt: Date?

    var id: String { sourceSystemId }

    enum CodingKeys: String, CodingKey {
        case sourceSystemId
        case label
        case displayName
        case status
        case updatedAt
        case lastObservationAt
    }

    init(sourceSystemId: String, label: String, status: String, updatedAt: Date?) {
        self.sourceSystemId = sourceSystemId
        self.label = label
        self.status = status
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceSystemId = try container.decode(String.self, forKey: .sourceSystemId)
        label = try container.decodeIfPresent(String.self, forKey: .label)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
            ?? sourceSystemId
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .lastObservationAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceSystemId, forKey: .sourceSystemId)
        try container.encode(label, forKey: .label)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    var isOperationallyHealthy: Bool {
        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStatus.isEmpty else { return false }
        if normalizedStatus.contains("degraded") ||
            normalizedStatus.contains("stale") ||
            normalizedStatus.contains("lost") ||
            normalizedStatus.contains("offline") ||
            normalizedStatus.contains("error") ||
            normalizedStatus.contains("failed") ||
            normalizedStatus.contains("warning") ||
            normalizedStatus.contains("unknown") {
            return false
        }
        return normalizedStatus.contains("ok") ||
            normalizedStatus.contains("online") ||
            normalizedStatus.contains("live") ||
            normalizedStatus.contains("healthy") ||
            normalizedStatus.contains("ready")
    }
}

struct ObservedObject: Codable, Identifiable, Equatable, Hashable, Sendable {
    var objectId: String
    var label: String?
    var objectType: String
    var affiliation: String?
    var position: GeoPoint
    var confidence: Double?
    var layerId: String?
    var sourceSystemId: String?
    var updatedAt: Date?

    var id: String { objectId }

    enum CodingKeys: String, CodingKey {
        case objectId
        case label
        case objectType
        case affiliation
        case position
        case confidence
        case layerId
        case layer
        case sourceSystemId
        case sourceId
        case updatedAt
        case lastUpdatedAt
    }

    init(
        objectId: String,
        label: String?,
        objectType: String,
        affiliation: String?,
        position: GeoPoint,
        confidence: Double?,
        updatedAt: Date?,
        layerId: String? = nil,
        sourceSystemId: String? = nil
    ) {
        self.objectId = objectId
        self.label = label
        self.objectType = objectType
        self.affiliation = affiliation
        self.position = position
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.layerId = layerId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sourceSystemId = sourceSystemId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decode(String.self, forKey: .objectId)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        objectType = try container.decodeIfPresent(String.self, forKey: .objectType) ?? "UNKNOWN"
        affiliation = try container.decodeIfPresent(String.self, forKey: .affiliation)
        position = try container.decode(GeoPoint.self, forKey: .position)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        layerId = try container.decodeIfPresent(String.self, forKey: .layerId)
            ?? container.decodeIfPresent(String.self, forKey: .layer)
        layerId = layerId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        sourceSystemId = try container.decodeIfPresent(String.self, forKey: .sourceSystemId)
            ?? container.decodeIfPresent(String.self, forKey: .sourceId)
        sourceSystemId = sourceSystemId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(objectId, forKey: .objectId)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(objectType, forKey: .objectType)
        try container.encodeIfPresent(affiliation, forKey: .affiliation)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(layerId, forKey: .layerId)
        try container.encodeIfPresent(sourceSystemId, forKey: .sourceSystemId)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    var inferredMapLayerId: String {
        if let directLayerId = Self.directCatalogLayerId(from: layerId) {
            return directLayerId
        }

        if isTAKLike {
            return "partner.tak.mobile"
        }
        if isFlightLike {
            return isSimulatedFlightLike ? "flight.sim.tracks" : "flight.public.tracks"
        }
        if let layerId, !layerId.isEmpty {
            return layerId
        }
        return "cop.objects"
    }

    func isVisibleInMapLayers(_ visibleLayerIds: Set<String>) -> Bool {
        visibleLayerIds.contains(inferredMapLayerId)
    }

    private var normalizedLayerId: String {
        layerId?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var normalizedObjectType: String {
        objectType.lowercased()
    }

    private var normalizedObjectId: String {
        objectId.lowercased()
    }

    private var normalizedSourceSystemId: String {
        sourceSystemId?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var isTAKLike: Bool {
        let source = normalizedSourceSystemId
        let type = normalizedObjectType
        return source.contains("tak") || type.contains("tak")
    }

    private var isFlightLike: Bool {
        let type = normalizedObjectType
        let source = normalizedSourceSystemId
        let objectId = normalizedObjectId
        let layer = normalizedLayerId
        return type.contains("air") ||
            type.contains("aero") ||
            type.contains("plane") ||
            type.contains("heli") ||
            type.contains("drone") ||
            type.contains("flight") ||
            type.contains("uav") ||
            type.contains("adsb") ||
            type.contains("ads-b") ||
            objectId.hasPrefix("flight:") ||
            objectId.contains(":adsb") ||
            source.contains("flight-data") ||
            source.contains("adsb") ||
            source.contains("ads-b") ||
            layer == "air-situation" ||
            layer == "public-flights" ||
            layer == "sim-air"
    }

    private var isSimulatedFlightLike: Bool {
        let source = normalizedSourceSystemId
        let layer = normalizedLayerId
        return layer == "sim-air" ||
            source.contains("sim-air") ||
            source.contains("sim.air") ||
            source.contains("sim_air") ||
            source.contains("air-situation") ||
            source.contains("synthetic") ||
            source.contains("simulation") ||
            source.contains("sim.flight-tracks")
    }

    private static func directCatalogLayerId(from rawLayerId: String?) -> String? {
        guard let rawLayerId else { return nil }
        let layerId = rawLayerId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch layerId {
        case "flight.public.tracks", "public-flight-tracks", "public.flight.tracks", "public-flights":
            return "flight.public.tracks"
        case "flight.sim.tracks", "sim-flight-tracks", "sim.flight.tracks", "sim-air":
            return "flight.sim.tracks"
        case "partner.tak.mobile":
            return "partner.tak.mobile"
        default:
            return nil
        }
    }
}

struct TrackHistoryPoint: Codable, Equatable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var observedAt: Date

    enum CodingKeys: String, CodingKey {
        case lat
        case lon
        case observedAt
        case timestamp
    }

    init(lat: Double, lon: Double, observedAt: Date) {
        self.lat = lat
        self.lon = lon
        self.observedAt = observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lat = try container.decode(Double.self, forKey: .lat)
        lon = try container.decode(Double.self, forKey: .lon)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .timestamp)
            ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lat, forKey: .lat)
        try container.encode(lon, forKey: .lon)
        try container.encode(observedAt, forKey: .observedAt)
    }
}

struct TrackHistory: Codable, Identifiable, Equatable, Hashable, Sendable {
    var objectId: String
    var points: [TrackHistoryPoint]

    var id: String { objectId }
}
