import Foundation

struct MobileBootstrap: Codable, Equatable, Sendable {
    var actor: AuthenticatedActor
    var auth: MobileAuthConfig
    var capabilities: MobileCapabilities
    var endpoints: [String: String]
    var map: MobileMapConfig
    var policy: MobileNativePolicy
    var profile: UserProfile
    var snapshot: MobileOfflineSnapshot
    var serverTimestamp: Date
}

enum MobilePairingSessionStatus: String, Codable, Equatable, Sendable {
    case pending
    case claimed
    case confirmed
    case expired
    case revoked
}

enum MobilePairingFlowStatus: String, Codable, Equatable, Sendable {
    case needsSignIn
    case claiming
    case waitingForWebConfirmation
    case paired
    case expired
    case accountMismatch
    case failed
}

struct MobilePairingPresentation: Identifiable, Equatable, Sendable {
    var id: String { code ?? status.rawValue }
    var code: String?
    var status: MobilePairingFlowStatus
    var expiresAt: Date?
    var detail: String?

    var isInProgress: Bool {
        switch status {
        case .needsSignIn, .claiming, .waitingForWebConfirmation:
            true
        case .paired, .expired, .accountMismatch, .failed:
            false
        }
    }
}

struct MobilePairingClaimRequest: Codable, Equatable, Sendable {
    struct Capabilities: Codable, Equatable, Sendable {
        var matrixRustSdk: Bool
        var e2ee: Bool
        var push: Bool
    }

    var deviceId: String
    var platform: String
    var appVersion: String
    var buildNumber: String
    var deviceModel: String
    var osVersion: String
    var matrixDeviceId: String?
    var capabilities: Capabilities
    var pushTokenRegistered: Bool
}

struct MobilePairingSessionResponse: Codable, Equatable, Sendable {
    var contractVersion: String
    var device: MobilePairedDevice?
    var pairing: MobilePairingSession
    var policy: MobileNativePolicy?
    var security: MobilePairingSecurity
    var serverTimestamp: Date
}

struct MobilePairingSession: Codable, Equatable, Sendable {
    var code: String
    var status: MobilePairingSessionStatus
    var expiresAt: Date
    var links: MobilePairingLinks
    var createdBy: MobilePairingActor?
    var claimedBy: MobilePairingActor?
    var claimedDevice: MobilePairingClaimedDevice?
    var claimedAt: Date?
    var confirmedAt: Date?
    var createdAt: Date?
}

struct MobilePairingLinks: Codable, Equatable, Sendable {
    var customSchemeUrl: URL
    var universalLink: URL
}

struct MobilePairingActor: Codable, Equatable, Sendable {
    var subjectId: String
    var username: String?
    var displayName: String?
}

struct MobilePairingClaimedDevice: Codable, Equatable, Sendable {
    var deviceId: String
    var platform: String
    var appVersion: String?
    var buildNumber: String?
    var deviceModel: String?
    var osVersion: String?
    var matrixDeviceId: String?
    var pushTokenRegistered: Bool?
}

struct MobilePairedDevice: Codable, Equatable, Sendable {
    var deviceId: String
    var deviceSessionId: String?
    var platform: String
    var status: String?
    var subjectId: String?
    var pushTokenRegistered: Bool?
    var pairedAt: Date?
    var registeredAt: Date?
}

struct MobilePairingSecurity: Codable, Equatable, Sendable {
    var containsAccessToken: Bool
    var containsRecoveryKey: Bool
    var containsRoomKeys: Bool
    var confirmationRequired: Bool

    var isMetadataOnly: Bool {
        !containsAccessToken && !containsRecoveryKey && !containsRoomKeys && confirmationRequired
    }
}

struct AuthenticatedActor: Codable, Equatable, Hashable, Sendable {
    var subjectId: String
    var username: String
    var displayName: String
    var roles: [String]
    var picture: String?
    var email: String?

    init(
        subjectId: String,
        username: String,
        displayName: String,
        roles: [String],
        picture: String? = nil,
        email: String? = nil
    ) {
        self.subjectId = subjectId
        self.username = username
        self.displayName = displayName
        self.roles = roles
        self.picture = picture
        self.email = email
    }
}

struct MobileAuthConfig: Codable, Equatable, Sendable {
    var mode: String
    var issuer: String?
    var clientId: String
    var redirectUriScheme: String
    var scope: String
}

struct MobileCapabilities: Codable, Equatable, Sendable {
    var alertAcknowledgement: Bool
    var aoiAlerts: Bool
    var bootstrap: Bool
    var communityReportUploads: Bool
    var communityReports: Bool
    var deviceRegistration: Bool
    var offlineSnapshot: Bool
    var pushNotifications: Bool
    var serverUserProfile: Bool
    var sseStream: Bool
    var trackHistory: Bool
}

struct MobileMapConfig: Codable, Equatable, Sendable {
    var attribution: String
    var defaultCenter: [Double]
    var defaultZoom: Double
    var glyphsTemplateUrl: String
    var styleUrl: String?
    var tileTemplateUrl: String
}

enum MapBasemapMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case imagery
    case hybrid

    var id: String { rawValue }
}

struct MapViewRegionState: Codable, Equatable, Sendable {
    var centerLat: Double
    var centerLon: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    var isRenderable: Bool {
        (-85.0...85.0).contains(centerLat) &&
            (-180.0...180.0).contains(centerLon) &&
            latitudeDelta > 0 &&
            longitudeDelta > 0
    }
}

struct MapDisplayProfile: Codable, Equatable, Sendable {
    var activeLayerIds: [String]
    var autoFit: Bool
    var basemapMode: MapBasemapMode
    var layerFilters: [String: [String: CSMJSONValue]]
    var showOfflineMap: Bool
    var showScale: Bool
    var lastRegion: MapViewRegionState?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case activeLayerIds
        case autoFit
        case basemapMode
        case layerFilters
        case showOfflineMap
        case showScale
        case lastRegion
        case updatedAt
    }

    init(
        activeLayerIds: [String],
        autoFit: Bool,
        basemapMode: MapBasemapMode,
        layerFilters: [String: [String: CSMJSONValue]] = [:],
        showOfflineMap: Bool,
        showScale: Bool,
        lastRegion: MapViewRegionState?,
        updatedAt: Date?
    ) {
        self.activeLayerIds = Self.normalizedLayerIds(activeLayerIds)
        self.autoFit = autoFit
        self.basemapMode = basemapMode
        self.layerFilters = Self.normalizedLayerFilters(layerFilters)
        self.showOfflineMap = showOfflineMap
        self.showScale = showScale
        self.lastRegion = lastRegion
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeLayerIds = Self.normalizedLayerIds(try container.decodeIfPresent([String].self, forKey: .activeLayerIds) ?? [])
        autoFit = try container.decodeIfPresent(Bool.self, forKey: .autoFit) ?? true
        basemapMode = try container.decodeIfPresent(MapBasemapMode.self, forKey: .basemapMode) ?? .hybrid
        layerFilters = Self.normalizedLayerFilters(
            try container.decodeIfPresent([String: [String: CSMJSONValue]].self, forKey: .layerFilters) ?? [:]
        )
        showOfflineMap = try container.decodeIfPresent(Bool.self, forKey: .showOfflineMap) ?? true
        showScale = try container.decodeIfPresent(Bool.self, forKey: .showScale) ?? true
        lastRegion = try container.decodeIfPresent(MapViewRegionState.self, forKey: .lastRegion)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    static func makeDefault(
        userProfile: UserProfile,
        catalog: MapLayerCatalog,
        now: Date = .now
    ) -> MapDisplayProfile {
        let availableLayerIds = Set(catalog.layers.filter(\.isAvailableInStandardMapUI).map(\.layerId))
        let explicitCatalogIds = normalizedLayerIds(userProfile.preferences.catalogLayerIds)
            .filter { availableLayerIds.contains($0) }
        let preferredIds = normalizedLayerIds(userProfile.preferredLayerIds)
            .filter { availableLayerIds.contains($0) }
        let defaultIds = catalog.layers
            .filter { $0.isAvailableInStandardMapUI && $0.defaultVisible }
            .map(\.layerId)
        let nativeIds = MapLayerCatalog.nativeDefaultVisibleLayerIds
            .filter { availableLayerIds.contains($0) }
        let activeIds = userProfile.preferences.hasCatalogLayerSelection
            ? explicitCatalogIds
            : normalizedLayerIds(preferredIds + defaultIds + nativeIds)
        let layerFilters = defaultLayerFilters(for: catalog).merging(userProfile.preferences.mapLayerFilters) { _, profileValue in
            profileValue
        }

        return MapDisplayProfile(
            activeLayerIds: activeIds,
            autoFit: true,
            basemapMode: .hybrid,
            layerFilters: layerFilters,
            showOfflineMap: true,
            showScale: true,
            lastRegion: nil,
            updatedAt: now
        )
    }

    func isLayerVisible(_ layerId: String) -> Bool {
        activeLayerIds.contains(layerId)
    }

    func filterValue(layerId: String, filter: MapLayerFilter) -> CSMJSONValue? {
        layerFilters[layerId]?[filter.filterId] ?? filter.defaultValue
    }

    func replacingLayerVisibility(layerId: String, isVisible: Bool, now: Date = .now) -> MapDisplayProfile {
        var next = self
        var ids = Set(next.activeLayerIds)
        if isVisible {
            ids.insert(layerId)
        } else {
            ids.remove(layerId)
        }
        next.activeLayerIds = Self.normalizedLayerIds(Array(ids))
        next.updatedAt = now
        return next
    }

    func replacingFilterValue(
        layerId: String,
        filterId: String,
        value: CSMJSONValue?,
        now: Date = .now
    ) -> MapDisplayProfile {
        var next = self
        var layerValues = next.layerFilters[layerId] ?? [:]
        if let value {
            layerValues[filterId] = value
        } else {
            layerValues.removeValue(forKey: filterId)
        }

        if layerValues.isEmpty {
            next.layerFilters.removeValue(forKey: layerId)
        } else {
            next.layerFilters[layerId] = layerValues
        }
        next.layerFilters = Self.normalizedLayerFilters(next.layerFilters)
        next.updatedAt = now
        return next
    }

    func normalizedForCatalog(_ catalog: MapLayerCatalog) -> MapDisplayProfile {
        let selectableIds = Set(catalog.layers.filter(\.isAvailableInStandardMapUI).map(\.layerId))
        let filterIdsByLayer = Dictionary(uniqueKeysWithValues: catalog.layers.map { layer in
            (layer.layerId, Set(layer.filters.map(\.filterId)))
        })
        var next = self
        next.activeLayerIds = Self.normalizedLayerIds(activeLayerIds).filter { selectableIds.contains($0) }
        if next.activeLayerIds.isEmpty {
            next.activeLayerIds = MapLayerCatalog.nativeDefaultVisibleLayerIds.filter { selectableIds.contains($0) }
        }
        next.layerFilters = Self.normalizedLayerFilters(layerFilters).reduce(into: [:]) { partial, entry in
            guard selectableIds.contains(entry.key), let allowedFilterIds = filterIdsByLayer[entry.key] else { return }
            let filterValues = entry.value.filter { allowedFilterIds.contains($0.key) }
            guard !filterValues.isEmpty else { return }
            partial[entry.key] = filterValues
        }
        return next
    }

    func removingLayerIds(_ layerIds: Set<String>, now: Date = .now) -> MapDisplayProfile {
        guard !layerIds.isEmpty else { return self }
        var next = self
        next.activeLayerIds = Self.normalizedLayerIds(activeLayerIds).filter { !layerIds.contains($0) }
        for layerId in layerIds {
            next.layerFilters.removeValue(forKey: layerId)
        }
        next.layerFilters = Self.normalizedLayerFilters(next.layerFilters)
        next.updatedAt = now
        return next
    }

    func replacingView(
        autoFit: Bool? = nil,
        basemapMode: MapBasemapMode? = nil,
        showOfflineMap: Bool? = nil,
        showScale: Bool? = nil,
        lastRegion: MapViewRegionState? = nil,
        now: Date = .now
    ) -> MapDisplayProfile {
        var next = self
        if let autoFit {
            next.autoFit = autoFit
        }
        if let basemapMode {
            next.basemapMode = basemapMode
        }
        if let showOfflineMap {
            next.showOfflineMap = showOfflineMap
        }
        if let showScale {
            next.showScale = showScale
        }
        if let lastRegion, lastRegion.isRenderable {
            next.lastRegion = lastRegion
        }
        next.updatedAt = now
        return next
    }

    static func normalizedLayerIds(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return nil }
            seen.insert(trimmed)
            return trimmed
        }
    }

    static func normalizedLayerFilters(_ values: [String: [String: CSMJSONValue]]) -> [String: [String: CSMJSONValue]] {
        values.reduce(into: [String: [String: CSMJSONValue]]()) { partial, entry in
            let layerId = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !layerId.isEmpty else { return }
            let filters = entry.value.reduce(into: [String: CSMJSONValue]()) { filterPartial, filterEntry in
                let filterId = filterEntry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !filterId.isEmpty, !filterEntry.value.isEmptyQueryValue else { return }
                filterPartial[filterId] = filterEntry.value
            }
            guard !filters.isEmpty else { return }
            partial[layerId] = filters
        }
    }

    private static func defaultLayerFilters(for catalog: MapLayerCatalog) -> [String: [String: CSMJSONValue]] {
        catalog.layers.reduce(into: [String: [String: CSMJSONValue]]()) { partial, layer in
            let filters = layer.filters.reduce(into: [String: CSMJSONValue]()) { filterPartial, filter in
                guard let value = filter.defaultValue, !value.isEmptyQueryValue else { return }
                filterPartial[filter.filterId] = value
            }
            guard !filters.isEmpty else { return }
            partial[layer.layerId] = filters
        }
    }
}

struct MapLayerCatalog: Codable, Equatable, Sendable {
    var catalogVersion: String
    var generatedAt: Date?
    var locale: String?
    var groups: [MapLayerGroup]
    var layers: [MapLayerDefinition]

    static let publicSafetyLayerIds = [
        "public.safety.warnings",
        "public.safety.weather_alerts",
        "public.safety.fire",
        "public.safety.flood"
    ]

    static let stableCopSimLayerIds = [
        "cop.objects",
        "public.safety.warnings",
        "public.safety.weather_alerts",
        "public.safety.fire",
        "public.safety.flood",
        "public.weather.current",
        "public.weather.aviation",
        "public.weather.observations",
        "public.weather.webcams",
        "public.safety.air_quality",
        "public.weather.temperature_grid",
        "public.weather.wind_field",
        "public.weather.precipitation_grid",
        "public.weather.humidity_grid",
        "public.weather.pressure_grid",
        "public.weather.radar_reflectivity",
        "public.weather.radar_precipitation",
        "public.weather.radar_nowcast",
        "public.safety.thunderstorm_risk",
        "public.safety.air_quality_grid",
        "public.mobile.network",
        "public.traffic.transit",
        "public.traffic.transit_stops",
        "public.traffic.road_events",
        "public.boundary.admin",
        "public.boundary.country",
        "public.boundary.region",
        "public.boundary.district",
        "public.boundary.orp",
        "public.place.settlements",
        "reference.infrastructure.healthcare",
        "reference.infrastructure.emergency",
        "reference.infrastructure.communications",
        "flight.public.tracks",
        "flight.reference.airports",
        "flight.reference.airspaces",
        "flight.reference.uas_geozones",
        "flight.airspace.activation",
        "partner.tak.mobile",
        "partner.tak.ground",
        "partner.tak.traffic",
        "diagnostic.mobile.coverage",
        "diagnostic.mobile.ctu_measurements",
        "user.community.reports",
        "user.sketch.drawings",
        "field.radio.planning",
        "offline.map"
    ]

    static let technicalLifecycleSignalIds = [
        "TRACK_STALE",
        "TRACK_LOST",
        "LOW_CONFIDENCE",
        "SOURCE_DEGRADED"
    ]

    static let nativeDefaultVisibleLayerIds = [
        "cop.objects",
        "public.safety.warnings",
        "public.safety.weather_alerts",
        "public.weather.observations",
        "user.community.reports",
        "user.sketch.drawings",
        "flight.public.tracks",
        "flight.sim.tracks"
    ]

    static let nativeFallback = MapLayerCatalog(
        catalogVersion: "native-fallback",
        generatedAt: nil,
        locale: "cs-CZ",
        groups: [
            MapLayerGroup(groupId: "operations", label: CSMLocalization.text("map.catalog.group.operations", fallback: "Situace"), icon: "map", order: 10),
            MapLayerGroup(groupId: "risks", label: CSMLocalization.text("map.catalog.group.risks", fallback: "Rizika"), icon: "exclamationmark.triangle", order: 20),
            MapLayerGroup(groupId: "risks.weather", label: CSMLocalization.text("map.catalog.group.weather", fallback: "Počasí"), icon: "cloud.sun", order: 24),
            MapLayerGroup(groupId: "community", label: CSMLocalization.text("map.catalog.group.community", fallback: "Hlášení"), icon: "person.3", order: 30),
            MapLayerGroup(groupId: "communications", label: CSMLocalization.text("map.catalog.group.communications", fallback: "Spojení"), icon: "antenna.radiowaves.left.and.right", order: 35),
            MapLayerGroup(groupId: "traffic", label: CSMLocalization.text("map.catalog.group.traffic", fallback: "Doprava"), icon: "car", order: 36),
            MapLayerGroup(groupId: "reference", label: CSMLocalization.text("map.catalog.group.reference", fallback: "Reference"), icon: "building.2", order: 37),
            MapLayerGroup(groupId: "flight", label: CSMLocalization.text("map.catalog.group.flight", fallback: "Letecký provoz"), icon: "airplane", order: 38),
            MapLayerGroup(groupId: "diagnostics", label: CSMLocalization.text("map.catalog.group.diagnostics", fallback: "Diagnostika"), icon: "wrench.and.screwdriver", order: 39),
            MapLayerGroup(groupId: "offline", label: CSMLocalization.text("map.catalog.group.offline", fallback: "Offline"), icon: "externaldrive.badge.checkmark", order: 40)
        ],
        layers: [
            MapLayerDefinition(
                layerId: "cop.objects",
                label: CSMLocalization.text("map.catalog.cop_objects.label", fallback: "Jednotky a objekty"),
                description: CSMLocalization.text("map.catalog.cop_objects.description", fallback: "Aktuální situační objekty z COP streamu."),
                groupId: "operations",
                role: "primary",
                audience: "operator",
                kind: "track_stream",
                defaultVisible: true,
                selectable: true,
                icon: "scope",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: 5,
                cacheTtlSeconds: nil,
                styleProfile: "cop-native-objects",
                query: MapLayerQuery(
                    mode: "stream",
                    providerId: "cop.tracks",
                    streamId: "tracks"
                )
            ),
            MapLayerDefinition(
                layerId: "public.safety.warnings",
                label: CSMLocalization.text("map.catalog.safety_warnings.label", fallback: "Výstrahy"),
                description: CSMLocalization.text("map.catalog.safety_warnings.description", fallback: "Bezpečnostní výstrahy relevantní pro aktuální profil."),
                groupId: "risks",
                role: "overlay",
                audience: "public",
                kind: "vector_features",
                defaultVisible: true,
                selectable: true,
                icon: "exclamationmark.triangle.fill",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: 60,
                cacheTtlSeconds: 900,
                styleProfile: "public-safety-warning",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "sim.safety-data",
                    streamId: "features",
                    providerLayerIds: ["warnings"],
                    providerSourceIds: ["gdacs_alerts", "hzs_incidents", "road_srti_lod"]
                ),
                provenance: MapLayerProvenance(
                    sourceIds: [
                        "sim.safety-data:gdacs_alerts",
                        "sim.safety-data:hzs_incidents",
                        "sim.safety-data:road_srti_lod"
                    ]
                )
            ),
            MapLayerDefinition(
                layerId: "public.safety.flood",
                label: CSMLocalization.text("map.catalog.flood.label", fallback: "Povodně a voda"),
                description: CSMLocalization.text("map.catalog.flood.description", fallback: "Hydrologická rizika a vodní situace."),
                groupId: "risks",
                role: "overlay",
                audience: "public",
                kind: "vector_features",
                defaultVisible: false,
                selectable: true,
                icon: "drop.fill",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: 300,
                cacheTtlSeconds: 900,
                styleProfile: "public-safety-flood",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "sim.safety-data",
                    streamId: "features",
                    providerLayerIds: ["flood"]
                )
            ),
            nativeFeatureLayer(
                layerId: "public.safety.weather_alerts",
                labelKey: "map.catalog.safety_weather_alerts.label",
                labelFallback: "Meteorologické výstrahy",
                descriptionKey: "map.catalog.safety_weather_alerts.description",
                descriptionFallback: "Oficiální meteorologické výstrahy ČHMÚ bez duplicit v obecné vrstvě výstrah.",
                groupId: "risks",
                defaultVisible: true,
                providerId: "sim.safety-data",
                providerLayerIds: ["weather_alerts"],
                providerSourceIds: ["chmi_alerts"],
                icon: "cloud.bolt.rain.fill",
                styleProfile: "public-safety-weather-alerts"
            ),
            nativeFeatureLayer(
                layerId: "public.safety.fire",
                labelKey: "map.catalog.safety_fire.label",
                labelFallback: "Požáry",
                descriptionKey: "map.catalog.safety_fire.description",
                descriptionFallback: "Požární nebezpečí, požární incidenty a ověřené veřejné požární zdroje.",
                groupId: "risks",
                providerId: "sim.safety-data",
                providerLayerIds: ["fire"],
                providerSourceIds: ["chmi_alerts", "gdacs_alerts", "hzs_incidents", "nasa_firms", "fire_hotspots", "fire_incidents"],
                icon: "flame.fill",
                styleProfile: "public-safety-fire"
            ),
            MapLayerDefinition(
                layerId: "public.weather.observations",
                label: CSMLocalization.text("map.catalog.weather_observations.label", fallback: "Počasí"),
                description: CSMLocalization.text("map.catalog.weather_observations.description", fallback: "Měřené počasí ze stanic ČHMÚ: teplota, vítr, srážky, vlhkost, tlak a odvozený stav počasí."),
                groupId: "risks.weather",
                role: "primary",
                audience: "public",
                kind: "vector_features",
                defaultVisible: true,
                selectable: true,
                icon: "cloud.sun.rain.fill",
                minZoom: 4,
                maxZoom: 18,
                refreshSeconds: 600,
                cacheTtlSeconds: 900,
                styleProfile: "weather-observations-v1",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "sim.situation-data",
                    streamId: "features",
                    providerLayerIds: ["weather"],
                    providerSourceIds: ["chmi_weather_stations"],
                    maxFeatures: 150
                ),
                provenance: MapLayerProvenance(
                    sourceIds: ["sim.situation-data:chmi_weather_stations"]
                )
            ),
            MapLayerDefinition(
                layerId: "public.weather.webcams",
                label: CSMLocalization.text("map.catalog.weather_webcams.label", fallback: "Webkamery ČHMÚ"),
                description: CSMLocalization.text("map.catalog.weather_webcams.description", fallback: "Webkamery ČHMÚ jako vizuální kontext počasí. Nejde o výstrahu ani automatický incident."),
                groupId: "risks.weather",
                role: "overlay",
                audience: "public",
                kind: "vector_features",
                defaultVisible: false,
                selectable: true,
                icon: "camera.viewfinder",
                minZoom: 4,
                maxZoom: 18,
                refreshSeconds: 600,
                cacheTtlSeconds: 600,
                styleProfile: "weather-webcams-v1",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "sim.situation-data",
                    streamId: "features",
                    providerLayerIds: ["weather_webcams"],
                    providerSourceIds: ["chmi_weather_webcams"],
                    maxFeatures: 200
                ),
                provenance: MapLayerProvenance(
                    sourceIds: ["sim.situation-data:chmi_weather_webcams"]
                )
            ),
            nativeFeatureLayer(
                layerId: "public.weather.current",
                labelKey: "map.catalog.weather_current.label",
                labelFallback: "Počasí ve středu mapy",
                descriptionKey: "map.catalog.weather_current.description",
                descriptionFallback: "Bodový aktuální souhrn počasí pro střed mapy. Není to plošná vrstva.",
                groupId: "risks.weather",
                role: "reference",
                selectable: false,
                providerLayerIds: ["weather"],
                providerSourceIds: ["open_meteo"],
                icon: "location.fill.viewfinder",
                styleProfile: "weather-current-v1",
                maxFeatures: 1
            ),
            nativeFeatureLayer(
                layerId: "public.weather.aviation",
                labelKey: "map.catalog.weather_aviation.label",
                labelFallback: "Letištní počasí",
                descriptionKey: "map.catalog.weather_aviation.description",
                descriptionFallback: "Letištní meteorologický kontext z COP/SIM pro leteckou situaci.",
                groupId: "risks.weather",
                providerLayerIds: ["weather"],
                providerSourceIds: ["aviation_weather"],
                icon: "cloud.sun.bolt.fill",
                styleProfile: "weather-aviation-v1",
                maxFeatures: 100
            ),
            nativeFeatureLayer(
                layerId: "public.safety.air_quality",
                labelKey: "map.catalog.air_quality.label",
                labelFallback: "Kvalita ovzduší",
                descriptionKey: "map.catalog.air_quality.description",
                descriptionFallback: "Měřené imisní stanice ČHMÚ a zdravotně relevantní index kvality ovzduší.",
                groupId: "risks.weather",
                providerLayerIds: ["air_quality"],
                providerSourceIds: ["chmi_air_quality"],
                icon: "aqi.medium",
                styleProfile: "air-quality-stations-v1",
                maxFeatures: 150
            ),
            nativeFeatureLayer(
                layerId: "public.weather.temperature_grid",
                labelKey: "map.catalog.weather_temperature_grid.label",
                labelFallback: "Teplotní pole",
                descriptionKey: "map.catalog.weather_temperature_grid.description",
                descriptionFallback: "Interpolované teplotní pole z měřených meteorologických stanic.",
                groupId: "risks.weather",
                kind: "grid_field",
                providerLayerIds: ["weather_temperature_grid"],
                providerSourceIds: ["chmi_weather_stations"],
                icon: "thermometer.medium",
                styleProfile: "weather-temperature-grid-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "public.weather.wind_field",
                labelKey: "map.catalog.weather_wind_field.label",
                labelFallback: "Vítr",
                descriptionKey: "map.catalog.weather_wind_field.description",
                descriptionFallback: "Vektorové pole větru z měřených meteorologických stanic.",
                groupId: "risks.weather",
                kind: "vector_field",
                providerLayerIds: ["weather_wind_field"],
                providerSourceIds: ["chmi_weather_stations"],
                icon: "wind",
                styleProfile: "weather-wind-field-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "public.weather.precipitation_grid",
                labelKey: "map.catalog.weather_precipitation_grid.label",
                labelFallback: "Srážky",
                descriptionKey: "map.catalog.weather_precipitation_grid.description",
                descriptionFallback: "Srážkové pole v jednotkách mm/10 min podle COP katalogu.",
                groupId: "risks.weather",
                kind: "grid_field",
                providerLayerIds: ["weather_precipitation_grid"],
                providerSourceIds: ["chmi_weather_stations"],
                icon: "cloud.rain.fill",
                styleProfile: "weather-precipitation-grid-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "public.weather.humidity_grid",
                labelKey: "map.catalog.weather_humidity_grid.label",
                labelFallback: "Vlhkost",
                descriptionKey: "map.catalog.weather_humidity_grid.description",
                descriptionFallback: "Interpolované pole relativní vlhkosti.",
                groupId: "risks.weather",
                kind: "grid_field",
                providerLayerIds: ["weather_humidity_grid"],
                providerSourceIds: ["chmi_weather_stations"],
                icon: "humidity.fill",
                styleProfile: "weather-humidity-grid-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "public.weather.pressure_grid",
                labelKey: "map.catalog.weather_pressure_grid.label",
                labelFallback: "Tlak",
                descriptionKey: "map.catalog.weather_pressure_grid.description",
                descriptionFallback: "Interpolované pole atmosférického tlaku.",
                groupId: "risks.weather",
                kind: "grid_field",
                providerLayerIds: ["weather_pressure_grid"],
                providerSourceIds: ["chmi_weather_stations"],
                icon: "barometer",
                styleProfile: "weather-pressure-grid-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "public.weather.radar_reflectivity",
                labelKey: "map.catalog.weather_radar_reflectivity.label",
                labelFallback: "Radarová odrazivost",
                descriptionKey: "map.catalog.weather_radar_reflectivity.description",
                descriptionFallback: "Radarový raster overlay ČHMÚ MAX_Z přes COP proxy.",
                groupId: "risks.weather",
                kind: "raster_overlay",
                providerLayerIds: ["weather_radar_reflectivity"],
                providerSourceIds: ["chmi_weather_radar"],
                icon: "dot.radiowaves.left.and.right",
                styleProfile: "weather-radar-reflectivity-v1",
                maxFeatures: 20
            ),
            nativeFeatureLayer(
                layerId: "public.weather.radar_precipitation",
                labelKey: "map.catalog.weather_radar_precipitation.label",
                labelFallback: "Radarové srážky",
                descriptionKey: "map.catalog.weather_radar_precipitation.description",
                descriptionFallback: "Radarový srážkový kontext ČHMÚ přes COP proxy.",
                groupId: "risks.weather",
                kind: "raster_overlay",
                providerLayerIds: ["weather_radar_precipitation"],
                providerSourceIds: ["chmi_weather_radar"],
                icon: "cloud.heavyrain.fill",
                styleProfile: "weather-radar-precipitation-v1",
                maxFeatures: 20
            ),
            nativeFeatureLayer(
                layerId: "public.weather.radar_nowcast",
                labelKey: "map.catalog.weather_radar_nowcast.label",
                labelFallback: "Radarový nowcast",
                descriptionKey: "map.catalog.weather_radar_nowcast.description",
                descriptionFallback: "Nowcast srážek a radarového vývoje přes COP proxy.",
                groupId: "risks.weather",
                kind: "raster_overlay",
                providerLayerIds: ["weather_radar_nowcast"],
                providerSourceIds: ["chmi_weather_radar"],
                icon: "clock.badge.checkmark",
                styleProfile: "weather-radar-nowcast-v1",
                maxFeatures: 20
            ),
            nativeFeatureLayer(
                layerId: "public.safety.thunderstorm_risk",
                labelKey: "map.catalog.thunderstorm_risk.label",
                labelFallback: "Bouřkové riziko",
                descriptionKey: "map.catalog.thunderstorm_risk.description",
                descriptionFallback: "Radarový kontext bouřkových jader bez raw feedu blesků.",
                groupId: "risks.weather",
                kind: "raster_overlay",
                providerLayerIds: ["weather_thunderstorm_risk"],
                providerSourceIds: ["chmi_weather_radar"],
                icon: "cloud.bolt.rain.fill",
                styleProfile: "weather-thunderstorm-risk-v1",
                maxFeatures: 20
            ),
            nativeFeatureLayer(
                layerId: "public.safety.air_quality_grid",
                labelKey: "map.catalog.air_quality_grid.label",
                labelFallback: "Kvalita ovzduší - plocha",
                descriptionKey: "map.catalog.air_quality_grid.description",
                descriptionFallback: "Plošný grid kvality ovzduší a hlavních polutantů.",
                groupId: "risks.weather",
                kind: "grid_field",
                providerLayerIds: ["air_quality_grid"],
                providerSourceIds: ["chmi_air_quality"],
                icon: "aqi.high",
                styleProfile: "air-quality-grid-v1",
                maxFeatures: 300
            ),
            MapLayerDefinition(
                layerId: "user.community.reports",
                label: CSMLocalization.text("map.catalog.community_reports.label", fallback: "Hlášení uživatelů"),
                description: CSMLocalization.text("map.catalog.community_reports.description", fallback: "Ověřená komunitní hlášení s fotkami, soubory nebo polohou."),
                groupId: "community",
                role: "user",
                audience: "operator",
                kind: "user_objects",
                defaultVisible: true,
                selectable: true,
                icon: "camera.fill",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: 30,
                cacheTtlSeconds: 900,
                styleProfile: "community-report",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "cop.community",
                    streamId: "features"
                )
            ),
            MapLayerDefinition(
                layerId: "user.sketch.drawings",
                label: CSMLocalization.text("map.catalog.sketch_drawings.label", fallback: "Zákresy"),
                description: CSMLocalization.text("map.catalog.sketch_drawings.description", fallback: "Sdílené COP zákresy, měření a poznámky v mapě."),
                groupId: "community",
                role: "user",
                audience: "operator",
                kind: "user_objects",
                defaultVisible: true,
                selectable: true,
                icon: "pencil.line",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: 30,
                cacheTtlSeconds: 900,
                styleProfile: "cop-sketch-drawings",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "cop.sketch",
                    streamId: "drawings"
                )
            ),
            MapLayerDefinition(
                layerId: "public.mobile.network",
                label: CSMLocalization.text("map.catalog.mobile_network.label", fallback: "Mobilní síť"),
                description: CSMLocalization.text("map.catalog.mobile_network.description", fallback: "Dostupnost a kvalita mobilního spojení v krizové oblasti."),
                groupId: "communications",
                role: "overlay",
                audience: "public",
                kind: "vector_features",
                defaultVisible: false,
                selectable: true,
                icon: "antenna.radiowaves.left.and.right",
                minZoom: 6,
                maxZoom: 18,
                refreshSeconds: 300,
                cacheTtlSeconds: 600,
                styleProfile: "mobile-network-quality-v1",
                query: MapLayerQuery(
                    mode: "bbox",
                    providerId: "sim.situation-data",
                    streamId: "features",
                    providerLayerIds: ["mobile_network"],
                    providerSourceIds: ["mobile_network_model"],
                    maxFeatures: 250
                ),
                filters: [
                    MapLayerFilter(
                        filterId: "technology",
                        label: "Technologie",
                        type: "multi_select",
                        values: ["2G", "4G", "5G"],
                        defaultValue: .array([.string("4G")])
                    )
                ],
                provenance: MapLayerProvenance(
                    sourceIds: ["sim.situation-data:mobile_network_model"],
                    technicalInputs: [
                        "sim.situation-data:mobile_coverage_model",
                        "sim.situation-data:ctu_nettest"
                    ]
                )
            ),
            nativeFeatureLayer(
                layerId: "public.traffic.transit",
                labelKey: "map.catalog.traffic_transit.label",
                labelFallback: "Veřejná doprava",
                descriptionKey: "map.catalog.traffic_transit.description",
                descriptionFallback: "Dopravní provoz a veřejná doprava z COP/SIM.",
                groupId: "traffic",
                providerLayerIds: ["traffic"],
                providerSourceIds: ["pid_gtfs_rt"],
                icon: "bus.fill",
                styleProfile: "traffic-transit-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "public.traffic.transit_stops",
                labelKey: "map.catalog.traffic_transit_stops.label",
                labelFallback: "Zastávky veřejné dopravy",
                descriptionKey: "map.catalog.traffic_transit_stops.description",
                descriptionFallback: "Statické zastávky veřejné dopravy z COP/SIM katalogu.",
                groupId: "traffic",
                role: "reference",
                providerLayerIds: ["traffic"],
                providerSourceIds: ["public_transit_static"],
                icon: "mappin.circle.fill",
                minZoom: 11,
                styleProfile: "traffic-public-transit-stops-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "public.traffic.road_events",
                labelKey: "map.catalog.traffic_road_events.label",
                labelFallback: "Dopravní události",
                descriptionKey: "map.catalog.traffic_road_events.description",
                descriptionFallback: "Dopravní kontext a omezení ze zdrojů NDIC/ŘSD.",
                groupId: "traffic",
                providerLayerIds: ["traffic"],
                providerSourceIds: ["road_srti_lod"],
                icon: "road.lanes",
                styleProfile: "traffic-road-events-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "public.boundary.admin",
                labelKey: "map.catalog.boundary_admin.label",
                labelFallback: "Správní hranice",
                descriptionKey: "map.catalog.boundary_admin.description",
                descriptionFallback: "Správní hranice pro orientaci a filtrování situace.",
                groupId: "reference",
                role: "reference",
                providerId: "sim.safety-data",
                providerLayerIds: ["boundary_admin"],
                providerSourceIds: ["admin_boundaries"],
                icon: "map",
                styleProfile: "boundary-admin-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "public.boundary.country",
                labelKey: "map.catalog.boundary_country.label",
                labelFallback: "Hranice státu",
                descriptionKey: "map.catalog.boundary_country.description",
                descriptionFallback: "Referenční hranice státu.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["boundary_country"],
                providerSourceIds: ["osm_postgis"],
                icon: "map",
                styleProfile: "boundary-country-v1",
                maxFeatures: 50
            ),
            nativeFeatureLayer(
                layerId: "public.boundary.region",
                labelKey: "map.catalog.boundary_region.label",
                labelFallback: "Kraje",
                descriptionKey: "map.catalog.boundary_region.description",
                descriptionFallback: "Referenční hranice krajů.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["boundary_region"],
                providerSourceIds: ["osm_postgis"],
                icon: "map",
                styleProfile: "boundary-region-v1",
                maxFeatures: 80
            ),
            nativeFeatureLayer(
                layerId: "public.boundary.district",
                labelKey: "map.catalog.boundary_district.label",
                labelFallback: "Okresy",
                descriptionKey: "map.catalog.boundary_district.description",
                descriptionFallback: "Referenční hranice okresů.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["boundary_district"],
                providerSourceIds: ["osm_postgis"],
                icon: "map",
                styleProfile: "boundary-district-v1",
                maxFeatures: 120
            ),
            nativeFeatureLayer(
                layerId: "public.boundary.orp",
                labelKey: "map.catalog.boundary_orp.label",
                labelFallback: "ORP",
                descriptionKey: "map.catalog.boundary_orp.description",
                descriptionFallback: "Referenční hranice obcí s rozšířenou působností.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["boundary_orp"],
                providerSourceIds: ["osm_postgis"],
                icon: "map",
                styleProfile: "boundary-orp-v1",
                maxFeatures: 160
            ),
            nativeFeatureLayer(
                layerId: "public.place.settlements",
                labelKey: "map.catalog.place_settlements.label",
                labelFallback: "Sídla",
                descriptionKey: "map.catalog.place_settlements.description",
                descriptionFallback: "Referenční sídla a místní názvy pro orientaci v terénu.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["place_settlements"],
                providerSourceIds: ["osm_postgis"],
                icon: "house.and.flag.fill",
                styleProfile: "place-settlements-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "reference.infrastructure.healthcare",
                labelKey: "map.catalog.infrastructure_healthcare.label",
                labelFallback: "Zdravotnictví",
                descriptionKey: "map.catalog.infrastructure_healthcare.description",
                descriptionFallback: "Nemocnice, lékárny a zdravotnické body z COP/SIM referenčních dat.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["ground"],
                providerSourceIds: ["osm_postgis"],
                categoryIds: ["hospital", "clinic", "doctors", "pharmacy"],
                icon: "cross.case.fill",
                styleProfile: "reference-healthcare-v1",
                maxFeatures: 200
            ),
            nativeFeatureLayer(
                layerId: "reference.infrastructure.emergency",
                labelKey: "map.catalog.infrastructure_emergency.label",
                labelFallback: "Záchranná infrastruktura",
                descriptionKey: "map.catalog.infrastructure_emergency.description",
                descriptionFallback: "Hasiči, policie, záchranná služba a nouzové body.",
                groupId: "reference",
                role: "reference",
                providerLayerIds: ["ground"],
                providerSourceIds: ["osm_postgis"],
                categoryIds: ["fire_station", "police", "ambulance_station", "shelter"],
                icon: "cross.case.circle.fill",
                styleProfile: "reference-emergency-v1",
                maxFeatures: 200
            ),
            nativeFeatureLayer(
                layerId: "reference.infrastructure.communications",
                labelKey: "map.catalog.infrastructure_communications.label",
                labelFallback: "Komunikační stožáry",
                descriptionKey: "map.catalog.infrastructure_communications.description",
                descriptionFallback: "Referenční OSM komunikační infrastruktura. Nejde o potvrzený stav operátora.",
                groupId: "communications",
                role: "reference",
                selectable: false,
                providerLayerIds: ["mobile"],
                providerSourceIds: ["osm_postgis"],
                categoryIds: ["communications_tower"],
                icon: "antenna.radiowaves.left.and.right.circle",
                styleProfile: "reference-communications-v1",
                maxFeatures: 200
            ),
            MapLayerDefinition(
                layerId: "flight.public.tracks",
                label: CSMLocalization.text("map.catalog.flight_public.label", fallback: "Veřejné lety"),
                description: CSMLocalization.text("map.catalog.flight_public.description", fallback: "Veřejná letová data agregovaná přes SIM flight-data."),
                groupId: "flight",
                role: "primary",
                audience: "public",
                kind: "track_stream",
                defaultVisible: true,
                selectable: true,
                icon: "airplane",
                minZoom: 4,
                maxZoom: 18,
                refreshSeconds: 5,
                cacheTtlSeconds: 5,
                styleProfile: "flight-public-track-v1",
                query: MapLayerQuery(
                    mode: "stream",
                    providerId: "cop.tracks",
                    streamId: "cop.live",
                    maxFeatures: 500
                ),
                provenance: MapLayerProvenance(sourceIds: ["sim.flight-data"])
            ),
            nativeFeatureLayer(
                layerId: "flight.reference.airports",
                labelKey: "map.catalog.flight_airports.label",
                labelFallback: "Letiště",
                descriptionKey: "map.catalog.flight_airports.description",
                descriptionFallback: "Referenční letiště a heliporty ze SIM flight-data.",
                groupId: "flight",
                role: "reference",
                providerId: "sim.flight-data",
                providerLayerIds: ["flight.airports"],
                providerSourceIds: ["flight_reference"],
                icon: "airplane.arrival",
                styleProfile: "flight-reference-airports-v1",
                maxFeatures: 200
            ),
            nativeFeatureLayer(
                layerId: "flight.reference.airspaces",
                labelKey: "map.catalog.flight_airspaces.label",
                labelFallback: "Letecké prostory",
                descriptionKey: "map.catalog.flight_airspaces.description",
                descriptionFallback: "Referenční letecké prostory a jejich omezení.",
                groupId: "flight",
                role: "reference",
                providerId: "sim.flight-data",
                providerLayerIds: ["flight.airspaces"],
                providerSourceIds: ["flight_reference"],
                icon: "square.3.layers.3d",
                styleProfile: "flight-reference-airspaces-v1",
                maxFeatures: 200
            ),
            nativeFeatureLayer(
                layerId: "flight.reference.uas_geozones",
                labelKey: "map.catalog.flight_uas_geozones.label",
                labelFallback: "UAS zóny",
                descriptionKey: "map.catalog.flight_uas_geozones.description",
                descriptionFallback: "Referenční UAS geozóny ze SIM flight-data.",
                groupId: "flight",
                role: "reference",
                providerId: "sim.flight-data",
                providerLayerIds: ["flight.uas_geozones"],
                providerSourceIds: ["flight_reference"],
                icon: "drone",
                styleProfile: "flight-reference-uas-geozones-v1",
                maxFeatures: 200
            ),
            nativeFeatureLayer(
                layerId: "flight.airspace.activation",
                labelKey: "map.catalog.flight_airspace_activation.label",
                labelFallback: "Aktivace prostorů",
                descriptionKey: "map.catalog.flight_airspace_activation.description",
                descriptionFallback: "Aktuální aktivace leteckých prostorů, pokud ji COP/SIM publikuje.",
                groupId: "flight",
                role: "overlay",
                providerId: "sim.flight-data",
                providerLayerIds: ["flight.airspace_activation"],
                providerSourceIds: ["flight_reference"],
                icon: "airplane.departure",
                styleProfile: "flight-airspace-activation-v1",
                maxFeatures: 200
            ),
            MapLayerDefinition(
                layerId: "flight.sim.tracks",
                label: CSMLocalization.text("map.catalog.flight_sim.label", fallback: "Simulace"),
                description: CSMLocalization.text("map.catalog.flight_sim.description", fallback: "Simulovaná letecká situace ze SIM track streamu."),
                groupId: "flight",
                role: "primary",
                audience: "public",
                kind: "track_stream",
                defaultVisible: true,
                selectable: true,
                icon: "airplane.circle",
                minZoom: 4,
                maxZoom: 18,
                refreshSeconds: 5,
                cacheTtlSeconds: 5,
                styleProfile: "sim-air-track-v1",
                query: MapLayerQuery(
                    mode: "stream",
                    providerId: "cop.tracks",
                    streamId: "cop.live",
                    maxFeatures: 500
                ),
                provenance: MapLayerProvenance(sourceIds: ["sim.air-situation"])
            ),
            nativeFeatureLayer(
                layerId: "partner.tak.mobile",
                labelKey: "map.catalog.partner_tak_mobile.label",
                labelFallback: "Partnerské jednotky",
                descriptionKey: "map.catalog.partner_tak_mobile.description",
                descriptionFallback: "Partnerské mobilní TAK prvky dostupné jen pro oprávněné role.",
                groupId: "operations",
                audience: "partner",
                providerId: "sim.tak-gateway",
                providerLayerIds: ["mobile"],
                providerSourceIds: ["tak_gateway"],
                icon: "person.2.wave.2.fill",
                styleProfile: "partner-tak-mobile-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "partner.tak.ground",
                labelKey: "map.catalog.partner_tak_ground.label",
                labelFallback: "Partnerské body",
                descriptionKey: "map.catalog.partner_tak_ground.description",
                descriptionFallback: "Partnerské pozemní TAK body dostupné jen pro oprávněné role.",
                groupId: "operations",
                audience: "partner",
                providerId: "sim.tak-gateway",
                providerLayerIds: ["ground"],
                providerSourceIds: ["tak_gateway"],
                icon: "mappin.and.ellipse",
                styleProfile: "partner-tak-ground-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "partner.tak.traffic",
                labelKey: "map.catalog.partner_tak_traffic.label",
                labelFallback: "Partnerský provoz",
                descriptionKey: "map.catalog.partner_tak_traffic.description",
                descriptionFallback: "Partnerské TAK dopravní prvky dostupné jen pro oprávněné role.",
                groupId: "traffic",
                audience: "partner",
                providerId: "sim.tak-gateway",
                providerLayerIds: ["traffic"],
                providerSourceIds: ["tak_gateway"],
                icon: "car.2.fill",
                styleProfile: "partner-tak-traffic-v1",
                maxFeatures: 250
            ),
            nativeFeatureLayer(
                layerId: "diagnostic.mobile.coverage",
                labelKey: "map.catalog.diagnostic_mobile_coverage.label",
                labelFallback: "Technický odhad pokrytí",
                descriptionKey: "map.catalog.diagnostic_mobile_coverage.description",
                descriptionFallback: "Diagnostická vrstva coverage modelu. Nepatří do veřejných výstrah.",
                groupId: "diagnostics",
                audience: "diagnostic",
                kind: "vector_features",
                providerLayerIds: ["mobile_coverage"],
                providerSourceIds: ["mobile_coverage_model"],
                icon: "waveform.path.ecg.rectangle",
                styleProfile: "diagnostic-mobile-coverage-v1",
                maxFeatures: 300
            ),
            nativeFeatureLayer(
                layerId: "diagnostic.mobile.ctu_measurements",
                labelKey: "map.catalog.diagnostic_mobile_ctu.label",
                labelFallback: "ČTÚ měření",
                descriptionKey: "map.catalog.diagnostic_mobile_ctu.description",
                descriptionFallback: "Diagnostická ČTÚ měření pro kvalitu mobilních zdrojů.",
                groupId: "diagnostics",
                audience: "diagnostic",
                selectable: false,
                providerLayerIds: ["mobile"],
                providerSourceIds: ["ctu_nettest"],
                icon: "dot.radiowaves.forward",
                styleProfile: "diagnostic-mobile-ctu-v1",
                maxFeatures: 300
            ),
            MapLayerDefinition(
                layerId: "field.radio.planning",
                label: CSMLocalization.text("map.catalog.radio_planning.label", fallback: "Rádiový plán"),
                description: CSMLocalization.text("map.catalog.radio_planning.description", fallback: "Odhad line-of-sight spojení, dosahu a hraničních rádiových vazeb z aktuální polohy."),
                groupId: "communications",
                role: "analysis",
                audience: "operator",
                kind: "local_analysis",
                defaultVisible: false,
                selectable: true,
                icon: "dot.radiowaves.left.and.right",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: nil,
                cacheTtlSeconds: nil,
                styleProfile: "field-radio-planning-v1",
                provenance: MapLayerProvenance(
                    sourceIds: ["device.location", "cop.visible-map-state"],
                    technicalInputs: [
                        "device.current_location",
                        "cop.objects",
                        "cop.community_reports",
                        "cop.map_features"
                    ]
                )
            ),
            MapLayerDefinition(
                layerId: "offline.map",
                label: CSMLocalization.text("map.catalog.offline_pack.label", fallback: "Offline mapový balíček"),
                description: CSMLocalization.text("map.catalog.offline_pack.description", fallback: "Uložené dlaždice a oblasti pro práci bez signálu."),
                groupId: "offline",
                role: "reference",
                audience: "operator",
                kind: "raster_tiles",
                defaultVisible: true,
                selectable: true,
                icon: "externaldrive.badge.checkmark",
                minZoom: nil,
                maxZoom: nil,
                refreshSeconds: nil,
                cacheTtlSeconds: nil,
                styleProfile: "offline-tile-cache"
            )
        ]
    )

    private static func nativeFeatureLayer(
        layerId: String,
        labelKey: String,
        labelFallback: String,
        descriptionKey: String,
        descriptionFallback: String,
        groupId: String,
        role: String = "overlay",
        audience: String? = "public",
        kind: String = "vector_features",
        defaultVisible: Bool = false,
        selectable: Bool = true,
        providerId: String = "sim.situation-data",
        providerLayerIds: [String],
        providerSourceIds: [String] = [],
        categoryIds: [String] = [],
        icon: String,
        minZoom: Double? = 4,
        maxZoom: Double? = 18,
        refreshSeconds: Int? = 300,
        cacheTtlSeconds: Int? = 900,
        styleProfile: String,
        maxFeatures: Int? = 250
    ) -> MapLayerDefinition {
        MapLayerDefinition(
            layerId: layerId,
            label: CSMLocalization.text(labelKey, fallback: labelFallback),
            description: CSMLocalization.text(descriptionKey, fallback: descriptionFallback),
            groupId: groupId,
            role: role,
            audience: audience,
            kind: kind,
            defaultVisible: defaultVisible,
            selectable: selectable,
            icon: icon,
            minZoom: minZoom,
            maxZoom: maxZoom,
            refreshSeconds: refreshSeconds,
            cacheTtlSeconds: cacheTtlSeconds,
            styleProfile: styleProfile,
            query: MapLayerQuery(
                mode: "bbox",
                providerId: providerId,
                streamId: "features",
                providerLayerIds: providerLayerIds,
                providerSourceIds: providerSourceIds,
                categoryIds: categoryIds,
                maxFeatures: maxFeatures
            ),
            provenance: MapLayerProvenance(
                sourceIds: providerSourceIds.map { "\(providerId):\($0)" }
            )
        )
    }
}

struct MapLayerGroup: Codable, Identifiable, Equatable, Hashable, Sendable {
    var groupId: String
    var label: String
    var icon: String?
    var order: Int?

    var id: String { groupId }
}

struct MapLayerDefinition: Codable, Identifiable, Equatable, Hashable, Sendable {
    var layerId: String
    var label: String
    var description: String?
    var groupId: String
    var role: String
    var audience: String?
    var kind: String
    var defaultVisible: Bool
    var selectable: Bool
    var enabled: Bool?
    var availability: String?
    var disabledReason: String?
    var icon: String?
    var minZoom: Double?
    var maxZoom: Double?
    var refreshSeconds: Int?
    var cacheTtlSeconds: Int?
    var styleProfile: String?
    var query: MapLayerQuery?
    var filters: [MapLayerFilter]
    var provenance: MapLayerProvenance?
    var legal: MapLayerLegal?

    var id: String { layerId }

    enum CodingKeys: String, CodingKey {
        case layerId
        case label
        case description
        case groupId
        case role
        case audience
        case kind
        case defaultVisible
        case selectable
        case enabled
        case availability
        case disabledReason
        case icon
        case minZoom
        case maxZoom
        case refreshSeconds
        case cacheTtlSeconds
        case styleProfile
        case query
        case filters
        case provenance
        case legal
    }

    init(
        layerId: String,
        label: String,
        description: String?,
        groupId: String,
        role: String,
        audience: String?,
        kind: String,
        defaultVisible: Bool,
        selectable: Bool,
        enabled: Bool? = nil,
        availability: String? = nil,
        disabledReason: String? = nil,
        icon: String?,
        minZoom: Double?,
        maxZoom: Double?,
        refreshSeconds: Int?,
        cacheTtlSeconds: Int?,
        styleProfile: String?,
        query: MapLayerQuery? = nil,
        filters: [MapLayerFilter] = [],
        provenance: MapLayerProvenance? = nil,
        legal: MapLayerLegal? = nil
    ) {
        self.layerId = layerId
        self.label = label
        self.description = description
        self.groupId = groupId
        self.role = role
        self.audience = audience
        self.kind = kind
        self.defaultVisible = defaultVisible
        self.selectable = selectable
        self.enabled = enabled
        self.availability = availability
        self.disabledReason = disabledReason
        self.icon = icon
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.refreshSeconds = refreshSeconds
        self.cacheTtlSeconds = cacheTtlSeconds
        self.styleProfile = styleProfile
        self.query = query
        self.filters = filters
        self.provenance = provenance
        self.legal = legal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layerId = try container.decode(String.self, forKey: .layerId)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? layerId
        description = try container.decodeIfPresent(String.self, forKey: .description)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId) ?? "other"
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "overlay"
        audience = try container.decodeIfPresent(String.self, forKey: .audience)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "vector_features"
        defaultVisible = try container.decodeIfPresent(Bool.self, forKey: .defaultVisible) ?? false
        selectable = try container.decodeIfPresent(Bool.self, forKey: .selectable) ?? true
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        availability = try container.decodeIfPresent(String.self, forKey: .availability)
        disabledReason = try container.decodeIfPresent(String.self, forKey: .disabledReason)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        minZoom = try container.decodeIfPresent(Double.self, forKey: .minZoom)
        maxZoom = try container.decodeIfPresent(Double.self, forKey: .maxZoom)
        refreshSeconds = try container.decodeIfPresent(Int.self, forKey: .refreshSeconds)
        cacheTtlSeconds = try container.decodeIfPresent(Int.self, forKey: .cacheTtlSeconds)
        styleProfile = try container.decodeIfPresent(String.self, forKey: .styleProfile)
        query = try container.decodeIfPresent(MapLayerQuery.self, forKey: .query)
        filters = try container.decodeIfPresent([MapLayerFilter].self, forKey: .filters) ?? []
        provenance = try container.decodeIfPresent(MapLayerProvenance.self, forKey: .provenance)
        legal = try container.decodeIfPresent(MapLayerLegal.self, forKey: .legal)
    }

    var isAvailableInStandardMapUI: Bool {
        guard selectable else { return false }
        guard enabled != false else { return false }
        guard Self.normalizedToken(availability) != "disabled" else { return false }
        guard Self.normalizedToken(audience) != "diagnostic" else { return false }
        guard Self.normalizedToken(role) != "diagnostic" else { return false }
        return true
    }

    var isDisabledByCatalog: Bool {
        enabled == false || Self.normalizedToken(availability) == "disabled"
    }

    private static func normalizedToken(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }
}

struct MapLayerQuery: Codable, Equatable, Hashable, Sendable {
    var mode: String
    var providerId: String
    var streamId: String
    var providerLayerIds: [String]
    var providerSourceIds: [String]
    var categoryIds: [String]
    var maxFeatures: Int?

    enum CodingKeys: String, CodingKey {
        case mode
        case providerId
        case streamId
        case providerLayerIds
        case providerSourceIds
        case categoryIds
        case maxFeatures
    }

    init(
        mode: String,
        providerId: String,
        streamId: String,
        providerLayerIds: [String] = [],
        providerSourceIds: [String] = [],
        categoryIds: [String] = [],
        maxFeatures: Int? = nil
    ) {
        self.mode = mode
        self.providerId = providerId
        self.streamId = streamId
        self.providerLayerIds = providerLayerIds
        self.providerSourceIds = providerSourceIds
        self.categoryIds = categoryIds
        self.maxFeatures = maxFeatures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "bbox"
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId) ?? "cop"
        streamId = try container.decodeIfPresent(String.self, forKey: .streamId) ?? "features"
        providerLayerIds = try container.decodeIfPresent([String].self, forKey: .providerLayerIds) ?? []
        providerSourceIds = try container.decodeIfPresent([String].self, forKey: .providerSourceIds) ?? []
        categoryIds = try container.decodeIfPresent([String].self, forKey: .categoryIds) ?? []
        maxFeatures = try container.decodeIfPresent(Int.self, forKey: .maxFeatures)
    }
}

struct MapLayerFilter: Codable, Equatable, Hashable, Sendable {
    var filterId: String
    var label: String
    var type: String
    var values: [String]
    var defaultValue: CSMJSONValue?

    enum CodingKeys: String, CodingKey {
        case filterId
        case label
        case type
        case values
        case defaultValue
    }

    init(
        filterId: String,
        label: String,
        type: String,
        values: [String] = [],
        defaultValue: CSMJSONValue? = nil
    ) {
        self.filterId = filterId
        self.label = label
        self.type = type
        self.values = values
        self.defaultValue = defaultValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filterId = try container.decode(String.self, forKey: .filterId)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? filterId
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "toggle"
        values = try container.decodeIfPresent([String].self, forKey: .values) ?? []
        defaultValue = try container.decodeIfPresent(CSMJSONValue.self, forKey: .defaultValue)
    }
}

struct MapLayerProvenance: Codable, Equatable, Hashable, Sendable {
    var sourceIds: [String]
    var technicalInputs: [String]

    enum CodingKeys: String, CodingKey {
        case sourceIds
        case technicalInputs
    }

    init(sourceIds: [String] = [], technicalInputs: [String] = []) {
        self.sourceIds = sourceIds
        self.technicalInputs = technicalInputs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceIds = try container.decodeIfPresent([String].self, forKey: .sourceIds) ?? []
        technicalInputs = try container.decodeIfPresent([String].self, forKey: .technicalInputs) ?? []
    }
}

struct MapLayerLegal: Codable, Equatable, Hashable, Sendable {
    var attribution: String?
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case attribution
        case notes
    }

    init(attribution: String? = nil, notes: [String] = []) {
        self.attribution = attribution
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attribution = try container.decodeIfPresent(String.self, forKey: .attribution)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

struct MapFeatureBoundingBox: Codable, Equatable, Hashable, Sendable {
    var west: Double
    var south: Double
    var east: Double
    var north: Double

    enum CodingKeys: String, CodingKey {
        case west
        case south
        case east
        case north
    }

    var asArray: [Double] { [west, south, east, north] }

    init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west
        self.south = south
        self.east = east
        self.north = north
    }

    init(_ region: MapViewRegionState) {
        let halfLatitude = region.latitudeDelta / 2
        let halfLongitude = region.longitudeDelta / 2
        self.init(
            west: max(-180, region.centerLon - halfLongitude),
            south: max(-85, region.centerLat - halfLatitude),
            east: min(180, region.centerLon + halfLongitude),
            north: min(85, region.centerLat + halfLatitude)
        )
    }

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            west = try array.decode(Double.self)
            south = try array.decode(Double.self)
            east = try array.decode(Double.self)
            north = try array.decode(Double.self)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        west = try container.decode(Double.self, forKey: .west)
        south = try container.decode(Double.self, forKey: .south)
        east = try container.decode(Double.self, forKey: .east)
        north = try container.decode(Double.self, forKey: .north)
    }
}

struct MapFeatureQueryRequest: Codable, Equatable, Sendable {
    var bbox: MapFeatureBoundingBox
    var layerIds: [String]
    var filters: [String: [String: CSMJSONValue]]
    var includeDiagnostics: Bool
    var includePartner: Bool
    var limit: Int
    var zoom: Double?

    enum CodingKeys: String, CodingKey {
        case bbox
        case layerIds
        case filters
        case includeDiagnostics
        case includePartner
        case limit
        case zoom
    }

    init(
        bbox: MapFeatureBoundingBox,
        layerIds: [String],
        filters: [String: [String: CSMJSONValue]] = [:],
        includeDiagnostics: Bool = false,
        includePartner: Bool = false,
        limit: Int = 250,
        zoom: Double? = nil
    ) {
        self.bbox = bbox
        self.layerIds = MapDisplayProfile.normalizedLayerIds(layerIds)
        self.filters = filters
        self.includeDiagnostics = includeDiagnostics
        self.includePartner = includePartner
        self.limit = limit
        self.zoom = zoom
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bbox.asArray, forKey: .bbox)
        try container.encode(layerIds, forKey: .layerIds)
        try container.encode(filters, forKey: .filters)
        try container.encode(includeDiagnostics, forKey: .includeDiagnostics)
        try container.encode(includePartner, forKey: .includePartner)
        try container.encode(limit, forKey: .limit)
        try container.encodeIfPresent(zoom, forKey: .zoom)
    }
}

struct MapFeatureQueryResponse: Codable, Equatable, Sendable {
    var contractVersion: String
    var generatedAt: Date
    var query: MapFeatureQueryEcho
    var situation: MapFeatureCollection?
    var safety: MapFeatureCollection?
    var flight: MapFeatureCollection?
    var community: MapFeatureCollection?
    var missionArena: MapFeatureCollection?
    var tak: MapFeatureCollection?
    var summary: MapFeatureQuerySummary
    var warnings: [String]

    var allFeatures: [MapFeature] {
        [
            situation?.features ?? [],
            safety?.features ?? [],
            flight?.features ?? [],
            community?.features ?? [],
            missionArena?.features ?? [],
            tak?.features ?? []
        ].flatMap { $0 }
    }

    var allWarningTexts: [String] {
        warnings + [
            situation?.warnings ?? [],
            safety?.warnings ?? [],
            flight?.warnings ?? [],
            community?.warnings ?? [],
            missionArena?.warnings ?? [],
            tak?.warnings ?? []
        ].flatMap { $0 }
    }
}

struct MapFeatureQueryEcho: Codable, Equatable, Sendable {
    var bbox: MapFeatureBoundingBox
    var layerIds: [String]
    var limit: Int
}

struct MapFeatureQuerySummary: Codable, Equatable, Sendable {
    var featureCount: Int
    var layerCount: Int
    var warningCount: Int
}

struct MapFeatureCollection: Codable, Equatable, Sendable {
    var contractVersion: String?
    var generatedAt: Date?
    var type: String
    var features: [MapFeature]
    var summary: MapFeatureCollectionSummary?
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case generatedAt
        case type
        case features
        case summary
        case warnings
    }

    init(
        contractVersion: String? = nil,
        generatedAt: Date? = nil,
        type: String = "FeatureCollection",
        features: [MapFeature],
        summary: MapFeatureCollectionSummary? = nil,
        warnings: [String] = []
    ) {
        self.contractVersion = contractVersion
        self.generatedAt = generatedAt
        self.type = type
        self.features = features
        self.summary = summary
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "FeatureCollection"
        features = try container.decodeIfPresent([MapFeature].self, forKey: .features) ?? []
        summary = try container.decodeIfPresent(MapFeatureCollectionSummary.self, forKey: .summary)
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

struct MapFeatureCollectionSummary: Codable, Equatable, Sendable {
    var featureCount: Int
    var layerCount: Int?
    var warningCount: Int?
}

struct MapFeature: Codable, Equatable, Identifiable, Sendable {
    var id: String?
    var type: String
    var geometry: MapFeatureGeometry
    var properties: MapFeatureProperties

    var stableId: String {
        id ?? properties.featureId
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case geometry
        case properties
    }

    init(
        id: String?,
        type: String = "Feature",
        geometry: MapFeatureGeometry,
        properties: MapFeatureProperties
    ) {
        self.id = id
        self.type = type
        self.geometry = geometry
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringId = try? container.decodeIfPresent(String.self, forKey: .id) {
            id = stringId
        } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) {
            id = String(intId)
        } else if let doubleId = try? container.decodeIfPresent(Double.self, forKey: .id) {
            id = String(doubleId)
        } else {
            id = nil
        }
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "Feature"
        geometry = try container.decode(MapFeatureGeometry.self, forKey: .geometry)
        properties = try container.decode(MapFeatureProperties.self, forKey: .properties)
    }
}

enum MapFeatureGeometry: Codable, Equatable, Sendable {
    case point([Double])
    case lineString([[Double]])
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    var geometryType: String {
        switch self {
        case .point: "Point"
        case .lineString: "LineString"
        case .polygon: "Polygon"
        case .multiPolygon: "MultiPolygon"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Point":
            self = .point(try container.decode([Double].self, forKey: .coordinates))
        case "LineString":
            self = .lineString(try container.decode([[Double]].self, forKey: .coordinates))
        case "Polygon":
            self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
        case "MultiPolygon":
            self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported map feature geometry type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(geometryType, forKey: .type)
        switch self {
        case .point(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        case .lineString(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        case .polygon(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        case .multiPolygon(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        }
    }
}

struct MapFeatureProperties: Codable, Equatable, Sendable {
    var featureId: String
    var layerId: String?
    var layer: String?
    var providerId: String?
    var providerLayerId: String?
    var sourceId: String?
    var sourceName: String?
    var category: String
    var label: String
    var observedAt: Date?
    var updatedAt: Date?
    var effectiveAt: Date?
    var expiresAt: Date?
    var validFrom: Date?
    var validUntil: Date?
    var stale: Bool?
    var confidence: Double?
    var severity: String?
    var status: String?
    var urgency: String?
    var certainty: String?
    var quality: String?
    var dataQuality: String?
    var description: String?
    var headline: String?
    var summary: String?
    var disclaimer: String?
    var recommendedAction: String?
    var typeCode: String?
    var sourceCode: String?
    var sourceSystem: String?
    var hazardType: String?
    var areaName: String?
    var affectedArea: String?
    var affectedAreas: [String]?
    var basis: [String]?
    var styleHint: String?
    var iconHint: String?
    var btsStatus: String?
    var operatorStatusAvailable: Bool?
    var metrics: [String: CSMJSONValue]?
    var tags: [String: CSMJSONValue]?
    var localized: [String: CSMJSONValue]?
    var rendering: [String: CSMJSONValue]?
    var providerProperties: [String: CSMJSONValue]?
    var legal: [String: CSMJSONValue]?

    enum CodingKeys: String, CodingKey {
        case featureId
        case layerId
        case layer
        case providerId
        case providerLayerId
        case sourceId
        case sourceName
        case category
        case label
        case observedAt
        case updatedAt
        case effectiveAt
        case expiresAt
        case validFrom
        case validUntil
        case stale
        case confidence
        case severity
        case status
        case urgency
        case certainty
        case quality
        case dataQuality
        case description
        case headline
        case summary
        case disclaimer
        case recommendedAction
        case typeCode
        case sourceCode
        case sourceSystem
        case hazardType
        case areaName
        case affectedArea
        case affectedAreas
        case basis
        case styleHint
        case iconHint
        case btsStatus
        case operatorStatusAvailable
        case metrics
        case tags
        case localized
        case rendering
        case providerProperties
        case legal
    }

    init(
        featureId: String,
        layerId: String?,
        layer: String?,
        providerId: String?,
        providerLayerId: String?,
        sourceId: String?,
        category: String,
        label: String,
        sourceName: String? = nil,
        observedAt: Date? = nil,
        updatedAt: Date? = nil,
        effectiveAt: Date? = nil,
        expiresAt: Date? = nil,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        stale: Bool? = nil,
        confidence: Double? = nil,
        severity: String? = nil,
        status: String? = nil,
        urgency: String? = nil,
        certainty: String? = nil,
        quality: String? = nil,
        dataQuality: String? = nil,
        description: String? = nil,
        headline: String? = nil,
        summary: String? = nil,
        disclaimer: String? = nil,
        recommendedAction: String? = nil,
        typeCode: String? = nil,
        sourceCode: String? = nil,
        sourceSystem: String? = nil,
        hazardType: String? = nil,
        areaName: String? = nil,
        affectedArea: String? = nil,
        affectedAreas: [String]? = nil,
        basis: [String]? = nil,
        styleHint: String? = nil,
        iconHint: String? = nil,
        btsStatus: String? = nil,
        operatorStatusAvailable: Bool? = nil,
        metrics: [String: CSMJSONValue]? = nil,
        tags: [String: CSMJSONValue]? = nil,
        localized: [String: CSMJSONValue]? = nil,
        rendering: [String: CSMJSONValue]? = nil,
        providerProperties: [String: CSMJSONValue]? = nil,
        legal: [String: CSMJSONValue]? = nil
    ) {
        self.featureId = featureId
        self.layerId = layerId
        self.layer = layer
        self.providerId = providerId
        self.providerLayerId = providerLayerId
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.category = category
        self.label = label
        self.observedAt = observedAt
        self.updatedAt = updatedAt
        self.effectiveAt = effectiveAt
        self.expiresAt = expiresAt
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.stale = stale
        self.confidence = confidence
        self.severity = severity
        self.status = status
        self.urgency = urgency
        self.certainty = certainty
        self.quality = quality
        self.dataQuality = dataQuality
        self.description = description
        self.headline = headline
        self.summary = summary
        self.disclaimer = disclaimer
        self.recommendedAction = recommendedAction
        self.typeCode = typeCode
        self.sourceCode = sourceCode
        self.sourceSystem = sourceSystem
        self.hazardType = hazardType
        self.areaName = areaName
        self.affectedArea = affectedArea
        self.affectedAreas = affectedAreas
        self.basis = basis
        self.styleHint = styleHint
        self.iconHint = iconHint
        self.btsStatus = btsStatus
        self.operatorStatusAvailable = operatorStatusAvailable
        self.metrics = metrics
        self.tags = tags
        self.localized = localized
        self.rendering = rendering
        self.providerProperties = providerProperties
        self.legal = legal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        featureId = try container.decodeIfPresent(String.self, forKey: .featureId)
            ?? container.decodeIfPresent(String.self, forKey: .layerId)
            ?? "feature"
        layerId = try container.decodeIfPresent(String.self, forKey: .layerId)
        layer = try container.decodeIfPresent(String.self, forKey: .layer)
        providerId = try container.decodeIfPresent(String.self, forKey: .providerId)
        providerLayerId = try container.decodeIfPresent(String.self, forKey: .providerLayerId)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId)
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "unknown"
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? featureId
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        effectiveAt = try container.decodeIfPresent(Date.self, forKey: .effectiveAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        validFrom = try container.decodeIfPresent(Date.self, forKey: .validFrom)
        validUntil = try container.decodeIfPresent(Date.self, forKey: .validUntil)
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale)
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        severity = try container.decodeIfPresent(String.self, forKey: .severity)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        urgency = try container.decodeIfPresent(String.self, forKey: .urgency)
        certainty = try container.decodeIfPresent(String.self, forKey: .certainty)
        quality = try container.decodeIfPresent(String.self, forKey: .quality)
        dataQuality = try container.decodeIfPresent(String.self, forKey: .dataQuality)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        disclaimer = try container.decodeIfPresent(String.self, forKey: .disclaimer)
        recommendedAction = try container.decodeIfPresent(String.self, forKey: .recommendedAction)
        typeCode = try container.decodeIfPresent(String.self, forKey: .typeCode)
        sourceCode = try container.decodeIfPresent(String.self, forKey: .sourceCode)
        sourceSystem = try container.decodeIfPresent(String.self, forKey: .sourceSystem)
        hazardType = try container.decodeIfPresent(String.self, forKey: .hazardType)
        areaName = try container.decodeIfPresent(String.self, forKey: .areaName)
        affectedArea = try container.decodeIfPresent(String.self, forKey: .affectedArea)
        affectedAreas = try container.decodeIfPresent([String].self, forKey: .affectedAreas)
        basis = try container.decodeIfPresent([String].self, forKey: .basis)
        styleHint = try container.decodeIfPresent(String.self, forKey: .styleHint)
        iconHint = try container.decodeIfPresent(String.self, forKey: .iconHint)
        btsStatus = try container.decodeIfPresent(String.self, forKey: .btsStatus)
        operatorStatusAvailable = try container.decodeIfPresent(Bool.self, forKey: .operatorStatusAvailable)
        metrics = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .metrics)
        tags = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .tags)
        localized = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .localized)
        rendering = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .rendering)
        providerProperties = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .providerProperties)
        legal = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .legal)
    }
}

extension MapFeatureProperties {
    var isWeatherWebcamFeature: Bool {
        let key = [
            layerId,
            layer,
            providerLayerId,
            sourceId,
            category
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        let normalizedKey = key
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")

        return normalizedKey.contains("public_weather_webcams") ||
            normalizedKey.contains("weather_webcams") ||
            normalizedKey.contains("weather_webcam") ||
            normalizedKey.contains("chmi_weather_webcams") ||
            normalizedKey.contains("webcam") ||
            weatherWebcamDetailURL != nil ||
            weatherWebcamSnapshotURL != nil
    }

    var weatherWebcamSnapshotURL: String? {
        weatherWebcamCameraStringValue("snapshotUrl", "snapshotURL")
    }

    var weatherWebcamDetailURL: String? {
        weatherWebcamCameraStringValue("detailUrl", "detailURL")
    }

    var weatherWebcamCameraLabel: String? {
        weatherWebcamCameraStringValue("label", "name", "title")
    }

    var isTransitVehicleFeature: Bool {
        let key = transitLayerKey
        if key.contains("transit_stops") || key.contains("public_transit_static") || key.contains("stop") {
            return false
        }
        return key.contains("public_traffic_transit") ||
            key.contains("traffic_transit") ||
            key.contains("gtfs_rt") ||
            transitVehicleId != nil ||
            transitDetailURL != nil
    }

    var transitDetailSourceId: String? {
        if let source = sourceId?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty {
            return source
        }
        return transitStringValue("sourceId", "providerSourceId", "feedId")
    }

    var transitDetailURL: String? {
        transitStringValue("detailUrl", "detailURL")
    }

    var transitVehicleId: String? {
        transitStringValue("vehicleId", "vehicle_id", "id")
    }

    var transitTripId: String? {
        transitStringValue("tripId", "trip_id")
    }

    var transitTransportMode: String? {
        transitStringValue("transportMode", "vehicleMode", "mode", "routeType")
    }

    var transitRouteShortName: String? {
        transitStringValue("routeShortName", "route_short_name", "route", "line", "lineName")
    }

    var transitDestination: String? {
        transitStringValue("destination", "headsign", "tripHeadsign")
    }

    var transitCurrentStatus: String? {
        transitStringValue("currentStatus", "status", "vehicleStatus")
    }

    var transitHeadingDeg: Double? {
        transitNumberValue("headingDeg", "heading", "bearing")
    }

    var transitDelaySeconds: Int? {
        transitNumberValue("delaySeconds", "delay", "delaySec").map { Int($0.rounded()) }
    }

    var transitRefreshSeconds: Int? {
        transitNumberValue("refreshSeconds", "refresh_sec", "ttlSeconds").map { Int($0.rounded()) }
    }

    var transitRouteTypeCode: Int? {
        transitNumberValue("routeTypeCode", "route_type", "routeType").map { Int($0.rounded()) }
    }

    var transitStableSelectionKey: String? {
        guard isTransitVehicleFeature else { return nil }
        let source = transitDetailSourceId ?? providerId ?? "cop"
        let vehicle = transitVehicleId ?? transitTripId ?? transitRouteShortName ?? featureId
        let mode = transitTransportMode ?? category
        return "traffic:vehicle:\(source):\(vehicle):\(mode)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var isRasterOverlayMetadataCarrier: Bool {
        let renderingMode = csmMapStringValue(rendering?["mode"])
        let renderingRole = csmMapStringValue(rendering?["geometryRole"])
        let renderingSuppressesFill = csmMapBoolValue(rendering?["doNotRenderGeometryFill"]) == true
        let providerRendering = csmMapObjectValue(providerProperties?["rendering"])
        let providerRenderingMode = csmMapStringValue(providerRendering?["mode"])
        let providerRenderAs = csmMapStringValue(providerProperties?["renderAs"])
        let tagRenderAs = csmMapStringValue(tags?["renderAs"])
        let tagGeometryRole = csmMapStringValue(tags?["geometryRole"])
        let layerKey = [layerId, layer, providerLayerId]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return renderingMode == "raster_overlay" ||
            providerRenderingMode == "raster_overlay" ||
            providerRenderAs == "raster_overlay" ||
            tagRenderAs == "raster_overlay" ||
            renderingRole == "raster_extent" ||
            tagGeometryRole == "raster_extent" ||
            renderingSuppressesFill ||
            csmMapObjectValue(providerProperties?["raster"]) != nil ||
            layerKey.contains("weather_radar") ||
            layerKey.contains("radar_reflectivity") ||
            layerKey.contains("radar_precipitation") ||
            layerKey.contains("radar_nowcast") ||
            layerKey.contains("thunderstorm_risk")
    }

    private var weatherWebcamCameraProperties: [String: CSMJSONValue]? {
        csmMapObjectValue(providerProperties?["camera"])
    }

    private var transitProviderProperties: [String: CSMJSONValue]? {
        csmMapObjectValue(providerProperties?["transit"]) ??
            csmMapObjectValue(tags?["transit"]) ??
            csmMapObjectValue(metrics?["transit"])
    }

    private var transitLayerKey: String {
        [
            layerId,
            layer,
            providerLayerId,
            sourceId,
            category,
            transitTransportMode,
            transitRouteShortName,
            transitVehicleId
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
    }

    private func weatherWebcamCameraStringValue(_ keys: String...) -> String? {
        guard let camera = weatherWebcamCameraProperties else { return nil }
        for key in keys {
            if let value = csmMapRawStringValue(camera[key]) {
                return value
            }
        }
        return nil
    }

    private func transitStringValue(_ keys: String...) -> String? {
        for key in keys {
            if let value = csmMapRawStringValue(transitProviderProperties?[key]) ??
                csmMapRawStringValue(providerProperties?[key]) ??
                csmMapRawStringValue(tags?[key]) ??
                csmMapRawStringValue(metrics?[key]) {
                return value
            }
        }
        return nil
    }

    private func transitNumberValue(_ keys: String...) -> Double? {
        for key in keys {
            if let value = csmMapNumberValue(transitProviderProperties?[key]) ??
                csmMapNumberValue(providerProperties?[key]) ??
                csmMapNumberValue(tags?[key]) ??
                csmMapNumberValue(metrics?[key]) {
                return value
            }
        }
        return nil
    }

    func rasterOverlayRequest(featureId: String, geometry: MapFeatureGeometry) -> MapRasterOverlayRequest? {
        guard isRasterOverlayMetadataCarrier,
              let raster = csmMapObjectValue(providerProperties?["raster"]),
              let sourceURL = csmMapRawStringValue(raster["url"]),
              !sourceURL.isEmpty
        else { return nil }

        let bounds = csmMapBoundsValue(raster["boundsWgs84"]) ?? Self.bounds(for: geometry)
        guard let bounds else { return nil }

        let providerRendering = csmMapObjectValue(providerProperties?["rendering"])
        let opacity = Self.clampedOpacity(
            csmMapNumberValue(raster["opacity"]) ??
                csmMapNumberValue(rendering?["opacity"]) ??
                csmMapNumberValue(providerRendering?["opacity"]) ??
                0.58
        )

        return MapRasterOverlayRequest(
            id: featureId,
            featureId: featureId,
            layerId: layerId ?? layer,
            label: headline ?? label,
            sourceURL: sourceURL,
            bounds: bounds,
            opacity: opacity
        )
    }

    private func csmMapStringValue(_ value: CSMJSONValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func csmMapRawStringValue(_ value: CSMJSONValue?) -> String? {
        guard case .string(let string)? = value else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func csmMapBoolValue(_ value: CSMJSONValue?) -> Bool? {
        guard case .bool(let bool)? = value else { return nil }
        return bool
    }

    private func csmMapObjectValue(_ value: CSMJSONValue?) -> [String: CSMJSONValue]? {
        guard case .object(let object)? = value else { return nil }
        return object
    }

    private func csmMapNumberValue(_ value: CSMJSONValue?) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let string):
            return Double(string)
        default:
            return nil
        }
    }

    private func csmMapBoundsValue(_ value: CSMJSONValue?) -> MapFeatureBoundingBox? {
        guard case .array(let values)? = value,
              values.count >= 4,
              let west = csmMapNumberValue(values[0]),
              let south = csmMapNumberValue(values[1]),
              let east = csmMapNumberValue(values[2]),
              let north = csmMapNumberValue(values[3])
        else { return nil }
        return Self.validBounds(west: west, south: south, east: east, north: north)
    }

    private static func bounds(for geometry: MapFeatureGeometry) -> MapFeatureBoundingBox? {
        let points: [(lat: Double, lon: Double)]
        switch geometry {
        case .point(let coordinate):
            points = normalizedPoints([coordinate])
        case .lineString(let coordinates):
            points = normalizedPoints(coordinates)
        case .polygon(let rings):
            points = normalizedPoints(rings.flatMap { $0 })
        case .multiPolygon(let polygons):
            points = normalizedPoints(polygons.flatMap { polygon in polygon.flatMap { $0 } })
        }

        guard let minLat = points.map(\.lat).min(),
              let maxLat = points.map(\.lat).max(),
              let minLon = points.map(\.lon).min(),
              let maxLon = points.map(\.lon).max()
        else { return nil }
        return validBounds(west: minLon, south: minLat, east: maxLon, north: maxLat)
    }

    private static func normalizedPoints(_ coordinates: [[Double]]) -> [(lat: Double, lon: Double)] {
        coordinates.compactMap { coordinate in
            guard coordinate.count >= 2 else { return nil }
            let lon = coordinate[0]
            let lat = coordinate[1]
            guard (-180.0...180.0).contains(lon), (-85.0...85.0).contains(lat) else { return nil }
            return (lat, lon)
        }
    }

    private static func validBounds(west: Double, south: Double, east: Double, north: Double) -> MapFeatureBoundingBox? {
        guard west < east,
              south < north,
              (-180.0...180.0).contains(west),
              (-180.0...180.0).contains(east),
              (-85.0...85.0).contains(south),
              (-85.0...85.0).contains(north)
        else { return nil }
        return MapFeatureBoundingBox(west: west, south: south, east: east, north: north)
    }

    private static func clampedOpacity(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

extension MapFeature {
    var rasterOverlayRequest: MapRasterOverlayRequest? {
        properties.rasterOverlayRequest(featureId: stableId, geometry: geometry)
    }
}

/// Detail of a selected live public-transport vehicle.
///
/// The normal map query intentionally returns only live point features. Route
/// shape, stop table and service alerts are loaded lazily after tap through COP
/// so the iOS app stays aligned with the web COP map without calling SIM
/// directly or over-fetching routes for the whole viewport.
struct TransitVehicleDetail: Codable, Equatable, Sendable {
    var contractVersion: String?
    var featureId: String?
    var generatedAt: Date?
    var observedAt: Date?
    var vehicle: TransitVehicle?
    var trip: TransitTrip?
    var route: TransitRoute?
    var current: TransitVehicleCurrent?
    var routeShape: TransitRouteShape?
    var stopTimes: [TransitStopTime]
    var quality: TransitDetailQuality?
    var serviceAlerts: [TransitServiceAlert]
    var warnings: [String]

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case featureId
        case generatedAt
        case observedAt
        case vehicle
        case trip
        case route
        case current
        case routeShape
        case stopTimes
        case stops
        case quality
        case serviceAlerts
        case warnings
    }

    init(
        contractVersion: String? = nil,
        featureId: String? = nil,
        generatedAt: Date? = nil,
        observedAt: Date? = nil,
        vehicle: TransitVehicle? = nil,
        trip: TransitTrip? = nil,
        route: TransitRoute? = nil,
        current: TransitVehicleCurrent? = nil,
        routeShape: TransitRouteShape? = nil,
        stopTimes: [TransitStopTime] = [],
        quality: TransitDetailQuality? = nil,
        serviceAlerts: [TransitServiceAlert] = [],
        warnings: [String] = []
    ) {
        self.contractVersion = contractVersion
        self.featureId = featureId
        self.generatedAt = generatedAt
        self.observedAt = observedAt
        self.vehicle = vehicle
        self.trip = trip
        self.route = route
        self.current = current
        self.routeShape = routeShape
        self.stopTimes = stopTimes
        self.quality = quality
        self.serviceAlerts = serviceAlerts
        self.warnings = warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion)
        featureId = try container.decodeIfPresent(String.self, forKey: .featureId)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        vehicle = try container.decodeIfPresent(TransitVehicle.self, forKey: .vehicle)
        trip = try container.decodeIfPresent(TransitTrip.self, forKey: .trip)
        route = try container.decodeIfPresent(TransitRoute.self, forKey: .route)
        current = try container.decodeIfPresent(TransitVehicleCurrent.self, forKey: .current)
        routeShape = try container.decodeIfPresent(TransitRouteShape.self, forKey: .routeShape)
        let decodedStops = try container.decodeIfPresent([TransitStopTime].self, forKey: .stops) ?? []
        let decodedStopTimes = try container.decodeIfPresent([TransitStopTime].self, forKey: .stopTimes) ?? []
        stopTimes = Self.mergedStopTimes(decodedStops + decodedStopTimes)
        quality = try container.decodeIfPresent(TransitDetailQuality.self, forKey: .quality)
        serviceAlerts = try container.decodeIfPresent([TransitServiceAlert].self, forKey: .serviceAlerts) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    var displayRouteShape: TransitRouteShape? {
        routeShape ?? route?.shape
    }

    var displayTitle: String {
        TransitText.firstNonEmpty(
            vehicle?.routeShortName,
            route?.routeShortName,
            trip?.routeShortName,
            current?.display?.title,
            vehicle?.label,
            featureId
        ) ?? "Spoj"
    }

    var displaySubtitle: String? {
        TransitText.firstNonEmpty(
            vehicle?.destination,
            route?.destination,
            route?.headsign,
            trip?.destination,
            trip?.headsign,
            current?.display?.subtitle,
            vehicle?.operatorName
        )
    }

    private static func mergedStopTimes(_ stops: [TransitStopTime]) -> [TransitStopTime] {
        var seen = Set<String>()
        return stops.enumerated().filter { index, stop in
            let key = stop.stopId ??
                "\(stop.displayName):\(stop.stopSequence ?? stop.sequence ?? index)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        .map(\.element)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contractVersion, forKey: .contractVersion)
        try container.encodeIfPresent(featureId, forKey: .featureId)
        try container.encodeIfPresent(generatedAt, forKey: .generatedAt)
        try container.encodeIfPresent(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(vehicle, forKey: .vehicle)
        try container.encodeIfPresent(trip, forKey: .trip)
        try container.encodeIfPresent(route, forKey: .route)
        try container.encodeIfPresent(current, forKey: .current)
        try container.encodeIfPresent(routeShape, forKey: .routeShape)
        try container.encode(stopTimes, forKey: .stopTimes)
        try container.encodeIfPresent(quality, forKey: .quality)
        try container.encode(serviceAlerts, forKey: .serviceAlerts)
        try container.encode(warnings, forKey: .warnings)
    }
}

struct TransitVehicle: Codable, Equatable, Sendable {
    var id: String?
    var vehicleId: String?
    var label: String?
    var operatorName: String?
    var routeShortName: String?
    var destination: String?
    var transportMode: String?
    var currentStatus: String?
    var status: String?
    var delaySeconds: Int?
    var occupancyStatus: String?
    var occupancyPercent: Double?
    var currentStopSequence: Int?
    var observedAt: Date?
    var position: TransitVehiclePosition?

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleId
        case label
        case operatorName = "operator"
        case routeShortName
        case destination
        case transportMode
        case currentStatus
        case status
        case delaySeconds
        case occupancyStatus
        case occupancyPercent
        case currentStopSequence
        case observedAt
        case position
    }
}

struct TransitVehiclePosition: Codable, Equatable, Sendable {
    var lat: Double?
    var lon: Double?
    var speedMps: Double?
    var headingDeg: Double?
    var observedAt: Date?
}

struct TransitTrip: Codable, Equatable, Sendable {
    var tripId: String?
    var routeId: String?
    var routeShortName: String?
    var destination: String?
    var headsign: String?
    var status: String?
    var vehicleId: String?
}

struct TransitRoute: Codable, Equatable, Sendable {
    var routeId: String?
    var routeShortName: String?
    var routeLongName: String?
    var destination: String?
    var direction: String?
    var headsign: String?
    var transportMode: String?
    var shape: TransitRouteShape?
}

struct TransitVehicleCurrent: Codable, Equatable, Sendable {
    var status: String?
    var delaySeconds: Int?
    var speedMps: Double?
    var headingDeg: Double?
    var observedAt: Date?
    var display: TransitDisplay?
}

struct TransitDisplay: Codable, Equatable, Sendable {
    var title: String?
    var label: String?
    var subtitle: String?
    var badgeLabel: String?
    var primaryValue: String?
    var secondaryValue: String?
    var iconKey: String?
}

struct TransitStopTime: Codable, Equatable, Identifiable, Sendable {
    var sequence: Int?
    var stopSequence: Int?
    var stopId: String?
    var stopName: String?
    var name: String?
    var plannedArrival: Date? = nil
    var plannedDeparture: Date? = nil
    var scheduledArrival: Date?
    var scheduledDeparture: Date?
    var realtimeArrival: Date?
    var realtimeDeparture: Date?
    var arrivalTime: Date?
    var departureTime: Date?
    var delaySeconds: Int?
    var status: String?
    var relationToVehicle: String?
    var distanceMeters: Double? = nil
    var position: TransitStopPosition? = nil

    var id: String {
        [
            "\(sequence ?? stopSequence ?? 0)",
            stopId,
            stopName,
            name
        ]
            .compactMap { $0 }
            .joined(separator: ":")
    }

    var displayName: String {
        TransitText.firstNonEmpty(stopName, name, stopId) ?? "Zastávka"
    }
}

struct TransitStopPosition: Codable, Equatable, Sendable {
    var lat: Double?
    var lon: Double?

    var isRenderable: Bool {
        guard let lat, let lon else { return false }
        return (-85.0...85.0).contains(lat) && (-180.0...180.0).contains(lon)
    }
}

struct TransitDetailQuality: Codable, Equatable, Sendable {
    var staticModelAvailable: Bool?
    var vehiclePositionAvailable: Bool?
    var realtimeVehicleAvailable: Bool?
    var tripScheduleAvailable: Bool?
    var tripUpdateAvailable: Bool?
    var routeShapeAvailable: Bool?
    var shapeAvailable: Bool?
    var stale: Bool?
    var warnings: [String]?
}

struct TransitServiceAlert: Codable, Equatable, Sendable {
    var id: String?
    var headline: String?
    var summary: String?
    var description: String?
    var severity: String?
    var effect: String?

    var stableId: String {
        TransitText.firstNonEmpty(id, headline, summary, description) ?? UUID().uuidString
    }
}

struct TransitRouteShape: Codable, Equatable, Sendable {
    var type: String?
    var coordinates: [[Double]]
    var truncated: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case coordinates
        case truncated
    }

    init(type: String? = "LineString", coordinates: [[Double]], truncated: Bool? = nil) {
        self.type = type
        self.coordinates = coordinates
        self.truncated = truncated
    }

    init(from decoder: Decoder) throws {
        let value = try CSMJSONValue(from: decoder)
        guard let coordinates = Self.lineCoordinates(from: value) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Transit route shape does not contain a renderable line.")
            )
        }
        self.type = Self.stringValue(for: "type", in: value) ?? "LineString"
        self.coordinates = coordinates
        self.truncated = Self.boolValue(for: "truncated", in: value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type ?? "LineString", forKey: .type)
        try container.encode(coordinates, forKey: .coordinates)
        try container.encodeIfPresent(truncated, forKey: .truncated)
    }

    private static func lineCoordinates(from value: CSMJSONValue) -> [[Double]]? {
        if let directLine = directLineCoordinates(from: value) {
            return directLine
        }

        guard case .object(let object) = value else { return nil }
        if let coordinatesValue = object["coordinates"] {
            if let directLine = directLineCoordinates(from: coordinatesValue) {
                return directLine
            }
            if let multiLine = longestLineCoordinates(from: coordinatesValue) {
                return multiLine
            }
        }

        for key in ["geometry", "routeShape", "routeGeometry", "shape", "route", "lineString", "path", "points"] {
            if let nested = object[key], let line = lineCoordinates(from: nested) {
                return line
            }
        }
        return nil
    }

    private static func directLineCoordinates(from value: CSMJSONValue) -> [[Double]]? {
        guard case .array(let values) = value else { return nil }
        let coordinates = values.compactMap(Self.coordinate(from:))
        guard coordinates.count >= 2 else { return nil }
        return coordinates
    }

    private static func longestLineCoordinates(from value: CSMJSONValue) -> [[Double]]? {
        guard case .array(let values) = value else { return nil }
        return values
            .compactMap(lineCoordinates(from:))
            .max { left, right in left.count < right.count }
    }

    private static func coordinate(from value: CSMJSONValue) -> [Double]? {
        switch value {
        case .array(let coordinates):
            guard coordinates.count >= 2,
                  let lon = coordinates[0].finiteDouble,
                  let lat = coordinates[1].finiteDouble,
                  lon.isFinite,
                  lat.isFinite
            else { return nil }
            return [lon, lat]
        case .object(let object):
            guard let lat = object["lat"]?.finiteDouble ?? object["latitude"]?.finiteDouble,
                  let lon = object["lon"]?.finiteDouble ?? object["lng"]?.finiteDouble ?? object["longitude"]?.finiteDouble,
                  lon.isFinite,
                  lat.isFinite
            else { return nil }
            return [lon, lat]
        case .string, .number, .bool, .null:
            return nil
        }
    }

    private static func stringValue(for key: String, in value: CSMJSONValue) -> String? {
        guard case .object(let object) = value else { return nil }
        return object[key]?.trimmedStringValue
    }

    private static func boolValue(for key: String, in value: CSMJSONValue) -> Bool? {
        guard case .object(let object) = value,
              case .bool(let bool)? = object[key]
        else { return nil }
        return bool
    }
}

private enum TransitText {
    static func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }
}

struct MapRasterOverlayRequest: Identifiable, Equatable, Sendable {
    var id: String
    var featureId: String
    var layerId: String?
    var label: String
    var sourceURL: String
    var bounds: MapFeatureBoundingBox
    var opacity: Double
}

struct MapRasterOverlayImage: Identifiable, Equatable, Sendable {
    var request: MapRasterOverlayRequest
    var imageData: Data

    var id: String { request.id }
    var featureId: String { request.featureId }
    var layerId: String? { request.layerId }
    var label: String { request.label }
    var bounds: MapFeatureBoundingBox { request.bounds }
    var opacity: Double { request.opacity }
}

struct WeatherRadarFrameCatalog: Decodable, Equatable, Sendable {
    var product: String?
    var generatedAt: Date?
    var frames: [WeatherRadarFrame]

    enum CodingKeys: String, CodingKey {
        case product
        case generatedAt
        case frames
        case items
    }

    init(product: String? = nil, generatedAt: Date? = nil, frames: [WeatherRadarFrame] = []) {
        self.product = product
        self.generatedAt = generatedAt
        self.frames = frames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        product = try container.decodeIfPresent(String.self, forKey: .product)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt)
        frames = try container.decodeIfPresent([WeatherRadarFrame].self, forKey: .frames) ??
            container.decodeIfPresent([WeatherRadarFrame].self, forKey: .items) ??
            []
    }
}

struct WeatherRadarFrame: Decodable, Equatable, Identifiable, Sendable {
    var id: String
    var cleanURL: String
    var bounds: MapFeatureBoundingBox?
    var observedAt: Date?
    var validAt: Date?
    var label: String?
    var opacity: Double

    enum CodingKeys: String, CodingKey {
        case id
        case frameId
        case cleanURL = "cleanUrl"
        case url
        case bounds
        case boundsWgs84
        case observedAt
        case validAt
        case label
        case title
        case opacity
    }

    init(
        id: String,
        cleanURL: String,
        bounds: MapFeatureBoundingBox? = nil,
        observedAt: Date? = nil,
        validAt: Date? = nil,
        label: String? = nil,
        opacity: Double = 0.58
    ) {
        self.id = id
        self.cleanURL = cleanURL
        self.bounds = bounds
        self.observedAt = observedAt
        self.validAt = validAt
        self.label = label
        self.opacity = min(1, max(0, opacity))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cleanURL = try container.decodeIfPresent(String.self, forKey: .cleanURL) ??
            container.decodeIfPresent(String.self, forKey: .url) ??
            ""
        id = try container.decodeIfPresent(String.self, forKey: .id) ??
            container.decodeIfPresent(String.self, forKey: .frameId) ??
            cleanURL
        bounds = try container.decodeIfPresent(MapFeatureBoundingBox.self, forKey: .boundsWgs84) ??
            container.decodeIfPresent(MapFeatureBoundingBox.self, forKey: .bounds)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
        validAt = try container.decodeIfPresent(Date.self, forKey: .validAt)
        label = try container.decodeIfPresent(String.self, forKey: .label) ??
            container.decodeIfPresent(String.self, forKey: .title)
        opacity = min(1, max(0, try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 0.58))
    }

    func rasterOverlayRequest(defaultBounds: MapFeatureBoundingBox?) -> MapRasterOverlayRequest? {
        guard !cleanURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bounds = bounds ?? defaultBounds
        else { return nil }

        return MapRasterOverlayRequest(
            id: "weather-radar:\(id)",
            featureId: "weather-radar:\(id)",
            layerId: "public.weather.radar.timeline",
            label: displayLabel,
            sourceURL: cleanURL,
            bounds: bounds,
            opacity: opacity
        )
    }

    var displayLabel: String {
        if let label = label?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
            return label
        }
        if let observedAt {
            return observedAt.formatted(date: .omitted, time: .shortened)
        }
        return "Radar"
    }
}

enum SketchDrawingKind: String, Codable, Equatable, Sendable {
    case arrow
    case circle
    case line
    case marker
    case measurement
    case point
    case polygon
    case text
}

enum SketchDrawingVisibility: String, Codable, Equatable, Sendable {
    case `private`
    case group
    case event
    case `public`
}

enum SketchPaletteMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case civil
    case professional

    var id: String { rawValue }
}

enum SketchGeometry: Codable, Equatable, Sendable {
    case point([Double])
    case lineString([[Double]])
    case polygon([[[Double]]])

    enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    var geometryType: String {
        switch self {
        case .point: "Point"
        case .lineString: "LineString"
        case .polygon: "Polygon"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Point":
            self = .point(try container.decode([Double].self, forKey: .coordinates))
        case "LineString":
            self = .lineString(try container.decode([[Double]].self, forKey: .coordinates))
        case "Polygon":
            self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported sketch geometry type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(geometryType, forKey: .type)
        switch self {
        case .point(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        case .lineString(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        case .polygon(let coordinates):
            try container.encode(coordinates, forKey: .coordinates)
        }
    }
}

struct SketchDrawingStyle: Codable, Equatable, Sendable {
    var stroke: String?
    var fill: String?
    var opacity: Double?
    var lineWidth: Double?
}

struct SketchDrawingSymbol: Codable, Equatable, Sendable {
    var palette: String?
    var iconId: String?
    var sidc: String?
}

struct SketchDrawingCreateRequest: Codable, Equatable, Sendable {
    var kind: SketchDrawingKind
    var visibility: SketchDrawingVisibility
    var geometry: SketchGeometry
    var label: String?
    var groupId: String?
    var eventId: String?
    var style: SketchDrawingStyle?
    var symbol: SketchDrawingSymbol?
    var properties: [String: CSMJSONValue]?
    var locked: Bool?
}

struct SketchDrawingUpdateRequest: Codable, Equatable, Sendable {
    var geometry: SketchGeometry?
    var label: String?
    var style: SketchDrawingStyle?
    var symbol: SketchDrawingSymbol?
    var properties: [String: CSMJSONValue]?
    var locked: Bool?
}

struct SketchDrawingCollection: Decodable, Equatable, Sendable {
    var contractVersion: String?
    var type: String
    var generatedAt: Date?
    var features: [SketchDrawing]

    enum CodingKeys: String, CodingKey {
        case contractVersion
        case type
        case generatedAt
        case features
    }

    init(
        contractVersion: String? = "cop-sketch-drawings-v1",
        type: String = "FeatureCollection",
        generatedAt: Date? = nil,
        features: [SketchDrawing] = []
    ) {
        self.contractVersion = contractVersion
        self.type = type
        self.generatedAt = generatedAt
        self.features = features
    }
}

struct SketchPaletteCatalog: Decodable, Equatable, Sendable {
    var contractVersion: String?
    var generatedAt: Date?
    var modes: [String: SketchPaletteModeDefinition]

    init(
        contractVersion: String? = "cop-sketch-palettes-v1",
        generatedAt: Date? = nil,
        modes: [String: SketchPaletteModeDefinition] = [:]
    ) {
        self.contractVersion = contractVersion
        self.generatedAt = generatedAt
        self.modes = modes
    }

    var sortedModes: [(mode: SketchPaletteMode, definition: SketchPaletteModeDefinition)] {
        SketchPaletteMode.allCases.compactMap { mode in
            guard let definition = modes[mode.rawValue] else { return nil }
            return (mode, definition)
        }
    }

    var allSymbols: [SketchPaletteSymbol] {
        sortedModes.flatMap { mode, definition in
            definition.symbols.map { symbol in
                var next = symbol
                next.palette = mode
                return next
            }
        }
    }
}

struct SketchPaletteModeDefinition: Decodable, Equatable, Sendable {
    var label: String
    var symbols: [SketchPaletteSymbol]
}

struct SketchPaletteSymbol: Decodable, Equatable, Identifiable, Sendable {
    var iconId: String
    var label: String
    var description: String?
    var sidc: String?
    var palette: SketchPaletteMode?

    var id: String {
        [palette?.rawValue, iconId].compactMap { $0 }.joined(separator: ":")
    }
}

struct SketchDrawing: Decodable, Equatable, Identifiable, Sendable {
    var type: String
    var id: String
    var geometry: SketchGeometry
    var properties: SketchDrawingProperties

    init(
        type: String = "Feature",
        id: String,
        geometry: SketchGeometry,
        properties: SketchDrawingProperties
    ) {
        self.type = type
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }

    var drawingId: String { properties.drawingId ?? id }
}

struct SketchDrawingProperties: Decodable, Equatable, Sendable {
    var drawingId: String?
    var kind: SketchDrawingKind
    var visibility: SketchDrawingVisibility
    var label: String
    var groupId: String?
    var eventId: String?
    var ownerSubjectId: String?
    var ownerUsername: String?
    var ownerDisplayName: String?
    var style: SketchDrawingStyle?
    var symbol: SketchDrawingSymbol?
    var properties: [String: CSMJSONValue]
    var locked: Bool
    var revision: Int?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case drawingId
        case kind
        case visibility
        case label
        case groupId
        case eventId
        case ownerSubjectId
        case ownerUsername
        case ownerDisplayName
        case style
        case symbol
        case properties
        case locked
        case revision
        case createdAt
        case updatedAt
    }

    init(
        drawingId: String? = nil,
        kind: SketchDrawingKind = .line,
        visibility: SketchDrawingVisibility = .private,
        label: String = "",
        groupId: String? = nil,
        eventId: String? = nil,
        ownerSubjectId: String? = nil,
        ownerUsername: String? = nil,
        ownerDisplayName: String? = nil,
        style: SketchDrawingStyle? = nil,
        symbol: SketchDrawingSymbol? = nil,
        properties: [String: CSMJSONValue] = [:],
        locked: Bool = false,
        revision: Int? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.drawingId = drawingId
        self.kind = kind
        self.visibility = visibility
        self.label = label
        self.groupId = groupId
        self.eventId = eventId
        self.ownerSubjectId = ownerSubjectId
        self.ownerUsername = ownerUsername
        self.ownerDisplayName = ownerDisplayName
        self.style = style
        self.symbol = symbol
        self.properties = properties
        self.locked = locked
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drawingId = try container.decodeIfPresent(String.self, forKey: .drawingId)
        kind = try container.decodeIfPresent(SketchDrawingKind.self, forKey: .kind) ?? .line
        visibility = try container.decodeIfPresent(SketchDrawingVisibility.self, forKey: .visibility) ?? .private
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        eventId = try container.decodeIfPresent(String.self, forKey: .eventId)
        ownerSubjectId = try container.decodeIfPresent(String.self, forKey: .ownerSubjectId)
        ownerUsername = try container.decodeIfPresent(String.self, forKey: .ownerUsername)
        ownerDisplayName = try container.decodeIfPresent(String.self, forKey: .ownerDisplayName)
        style = try container.decodeIfPresent(SketchDrawingStyle.self, forKey: .style)
        symbol = try container.decodeIfPresent(SketchDrawingSymbol.self, forKey: .symbol)
        properties = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .properties) ?? [:]
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        revision = try container.decodeIfPresent(Int.self, forKey: .revision)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

enum CSMJSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: CSMJSONValue])
    case array([CSMJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: CSMJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([CSMJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension CSMJSONValue {
    static func encodable<Value: Encodable>(_ value: Value) throws -> CSMJSONValue {
        let data = try CSMJSONCoding.encoder.encode(value)
        return try CSMJSONCoding.decoder.decode(CSMJSONValue.self, from: data)
    }

    var finiteDouble: Double? {
        switch self {
        case .number(let value) where value.isFinite:
            return value
        case .string(let value):
            let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
            return number?.isFinite == true ? number : nil
        default:
            return nil
        }
    }

    var finiteInt: Int? {
        guard let value = finiteDouble,
              value >= Double(Int.min),
              value <= Double(Int.max)
        else {
            return nil
        }
        return Int(value.rounded())
    }

    var isEmptyQueryValue: Bool {
        switch self {
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let values):
            return values.filter { !$0.isEmptyQueryValue }.isEmpty
        case .object(let values):
            return values.filter { !$0.value.isEmptyQueryValue }.isEmpty
        case .null:
            return true
        case .number, .bool:
            return false
        }
    }

    var stringArrayValue: [String] {
        switch self {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [trimmed]
        case .array(let values):
            return MapDisplayProfile.normalizedLayerIds(values.flatMap(\.stringArrayValue))
        default:
            return []
        }
    }

    var trimmedStringValue: String? {
        guard case .string(let value) = self else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct MobileNativePolicy: Codable, Equatable, Sendable {
    var minimumAppVersion: String
    var offlineCacheTtlSeconds: Int
    var pushNotifications: String
    var requireBiometricUnlock: Bool
    var requireManagedDevice: Bool
    var relayTrustedSigningKeys: [CrisisRelayTrustedSigningKey]
    var relayRevokedSigningKeyIds: [String]

    init(
        minimumAppVersion: String,
        offlineCacheTtlSeconds: Int,
        pushNotifications: String,
        requireBiometricUnlock: Bool,
        requireManagedDevice: Bool,
        relayTrustedSigningKeys: [CrisisRelayTrustedSigningKey] = [],
        relayRevokedSigningKeyIds: [String] = []
    ) {
        self.minimumAppVersion = minimumAppVersion
        self.offlineCacheTtlSeconds = offlineCacheTtlSeconds
        self.pushNotifications = pushNotifications
        self.requireBiometricUnlock = requireBiometricUnlock
        self.requireManagedDevice = requireManagedDevice
        self.relayTrustedSigningKeys = relayTrustedSigningKeys
        self.relayRevokedSigningKeyIds = relayRevokedSigningKeyIds
    }

    enum CodingKeys: String, CodingKey {
        case minimumAppVersion
        case offlineCacheTtlSeconds
        case pushNotifications
        case requireBiometricUnlock
        case requireManagedDevice
        case relayTrustedSigningKeys
        case relayRevokedSigningKeyIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumAppVersion = try container.decode(String.self, forKey: .minimumAppVersion)
        offlineCacheTtlSeconds = try container.decode(Int.self, forKey: .offlineCacheTtlSeconds)
        pushNotifications = try container.decode(String.self, forKey: .pushNotifications)
        requireBiometricUnlock = try container.decode(Bool.self, forKey: .requireBiometricUnlock)
        requireManagedDevice = try container.decode(Bool.self, forKey: .requireManagedDevice)
        relayTrustedSigningKeys = try container.decodeIfPresent([CrisisRelayTrustedSigningKey].self, forKey: .relayTrustedSigningKeys) ?? []
        relayRevokedSigningKeyIds = try container.decodeIfPresent([String].self, forKey: .relayRevokedSigningKeyIds) ?? []
    }
}

struct OperatorProfilePreferences: Codable, Equatable, Hashable, Sendable {
    static let maxAvatarDataURLLength = 250_000

    var avatarDataUrl: String?
    var contactNote: String?
    var displayName: String?
    var email: String?
    var organization: String?
    var phone: String?
    var publicContact: Bool?
    var role: String?

    enum CodingKeys: String, CodingKey {
        case avatarDataUrl
        case contactNote
        case displayName
        case email
        case organization
        case phone
        case publicContact
        case role
    }

    init(
        avatarDataUrl: String? = nil,
        contactNote: String? = nil,
        displayName: String? = nil,
        email: String? = nil,
        organization: String? = nil,
        phone: String? = nil,
        publicContact: Bool? = nil,
        role: String? = nil
    ) {
        self.avatarDataUrl = Self.normalizedDataURL(avatarDataUrl)
        self.contactNote = Self.trimmed(contactNote, maxLength: 280)
        self.displayName = Self.trimmed(displayName, maxLength: 80)
        self.email = Self.trimmed(email, maxLength: 120)
        self.organization = Self.trimmed(organization, maxLength: 120)
        self.phone = Self.trimmed(phone, maxLength: 40)
        self.publicContact = publicContact
        self.role = Self.trimmed(role, maxLength: 80)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            avatarDataUrl: try container.decodeIfPresent(String.self, forKey: .avatarDataUrl),
            contactNote: try container.decodeIfPresent(String.self, forKey: .contactNote),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            email: try container.decodeIfPresent(String.self, forKey: .email),
            organization: try container.decodeIfPresent(String.self, forKey: .organization),
            phone: try container.decodeIfPresent(String.self, forKey: .phone),
            publicContact: try container.decodeIfPresent(Bool.self, forKey: .publicContact),
            role: try container.decodeIfPresent(String.self, forKey: .role)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(avatarDataUrl, forKey: .avatarDataUrl)
        try container.encodeIfPresent(contactNote, forKey: .contactNote)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(organization, forKey: .organization)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(publicContact, forKey: .publicContact)
        try container.encodeIfPresent(role, forKey: .role)
    }

    var normalized: OperatorProfilePreferences {
        OperatorProfilePreferences(
            avatarDataUrl: avatarDataUrl,
            contactNote: contactNote,
            displayName: displayName,
            email: email,
            organization: organization,
            phone: phone,
            publicContact: publicContact,
            role: role
        )
    }

    var isEmpty: Bool {
        avatarDataUrl == nil &&
            contactNote == nil &&
            displayName == nil &&
            email == nil &&
            organization == nil &&
            phone == nil &&
            publicContact == nil &&
            role == nil
    }

    var visibleFieldCount: Int {
        [
            avatarDataUrl,
            contactNote,
            displayName,
            email,
            organization,
            phone,
            role
        ].compactMap { $0 }.count + (publicContact == nil ? 0 : 1)
    }

    func mergedWithIdentity(actor: AuthenticatedActor?) -> OperatorProfilePreferences {
        OperatorProfilePreferences(
            avatarDataUrl: avatarDataUrl ?? actor?.picture,
            contactNote: contactNote,
            displayName: displayName ?? actor?.displayName,
            email: email ?? actor?.email,
            organization: organization,
            phone: phone,
            publicContact: publicContact,
            role: role
        )
    }

    private static func trimmed(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLength))
    }

    private static func normalizedDataURL(_ value: String?) -> String? {
        guard let value = trimmed(value, maxLength: maxAvatarDataURLLength),
              value.count <= maxAvatarDataURLLength,
              value.range(
                of: #"^data:image/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$"#,
                options: .regularExpression
              ) != nil
        else {
            return nil
        }
        return value
    }
}

struct UserDisplayPreferences: Codable, Equatable, Sendable {
    var values: [String: CSMJSONValue]

    static let empty = UserDisplayPreferences(values: [:])

    init(values: [String: CSMJSONValue] = [:]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        values = try container.decode([String: CSMJSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    var operatorProfile: OperatorProfilePreferences? {
        decode(OperatorProfilePreferences.self, from: values["operatorProfile"])
    }

    var alertRadiusKm: Double? {
        values["alertRadiusKm"]?.finiteDouble
    }

    var preferredHistorySeconds: Int? {
        values["trackHistoryWindowSeconds"]?.finiteInt
    }

    var mapCatalogLocale: String {
        Self.normalizedLocale(
            values["language"]?.trimmedStringValue ??
                values["locale"]?.trimmedStringValue ??
                values["mapLocale"]?.trimmedStringValue
        )
    }

    var catalogLayerIds: [String] {
        MapDisplayProfile.normalizedLayerIds(values["catalogLayerIds"]?.stringArrayValue ?? [])
    }

    var hasCatalogLayerSelection: Bool {
        values.keys.contains("catalogLayerIds")
    }

    var mapLayerFilters: [String: [String: CSMJSONValue]] {
        MapDisplayProfile.normalizedLayerFilters(
            decode([String: [String: CSMJSONValue]].self, from: values["mapLayerFilters"]) ?? [:]
        )
    }

    var preferredLayerIds: [String] {
        if hasCatalogLayerSelection {
            return catalogLayerIds
        }
        let candidates = [
            "safetyLayerIds",
            "situationLayerIds",
            "trackLayerIds"
        ]
        return MapDisplayProfile.normalizedLayerIds(candidates.flatMap { key in
            values[key]?.stringArrayValue ?? []
        })
    }

    func settingOperatorProfile(_ profile: OperatorProfilePreferences?) -> UserDisplayPreferences {
        var next = values
        guard let profile = profile?.normalized, !profile.isEmpty else {
            next.removeValue(forKey: "operatorProfile")
            return UserDisplayPreferences(values: next)
        }
        if let value = try? CSMJSONValue.encodable(profile) {
            next["operatorProfile"] = value
        }
        return UserDisplayPreferences(values: next)
    }

    func settingCatalogLayerIds(_ layerIds: [String]) -> UserDisplayPreferences {
        var next = values
        let normalizedIds = MapDisplayProfile.normalizedLayerIds(layerIds)
        next["catalogLayerIds"] = .array(normalizedIds.map(CSMJSONValue.string))
        return UserDisplayPreferences(values: next)
    }

    func settingMapLayerFilters(_ filters: [String: [String: CSMJSONValue]]) -> UserDisplayPreferences {
        var next = values
        let normalizedFilters = MapDisplayProfile.normalizedLayerFilters(filters)
        if normalizedFilters.isEmpty {
            next.removeValue(forKey: "mapLayerFilters")
        } else if let value = try? CSMJSONValue.encodable(normalizedFilters) {
            next["mapLayerFilters"] = value
        }
        return UserDisplayPreferences(values: next)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from value: CSMJSONValue?) -> Value? {
        guard let value,
              let data = try? CSMJSONCoding.encoder.encode(value)
        else {
            return nil
        }
        return try? CSMJSONCoding.decoder.decode(type, from: data)
    }

    private static func normalizedLocale(_ rawValue: String?) -> String {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        switch normalized {
        case "en", "en-us", "en-gb":
            return "en-US"
        case "cs", "cz", "cs-cz", "cs-sk":
            return "cs-CZ"
        default:
            return "cs-CZ"
        }
    }
}

struct UserPreferenceProfile: Codable, Equatable, Sendable {
    var actor: AuthenticatedActor
    var alertPreferences: [String: CSMJSONValue]
    var preferences: UserDisplayPreferences
    var updatedAt: Date?

    var mobileProfile: UserProfile {
        UserProfile(
            alertRadiusKm: preferences.alertRadiusKm ?? 1.0,
            preferredHistorySeconds: preferences.preferredHistorySeconds ?? 180,
            preferredLayerIds: preferences.preferredLayerIds,
            updatedAt: updatedAt,
            alertPreferences: alertPreferences,
            preferences: preferences
        )
    }
}

struct UserPreferenceUpdate: Codable, Equatable, Sendable {
    var alertPreferences: [String: CSMJSONValue]?
    var preferences: UserDisplayPreferences
}

struct UserProfile: Codable, Equatable, Sendable {
    var alertRadiusKm: Double
    var preferredHistorySeconds: Int
    var preferredLayerIds: [String]
    var updatedAt: Date?
    var alertPreferences: [String: CSMJSONValue]
    var preferences: UserDisplayPreferences

    var operatorProfile: OperatorProfilePreferences? {
        preferences.operatorProfile
    }

    enum CodingKeys: String, CodingKey {
        case alertRadiusKm
        case preferredHistorySeconds
        case preferredLayerIds
        case updatedAt
        case alertPreferences
        case preferences
    }

    init(
        alertRadiusKm: Double,
        preferredHistorySeconds: Int,
        preferredLayerIds: [String],
        updatedAt: Date?,
        alertPreferences: [String: CSMJSONValue] = [:],
        preferences: UserDisplayPreferences = .empty
    ) {
        self.alertRadiusKm = alertRadiusKm
        self.preferredHistorySeconds = preferredHistorySeconds
        self.preferredLayerIds = preferredLayerIds
        self.updatedAt = updatedAt
        self.alertPreferences = alertPreferences
        self.preferences = preferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nestedPreferences = try container.decodeIfPresent(UserDisplayPreferences.self, forKey: .preferences) ?? .empty
        let nestedAlertPreferences = try container.decodeIfPresent([String: CSMJSONValue].self, forKey: .alertPreferences) ?? [:]

        alertRadiusKm = try container.decodeIfPresent(Double.self, forKey: .alertRadiusKm) ??
            nestedPreferences.alertRadiusKm ??
            1.0
        preferredHistorySeconds = try container.decodeIfPresent(Int.self, forKey: .preferredHistorySeconds) ??
            nestedPreferences.preferredHistorySeconds ??
            180
        let topLevelLayerIds = try container.decodeIfPresent([String].self, forKey: .preferredLayerIds) ?? []
        preferredLayerIds = topLevelLayerIds.isEmpty ? nestedPreferences.preferredLayerIds : topLevelLayerIds
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        alertPreferences = nestedAlertPreferences
        preferences = nestedPreferences
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alertRadiusKm, forKey: .alertRadiusKm)
        try container.encode(preferredHistorySeconds, forKey: .preferredHistorySeconds)
        try container.encode(preferredLayerIds, forKey: .preferredLayerIds)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(alertPreferences, forKey: .alertPreferences)
        try container.encode(preferences, forKey: .preferences)
    }
}

struct MobileOfflineSnapshot: Codable, Equatable, Sendable {
    var alerts: [CopAlert]
    var cachePolicy: MobileCachePolicy
    var healthStatus: String
    var objects: [ObservedObject]
    var serverTimestamp: Date
    var snapshotId: String
    var sourceHealth: [SourceHealthItem]
    var sources: [String]
    var streamHealthStatus: String
    var trackHistory: [TrackHistory]

    enum CodingKeys: String, CodingKey {
        case alerts
        case cachePolicy
        case health
        case healthStatus
        case objects
        case serverTimestamp
        case snapshotId
        case sourceHealth
        case sources
        case streamHealth
        case streamHealthStatus
        case trackHistory
    }

    init(
        alerts: [CopAlert],
        cachePolicy: MobileCachePolicy,
        healthStatus: String,
        objects: [ObservedObject],
        serverTimestamp: Date,
        snapshotId: String,
        sourceHealth: [SourceHealthItem],
        sources: [String],
        streamHealthStatus: String,
        trackHistory: [TrackHistory]
    ) {
        self.alerts = alerts
        self.cachePolicy = cachePolicy
        self.healthStatus = healthStatus
        self.objects = objects
        self.serverTimestamp = serverTimestamp
        self.snapshotId = snapshotId
        self.sourceHealth = sourceHealth
        self.sources = sources
        self.streamHealthStatus = streamHealthStatus
        self.trackHistory = trackHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alerts = try container.decodeIfPresent([CopAlert].self, forKey: .alerts) ?? []
        cachePolicy = try container.decodeIfPresent(MobileCachePolicy.self, forKey: .cachePolicy) ?? .readOnlyDefault
        objects = try container.decodeIfPresent([ObservedObject].self, forKey: .objects) ?? []
        serverTimestamp = try container.decodeIfPresent(Date.self, forKey: .serverTimestamp) ?? .now
        snapshotId = try container.decodeIfPresent(String.self, forKey: .snapshotId) ?? UUID().uuidString
        sourceHealth = try container.decodeIfPresent([SourceHealthItem].self, forKey: .sourceHealth) ?? []
        trackHistory = try container.decodeIfPresent([TrackHistory].self, forKey: .trackHistory) ?? []

        healthStatus = try container.decodeIfPresent(String.self, forKey: .healthStatus)
            ?? container.decodeStatusObjectIfPresent(forKey: .health)
            ?? "unknown"

        streamHealthStatus = try container.decodeIfPresent(String.self, forKey: .streamHealthStatus)
            ?? container.decodeStatusObjectIfPresent(forKey: .streamHealth)
            ?? "unknown"

        if let stringSources = try? container.decode([String].self, forKey: .sources) {
            sources = stringSources
        } else {
            sources = (try? container.decode([SourceIdentity].self, forKey: .sources).map(\.sourceSystemId)) ?? []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(alerts, forKey: .alerts)
        try container.encode(cachePolicy, forKey: .cachePolicy)
        try container.encode(healthStatus, forKey: .healthStatus)
        try container.encode(objects, forKey: .objects)
        try container.encode(serverTimestamp, forKey: .serverTimestamp)
        try container.encode(snapshotId, forKey: .snapshotId)
        try container.encode(sourceHealth, forKey: .sourceHealth)
        try container.encode(sources, forKey: .sources)
        try container.encode(streamHealthStatus, forKey: .streamHealthStatus)
        try container.encode(trackHistory, forKey: .trackHistory)
    }

    /// Safety/public alert surfaces must not treat track lifecycle and source
    /// quality signals as user-facing warnings. Those signals belong in the
    /// source-quality diagnostics panel.
    var publicAlerts: [CopAlert] {
        alerts.filter(\.isPublicAlertSurfaceEligible)
    }

    var activePublicAlerts: [CopAlert] {
        alerts.filter { $0.status == .active && $0.isPublicAlertSurfaceEligible }
    }

    var dataQualityLifecycleSignals: [CopAlert] {
        alerts.filter(\.isDataQualityLifecycleSignal)
    }

    var activeDataQualityLifecycleSignals: [CopAlert] {
        alerts.filter { $0.status == .active && $0.isDataQualityLifecycleSignal }
    }
}

struct MobileCachePolicy: Codable, Equatable, Sendable {
    var apiResponses: String
    var maxHistoryPointsPerObject: Int
    var maxHistorySeconds: Int
    var mode: String
    var offlineCacheTtlSeconds: Int
    var recommendedStorage: String

    static let readOnlyDefault = MobileCachePolicy(
        apiResponses: "network-only",
        maxHistoryPointsPerObject: 120,
        maxHistorySeconds: 180,
        mode: "read-only",
        offlineCacheTtlSeconds: 900,
        recommendedStorage: "encrypted-device-storage"
    )
}

struct MessagingStatus: Codable, Equatable, Sendable {
    var chatAvailable: Bool
    var checkedAt: Date
    var contractVersion: String
    var enabled: Bool
    var providerId: String
    var serviceName: String
    var status: String
    var warnings: [String]
}

struct MessagingBootstrap: Codable, Equatable, Sendable {
    var accessToken: String?
    var refreshToken: String? = nil
    var chatAvailable: Bool
    var contractVersion: String
    var deviceId: String?
    var e2eeRequired: Bool
    var enabled: Bool
    var expiresInMs: Int? = nil
    var expiresAt: Date?
    var homeserverBaseUrl: URL?
    var providerId: String
    var serverName: String?
    var status: String
    var tokenAvailable: Bool
    var userId: String?
    var warnings: [String]
}

struct MobileDeviceRegistration: Codable, Equatable, Sendable {
    var deviceId: String
    var platform: String
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceModel: String
    var capabilities: [String]
    var push: MobilePushRegistration? = nil
    var posture: MobileDevicePosture? = nil
}

struct MobileDeviceRegistrationResponse: Codable, Equatable, Sendable {
    var deviceSessionId: String
    var pushTokenRegistered: Bool
    var policy: MobileNativePolicy
    var serverTimestamp: Date
}

struct MobilePushRegistration: Codable, Equatable, Sendable {
    var token: String?
    var environment: String
    var authorization: String
    var updatedAt: Date
}

struct CSMNotificationPreferences: Codable, Equatable, Hashable, Sendable {
    var directMessages: Bool
    var groupMessages: Bool
    var safetyAlerts: Bool
    var systemNotifications: Bool

    static let `default` = CSMNotificationPreferences(
        directMessages: true,
        groupMessages: true,
        safetyAlerts: true,
        systemNotifications: true
    )

    init(
        directMessages: Bool,
        groupMessages: Bool,
        safetyAlerts: Bool,
        systemNotifications: Bool
    ) {
        self.directMessages = directMessages
        self.groupMessages = groupMessages
        self.safetyAlerts = safetyAlerts
        self.systemNotifications = systemNotifications
    }

    init(categories: [String]) {
        directMessages = categories.contains("message.direct")
        groupMessages = categories.contains("message.group")
        safetyAlerts = categories.contains("safety.alert") || categories.contains("safety.area_update")
        systemNotifications = categories.contains("system.account") || categories.contains("system.delivery")
    }

    var categories: [String] {
        var result: [String] = []
        if directMessages {
            result.append("message.direct")
        }
        if groupMessages {
            result.append("message.group")
        }
        if safetyAlerts {
            result.append(contentsOf: ["safety.alert", "safety.area_update"])
        }
        if systemNotifications {
            result.append(contentsOf: ["system.account", "system.delivery"])
        }
        return result
    }
}

struct CSMNotificationSubscriptions: Codable, Equatable, Hashable, Sendable {
    var groupIds: [String]
    var areaIds: [String]

    static let empty = CSMNotificationSubscriptions(groupIds: [], areaIds: [])

    init(groupIds: [String], areaIds: [String]) {
        self.groupIds = Self.uniqueIdentifiers(groupIds)
        self.areaIds = Self.uniqueIdentifiers(areaIds)
    }

    func containsGroup(_ groupId: String) -> Bool {
        guard let groupId = Self.normalizedIdentifier(groupId) else { return false }
        return groupIds.contains(groupId)
    }

    func containsArea(_ areaId: String) -> Bool {
        guard let areaId = Self.normalizedIdentifier(areaId) else { return false }
        return areaIds.contains(areaId)
    }

    func settingGroup(_ groupId: String, enabled: Bool) -> CSMNotificationSubscriptions {
        guard let groupId = Self.normalizedIdentifier(groupId) else { return self }
        return CSMNotificationSubscriptions(
            groupIds: Self.settingIdentifier(groupId, enabled: enabled, in: groupIds),
            areaIds: areaIds
        )
    }

    func settingArea(_ areaId: String, enabled: Bool) -> CSMNotificationSubscriptions {
        guard let areaId = Self.normalizedIdentifier(areaId) else { return self }
        return CSMNotificationSubscriptions(
            groupIds: groupIds,
            areaIds: Self.settingIdentifier(areaId, enabled: enabled, in: areaIds)
        )
    }

    static func normalizedIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return nil }
        guard trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return trimmed
    }

    private static func settingIdentifier(_ id: String, enabled: Bool, in ids: [String]) -> [String] {
        let existing = uniqueIdentifiers(ids)
        if enabled {
            return existing.contains(id) ? existing : existing + [id]
        }
        return existing.filter { $0 != id }
    }

    private static func uniqueIdentifiers(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let normalized = normalizedIdentifier(value), !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return normalized
        }
    }
}

struct CSMMessagingDeviceRegistrationRequest: Codable, Equatable, Sendable {
    var apnsEnvironment: String
    var appBundleId: String
    var appInstanceId: String
    var capabilities: Capabilities
    var deviceToken: String
    var voipDeviceToken: String
    var locale: String
    var platform: String
    var preferences: Preferences
    var subscriptions: Subscriptions
    var timezone: String

    struct Capabilities: Codable, Equatable, Sendable {
        var criticalAlerts: Bool
        var e2ee: Bool
        var liveActivities: Bool
        var voip: Bool
    }

    struct Preferences: Codable, Equatable, Sendable {
        var categories: [String]
    }

    struct Subscriptions: Codable, Equatable, Sendable {
        var groupIds: [String]
        var areaIds: [String]
    }
}

struct MobileDeviceRegistrationTicketRequest: Codable, Equatable, Sendable {
    var appInstanceId: String
    var bundleId: String
}

struct MobileDeviceRegistrationTicketResponse: Codable, Equatable, Sendable {
    var contractVersion: String
    var expiresAt: Date
    var messagingBaseUrl: URL
    var ticket: String
}

struct CSMMessagingDeviceRegistrationResponse: Codable, Equatable, Sendable {
    var contractVersion: String?
    var providerId: String?
    var device: CSMMessagingRegisteredDevice
}

struct CSMMessagingRegisteredDevice: Codable, Equatable, Sendable {
    var deviceId: String
    var userId: String?
    var platform: String?
    var status: String?
    var locale: String?
    var timezone: String?
    var preferences: CSMMessagingDevicePreferences?
    var subscriptions: CSMMessagingDeviceSubscriptions?
}

struct CSMMessagingDevicePreferences: Codable, Equatable, Sendable {
    var categories: [String]
}

struct CSMMessagingDeviceSubscriptions: Codable, Equatable, Sendable {
    var groupIds: [String]
    var areaIds: [String]
}

struct MobileDevicePosture: Codable, Equatable, Sendable {
    var protectedDataAvailable: Bool
    var lowPowerModeEnabled: Bool
    var managedAppConfigurationPresent: Bool
    var managedDeviceRequired: Bool
    var remoteWipeRequested: Bool
    var biometryType: String
    var evaluatedAt: Date

    static let unknown = MobileDevicePosture(
        protectedDataAvailable: false,
        lowPowerModeEnabled: false,
        managedAppConfigurationPresent: false,
        managedDeviceRequired: false,
        remoteWipeRequested: false,
        biometryType: "unknown",
        evaluatedAt: .distantPast
    )
}

struct MobileManagedAppPolicy: Codable, Equatable, Sendable {
    var configurationPresent: Bool
    var requireManagedDeviceOverride: Bool?
    var remoteWipeRequested: Bool
    var relayDisabled: Bool
    var localAIDisabled: Bool
    var offlineTileCachingDisabled: Bool
    var securityExportDisabled: Bool
    var relayTrustedSigningKeys: [CrisisRelayTrustedSigningKey]
    var relayRevokedSigningKeyIds: [String]

    static let unmanaged = MobileManagedAppPolicy(
        configurationPresent: false,
        requireManagedDeviceOverride: nil,
        remoteWipeRequested: false,
        relayDisabled: false,
        localAIDisabled: false,
        offlineTileCachingDisabled: false,
        securityExportDisabled: false,
        relayTrustedSigningKeys: [],
        relayRevokedSigningKeyIds: []
    )

    func requiresManagedDevice(serverPolicy: MobileNativePolicy?) -> Bool {
        requireManagedDeviceOverride ?? serverPolicy?.requireManagedDevice ?? false
    }

    static func fromManagedConfiguration(_ configuration: [String: Any]?) -> MobileManagedAppPolicy {
        guard let configuration else { return .unmanaged }
        return MobileManagedAppPolicy(
            configurationPresent: true,
            requireManagedDeviceOverride: boolValue(configuration, keys: ["CSMRequireManagedDevice", "RequireManagedDevice"]),
            remoteWipeRequested: boolValue(configuration, keys: ["CSMRemoteWipeRequested", "RemoteWipeRequested"]) ?? false,
            relayDisabled: boolValue(configuration, keys: ["CSMRelayDisabled", "RelayDisabled"]) ?? false,
            localAIDisabled: boolValue(configuration, keys: ["CSMLocalAIDisabled", "LocalAIDisabled"]) ?? false,
            offlineTileCachingDisabled: boolValue(configuration, keys: ["CSMOfflineTileCachingDisabled", "OfflineTileCachingDisabled"]) ?? false,
            securityExportDisabled: boolValue(configuration, keys: ["CSMSecurityExportDisabled", "SecurityExportDisabled"]) ?? false,
            relayTrustedSigningKeys: relayTrustedSigningKeys(configuration),
            relayRevokedSigningKeyIds: relayRevokedSigningKeyIds(configuration)
        )
    }

    private static func relayTrustedSigningKeys(_ configuration: [String: Any]) -> [CrisisRelayTrustedSigningKey] {
        for key in ["CSMRelayTrustedSigningKeys", "RelayTrustedSigningKeys"] {
            guard let rawValue = configuration[key] else { continue }
            if let keys = decodeRelayTrustedSigningKeys(rawValue) {
                return keys
            }
        }
        return []
    }

    private static func relayRevokedSigningKeyIds(_ configuration: [String: Any]) -> [String] {
        for key in ["CSMRelayRevokedSigningKeyIds", "RelayRevokedSigningKeyIds"] {
            guard let rawValue = configuration[key] else { continue }
            if let ids = stringListValue(rawValue) {
                return ids
            }
        }
        return []
    }

    private static func decodeRelayTrustedSigningKeys(_ rawValue: Any) -> [CrisisRelayTrustedSigningKey]? {
        if let keys = rawValue as? [CrisisRelayTrustedSigningKey] {
            return keys
        }
        if let json = rawValue as? String,
           let data = json.data(using: .utf8) {
            return try? CSMJSONCoding.decoder.decode([CrisisRelayTrustedSigningKey].self, from: data)
        }
        if JSONSerialization.isValidJSONObject(rawValue),
           let data = try? JSONSerialization.data(withJSONObject: rawValue) {
            return try? CSMJSONCoding.decoder.decode([CrisisRelayTrustedSigningKey].self, from: data)
        }
        return nil
    }

    private static func stringListValue(_ rawValue: Any) -> [String]? {
        if let value = rawValue as? [String] {
            return value.map(Self.normalizedKeyId).filter { !$0.isEmpty }
        }
        if let value = rawValue as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("["),
               let data = trimmed.data(using: .utf8),
               let decoded = try? CSMJSONCoding.decoder.decode([String].self, from: data) {
                return decoded.map(Self.normalizedKeyId).filter { !$0.isEmpty }
            }
            return trimmed
                .split(separator: ",")
                .map { normalizedKeyId(String($0)) }
                .filter { !$0.isEmpty }
        }
        return nil
    }

    private static func normalizedKeyId(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func boolValue(_ configuration: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            guard let rawValue = configuration[key] else { continue }
            if let value = rawValue as? Bool {
                return value
            }
            if let value = rawValue as? NSNumber {
                return value.boolValue
            }
            if let value = rawValue as? String {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "1", "true", "yes", "y", "on":
                    return true
                case "0", "false", "no", "n", "off":
                    return false
                default:
                    continue
                }
            }
        }
        return nil
    }
}

private struct StatusObject: Decodable {
    var status: String?
}

private struct SourceIdentity: Decodable {
    var sourceSystemId: String
}

private extension KeyedDecodingContainer {
    func decodeStatusObjectIfPresent(forKey key: Key) throws -> String? {
        try decodeIfPresent(StatusObject.self, forKey: key)?.status
    }
}
