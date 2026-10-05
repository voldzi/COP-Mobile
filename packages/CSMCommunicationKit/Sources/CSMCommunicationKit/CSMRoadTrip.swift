import Foundation

/// Immutable opt-in snapshot for sim-road-trip-v1. Dimensions describe the whole loaded combination.
public struct CSMRoadTrip: Codable, Sendable, Equatable {
    public let version: String
    public let requestId: String
    public let intent: CSMRoadTripIntent
    public let vehicle: CSMRoadTripVehicle
    public let departure: CSMRoadTripDeparture
    public let preferences: CSMRoadTripPreferences
    public let requirements: CSMRoadTripRequirements
    public let waypoints: [CSMRoadTripWaypoint]
    public let destination: CSMRoadTripDestination

    public init(requestId: UUID = UUID(), intent: CSMRoadTripIntent, vehicle: CSMRoadTripVehicle,
                departure: CSMRoadTripDeparture = .now, preferences: CSMRoadTripPreferences,
                waypoints: [CSMRoadTripWaypoint] = [], destination: CSMRoadTripDestination = .roadPoint) {
        version = "sim-road-trip-v1"
        self.requestId = requestId.uuidString.lowercased()
        self.intent = intent; self.vehicle = vehicle; self.departure = departure
        self.preferences = preferences; requirements = CSMRoadTripRequirements()
        self.waypoints = waypoints; self.destination = destination
    }
    var isValid: Bool {
        version == "sim-road-trip-v1" && UUID(uuidString: requestId) != nil && vehicle.isValid &&
        ((intent == .carWithTrailer) == vehicle.trailer.attached) && departure.isValid &&
        requirements == CSMRoadTripRequirements() && waypoints.count <= 12 && waypoints.allSatisfy { $0.point.isValid } && destination.isValid
    }
}
public enum CSMRoadTripIntent: String, Codable, Sendable { case car, commercialTruck = "commercial_truck", carWithTrailer = "car_with_trailer" }
public struct CSMRoadTripVehicle: Codable, Sendable, Equatable {
    public let heightM: Double
    public let widthM: Double
    public let lengthM: Double
    public let loadedWeightKg: Double
    public let axleLoadKg: Double?
    public let axleCount: Int?
    public let trailer: CSMRoadTripTrailer
    public init(heightM: Double, widthM: Double, lengthM: Double, loadedWeightKg: Double,
                axleLoadKg: Double? = nil, axleCount: Int? = nil, trailer: CSMRoadTripTrailer = .none) {
        self.heightM = heightM; self.widthM = widthM; self.lengthM = lengthM; self.loadedWeightKg = loadedWeightKg
        self.axleLoadKg = axleLoadKg; self.axleCount = axleCount; self.trailer = trailer
    }
    var isValid: Bool {
        [(heightM, 8.0), (widthM, 5.0), (lengthM, 30.0), (loadedWeightKg, 100_000.0)].allSatisfy { $0.0.isFinite && $0.0 > 0 && $0.0 <= $0.1 } &&
        (axleLoadKg.map { $0.isFinite && $0 > 0 && $0 <= min(40_000, loadedWeightKg) } ?? true) &&
        (axleCount.map { (2...10).contains($0) } ?? true) && trailer.isValid &&
        (trailer.loadedWeightKg.map { $0 <= loadedWeightKg } ?? true) && (trailer.lengthM.map { $0 <= lengthM } ?? true) &&
        (trailer.heightM.map { $0 <= heightM } ?? true) && (trailer.widthM.map { $0 <= widthM } ?? true)
    }
}
public struct CSMRoadTripTrailer: Codable, Sendable, Equatable {
    public let attached: Bool
    public let heightM: Double?
    public let widthM: Double?
    public let lengthM: Double?
    public let loadedWeightKg: Double?
    public let axleCount: Int?
    public static let none = CSMRoadTripTrailer(attached: false)
    public init(attached: Bool, heightM: Double? = nil, widthM: Double? = nil, lengthM: Double? = nil,
                loadedWeightKg: Double? = nil, axleCount: Int? = nil) {
        self.attached = attached; self.heightM = heightM; self.widthM = widthM; self.lengthM = lengthM
        self.loadedWeightKg = loadedWeightKg; self.axleCount = axleCount
    }
    var isValid: Bool {
        let fields = [(heightM, 8.0), (widthM, 5.0), (lengthM, 30.0), (loadedWeightKg, 100_000.0)]
        if !attached { return fields.allSatisfy { $0.0 == nil } && axleCount == nil }
        return fields.allSatisfy { field in field.0.map { $0.isFinite && $0 > 0 && $0 <= field.1 } ?? false } &&
            (axleCount.map { (1...5).contains($0) } ?? false)
    }
}
public struct CSMRoadTripDeparture: Codable, Sendable, Equatable {
    public let mode: String
    public let at: String?
    public static let now = CSMRoadTripDeparture(mode: "now", at: nil)
    private init(mode: String, at: String?) { self.mode = mode; self.at = at }
    public static func departAt(_ date: Date) -> CSMRoadTripDeparture {
        CSMRoadTripDeparture(mode: "depart_at", at: ISO8601DateFormatter().string(from: date))
    }
    var isValid: Bool {
        (mode == "now" && at == nil) || (mode == "depart_at" && at?.hasSuffix("Z") == true && at.flatMap { ISO8601DateFormatter().date(from: $0) } != nil)
    }
}
public struct CSMRoadTripPreferences: Codable, Sendable, Equatable {
    public let avoidTolls: Bool
    public let preferPaved: Bool
    public init(avoidTolls: Bool, preferPaved: Bool) { self.avoidTolls = avoidTolls; self.preferPaved = preferPaved }
}
public struct CSMRoadTripRequirements: Codable, Sendable, Equatable {
    public let roadClosures: String
    public let legalAccess: String
    public let vehicleLimits: String
    public init() { roadClosures = "mandatory"; legalAccess = "mandatory"; vehicleLimits = "mandatory" }
}
public struct CSMRoadTripWaypoint: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case via, stop }
    public let type: Kind
    public let point: CSMRoadTripPoint
    public init(type: Kind, point: CSMRoadTripPoint) { self.type = type; self.point = point }
}
public struct CSMRoadTripPoint: Codable, Sendable, Equatable {
    public let lat: Double
    public let lon: Double
    public let label: String?
    public init(latitude: Double, longitude: Double, label: String? = nil) { lat = latitude; lon = longitude; self.label = label }
    var isValid: Bool { CSMRoutePoint(latitude: lat, longitude: lon).isValid && (label?.count ?? 0) <= 80 }
}
public struct CSMRoadTripDestination: Codable, Sendable, Equatable {
    public let kind: String
    public let entranceId: String?
    public static let roadPoint = CSMRoadTripDestination(kind: "road_point", entranceId: nil)
    private init(kind: String, entranceId: String?) { self.kind = kind; self.entranceId = entranceId }
    public static func approvedEntrance(_ id: String) -> CSMRoadTripDestination { CSMRoadTripDestination(kind: "approved_entrance", entranceId: id) }
    var isValid: Bool {
        (kind == "road_point" && entranceId == nil) || (kind == "approved_entrance" && (entranceId?.isEmpty == false) && (entranceId?.count ?? 0) <= 128)
    }
}

public struct CSMRoadTripAssessment: Codable, Sendable {
    public let version: String
    public let requestId: String
    public let requestHash: String
    public let appliedHash: String
    public let appliedTrip: CSMRoadTrip
    public let engine: CSMRoadTripEngine
    public let geometryHash: String
    public let routingDataset: CSMRoadTripDataset
    public let closures: CSMRoadTripClosures
    public let vehicleLimits: CSMRoadTripVehicleLimits
    public let waypoints: CSMRoadTripWaypoints
    public let lastMile: String
    public let validUntil: Date
    public let limitations: [String]
    /// COP checks canonical request and geometry hashes server-side against the actual response before forwarding.
    func satisfies(_ trip: CSMRoadTrip, coverage: CSMRouteCoverage?, at now: Date) -> Bool {
        version == "sim-road-trip-assessment-v1" && requestId == trip.requestId && appliedTrip == trip &&
        requestHash.count == 64 && requestHash.allSatisfy { "0123456789abcdef".contains($0) } && appliedHash == requestHash &&
        geometryHash.count == 64 && geometryHash.allSatisfy { "0123456789abcdef".contains($0) } &&
        engine.provider == "valhalla" && engine.costing == (trip.intent == .car ? "auto" : "truck") && !engine.fallbackUsed &&
        routingDataset.freshness == "current" && coverage?.routingDataset?.version == routingDataset.version &&
        coverage?.routingDataset?.builtAt == routingDataset.builtAt && routingDataset.builtAt <= now &&
        closures.state == "applied" && closures.coverage == "authoritative_reviewed_snapshot" && !closures.revision.isEmpty &&
        closures.observedAt <= now && validUntil > now && validUntil <= closures.validUntil &&
        vehicleLimits.state == "provider_costing_applied" && vehicleLimits.coverage == "mapped_restrictions_incomplete" &&
        Set(["heightM", "widthM", "lengthM", "loadedWeightKg"]).isSubset(of: Set(vehicleLimits.appliedFields)) &&
        waypoints.state == "applied" && waypoints.orderedCount == trip.waypoints.count && lastMile == "not_requested" && trip.destination.kind == "road_point"
    }
}
public struct CSMRoadTripEngine: Codable, Sendable { public let provider: String; public let version: String; public let costing: String; public let fallbackUsed: Bool }
public struct CSMRoadTripDataset: Codable, Sendable { public let version: String; public let builtAt: Date; public let sourceAgeSeconds: Double; public let freshness: String }
public struct CSMRoadTripClosures: Codable, Sendable { public let state: String; public let revision: String; public let observedAt: Date; public let validUntil: Date; public let appliedClosureCount: Int; public let coverage: String }
public struct CSMRoadTripVehicleLimits: Codable, Sendable { public let state: String; public let appliedFields: [String]; public let coverage: String }
public struct CSMRoadTripWaypoints: Codable, Sendable { public let state: String; public let orderedCount: Int }
public struct CSMRouteRoundabout: Codable, Sendable {
    public let phase: String
    public let source: String
    public let countState: String
    public let exitCount: Int?
    public let exitRoadNames: [String]?
    public let signNames: [String]?
}

public extension CSMDriverRouteResponse {
    /// Strict trips never grant an Apple/unconstrained fallback. Revalidate after route selection and as validity expires.
    func navigationRoutes(for trip: CSMRoadTrip, at now: Date = .now) throws -> [CSMDriverRoute] {
        guard !hasKnownClosures, trip.isValid, !routes.isEmpty, routes.count <= 3,
              routes.allSatisfy({ $0.isNavigable && $0.assessment?.satisfies(trip, coverage: coverage, at: now) == true })
        else { throw CSMDriverRoutingError.safetyRequirementsUnavailable }
        return routes.sorted { ($0.rank ?? 1) < ($1.rank ?? 1) }
    }
}
public extension CSMCommunicationRuntime {
    static var roadTripContractVersion: String { "sim-road-trip-v1" }
    func drivingRoutes(from: CSMRoutePoint, to: CSMRoutePoint, trip: CSMRoadTrip, alternatives: Int = 3) async throws -> CSMDriverRouteResponse {
        guard from.isValid, to.isValid else { throw CSMDriverRoutingError.invalidCoordinates }
        guard trip.isValid, (1...3).contains(alternatives) else { throw CSMDriverRoutingError.invalidTrip }
        await startIfNeeded()
        let request = CSMDriverRouteRequest(from: from, to: to, alternatives: alternatives,
            includeRoadAttributes: true, trip: trip, avoid: ["road_closure"])
        let response = try await driverReportService.drivingRoutes(request)
        _ = try response.navigationRoutes(for: trip)
        return response
    }
}

public struct CSMDriverRoutingCatalog: Codable, Sendable {
    public let profiles: [CSMDriverRoutingProfile]
    public let warnings: [String]
    public let capabilities: CSMRoadTripCapabilities?
    public let mappedProfiles: CSMMappedProfileCapabilities?
}
public struct CSMDriverRoutingProfile: Codable, Sendable {
    public let profileId: String
    public let label: String?
}
public struct CSMRoadTripCapabilities: Codable, Sendable {
    public let version: String
    public let strictRoutesEnabled: Bool
    /// This is not a promise that a particular graph or closure snapshot is currently healthy.
    public let availability: String
    public let intents: [CSMRoadTripIntentCapability]
    public let vehicleFields: [String]
    public let unsupportedFields: [String]
    public let closures: CSMRoadTripClosureCapability
    public let graphMaxAgeSeconds: Int
    public let maxWaypoints: Int
    public let maxAlternatives: Int
    public let cachePolicy: String
    public let emergencyExemption: Bool
}
public struct CSMRoadTripIntentCapability: Codable, Sendable { public let intent: CSMRoadTripIntent; public let costing: String; public let state: String }
public struct CSMRoadTripClosureCapability: Codable, Sendable { public let mode: String; public let state: String; public let oneDirection: String }
public extension CSMCommunicationRuntime {
    func drivingCapabilities() async throws -> CSMDriverRoutingCatalog {
        await startIfNeeded()
        return try await driverReportService.drivingCapabilities()
    }
}
