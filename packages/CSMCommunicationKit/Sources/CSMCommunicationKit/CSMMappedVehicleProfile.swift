import Foundation

struct CSMMappedRouteFeature: Codable, Sendable {
    struct Properties: Codable, Sendable {
        let mappedProfileAssessment: CSMMappedProfileAssessment?
    }
    let id: String
    let type: String
    let geometry: CSMRouteGeometry
    let properties: Properties
}

public struct CSMMappedVehicleProfile: Codable, Equatable, Sendable {
    public let version: String
    public let intent: String
    public let coverageAcknowledged: String
    public let vehicle: Vehicle?
    public struct Trailer: Codable, Equatable, Sendable {
        public let attached: Bool
        public let heightM, widthM, lengthM, loadedWeightKg: Double
        public init(heightM: Double, widthM: Double, lengthM: Double, loadedWeightKg: Double) {
            attached = true; self.heightM = heightM; self.widthM = widthM
            self.lengthM = lengthM; self.loadedWeightKg = loadedWeightKg
        }
    }
    public struct Vehicle: Codable, Equatable, Sendable {
        public let heightM, widthM, lengthM, loadedWeightKg: Double
        public let axleLoadKg: Double?
        public let axleCount: Int?
        public let trailer: Trailer?
        public init(heightM: Double, widthM: Double, lengthM: Double, loadedWeightKg: Double,
                    axleLoadKg: Double? = nil, axleCount: Int? = nil, trailer: Trailer? = nil) {
            self.heightM = heightM; self.widthM = widthM; self.lengthM = lengthM
            self.loadedWeightKg = loadedWeightKg; self.axleLoadKg = axleLoadKg
            self.axleCount = axleCount; self.trailer = trailer
        }
    }
    public init(intent: String, vehicle: Vehicle? = nil) {
        version = "sim-mapped-road-profile-v1"; coverageAcknowledged = "mapped_restrictions_incomplete"
        self.intent = intent; self.vehicle = vehicle
    }
    public var isValid: Bool {
        guard version == "sim-mapped-road-profile-v1", coverageAcknowledged == "mapped_restrictions_incomplete",
              ["car", "commercial_truck", "car_with_trailer", "road_legal_4x4"].contains(intent) else { return false }
        guard let vehicle else { return intent == "car" || intent == "road_legal_4x4" }
        func valid(_ h: Double, _ w: Double, _ l: Double, _ kg: Double) -> Bool {
            [(h, 5.0), (w, 3.0), (l, 25.0), (kg, 60_000.0)].allSatisfy { $0.0.isFinite && $0.0 > 0 && $0.0 <= $0.1 }
        }
        guard valid(vehicle.heightM, vehicle.widthM, vehicle.lengthM, vehicle.loadedWeightKg) else { return false }
        if intent != "commercial_truck" && (vehicle.axleLoadKg != nil || vehicle.axleCount != nil) { return false }
        if let axle = vehicle.axleLoadKg, !axle.isFinite || axle <= 0 || axle > min(40_000, vehicle.loadedWeightKg) { return false }
        if let count = vehicle.axleCount, !(2...20).contains(count) { return false }
        guard (intent == "car_with_trailer") == (vehicle.trailer != nil) else { return false }
        if let trailer = vehicle.trailer {
            guard trailer.attached, valid(trailer.heightM, trailer.widthM, trailer.lengthM, trailer.loadedWeightKg),
                  trailer.heightM <= vehicle.heightM, trailer.widthM <= vehicle.widthM,
                  trailer.lengthM <= vehicle.lengthM, trailer.loadedWeightKg <= vehicle.loadedWeightKg else { return false }
        }
        return true
    }
    var requiredFields: Set<String> {
        var fields: Set<String> = vehicle == nil ? [] : ["heightM", "widthM", "lengthM", "loadedWeightKg"]
        if vehicle?.axleLoadKg != nil { fields.insert("axleLoadKg") }
        if vehicle?.axleCount != nil { fields.insert("axleCount") }
        if intent == "road_legal_4x4" { fields.insert("road_first_preference") }
        return fields
    }
}

public struct CSMMappedProfileCapabilities: Codable, Sendable {
    public struct Intent: Codable, Sendable {
        public let intent, costing: String
        public let supportedFields, limitations: [String]
    }
    public let version, availability: String
    public let intents: [Intent]
    public let maxSnapDistanceM: Double
    public let driverDeclaredAuthorization, unmappedLastMile: String
    public let strictGuarantees: Bool
    public func permits(_ profile: CSMMappedVehicleProfile) -> Bool {
        version == "sim-mapped-road-profile-capabilities-v1" && availability == "requires_runtime_validation" &&
        profile.isValid && maxSnapDistanceM == 25 && !strictGuarantees &&
        driverDeclaredAuthorization == "unsupported" && unmappedLastMile == "unsupported" &&
        intents.contains { $0.intent == profile.intent && $0.costing == (profile.intent == "commercial_truck" ? "truck" : "auto") && profile.requiredFields.isSubset(of: Set($0.supportedFields)) }
    }
}

public struct CSMMappedProfileAssessment: Codable, Sendable {
    public struct Engine: Codable, Sendable {
        public let provider, version, costing: String
        public let fallbackUsed: Bool
    }
    public struct LastMile: Codable, Sendable {
        public let state: String
        public let target, mappedEndpoint: CSMRoutePoint
        public let distanceM: Double
    }
    public let version, state, coverage: String
    public let appliedProfile: CSMMappedVehicleProfile
    public let profileHash, requestHash, geometryHash: String
    public let engine: Engine
    public let routingDataset: CSMRoutingDataset
    public let appliedFields: [String]
    public let validUntil: Date
    public let lastMile: LastMile
    public let limitations: [String]
}

extension CSMDriverRouteResponse {
    public func requireValidMappedProfile(at now: Date = .now) throws {
        guard !routes.contains(where: { $0.mappedProfileAssessment != nil }) ||
                (mappedProfileVerified && routes.allSatisfy { $0.mappedProfileAssessment.map { $0.validUntil > now } == true }) else {
            throw CSMDriverRoutingError.invalidMappedProfile
        }
    }
    func verifyingMappedProfile(_ request: CSMDriverRouteRequest, at now: Date = .now) throws -> Self {
        guard let profile = request.vehicleProfile else {
            guard !routes.contains(where: { $0.mappedProfileAssessment != nil }) else { throw CSMDriverRoutingError.invalidMappedProfile }
            return self
        }
        guard profile.isValid, knownClosuresVerified, !requiresMapKitFallback, !routes.isEmpty, let query,
              let features, features.count == routes.count, Set(features.map(\.id)).count == features.count else { throw CSMDriverRoutingError.invalidMappedProfile }
        let canonical = try RoutingCanonicalJSON()
        let profileHash = try canonical.hash(profile), queryHash = try canonical.hash(query)
        for route in routes {
            guard let assessment = route.mappedProfileAssessment, let closure = route.knownClosures,
                  assessment.version == "sim-mapped-road-profile-assessment-v1", assessment.state == "applied",
                  assessment.coverage == "mapped_restrictions_incomplete", assessment.appliedProfile == profile,
                  assessment.profileHash == profileHash, assessment.requestHash == queryHash,
                  assessment.geometryHash == (try canonical.hash(route.geometry)), assessment.validUntil > now,
                  assessment.validUntil <= closure.validUntil, assessment.routingDataset.version == closure.routingDataset.version,
                  assessment.routingDataset.builtAt == closure.routingDataset.builtAt,
                  assessment.engine.provider == "valhalla", assessment.engine.version == "3.8.3", !assessment.engine.fallbackUsed,
                  assessment.engine.costing == (profile.intent == "commercial_truck" ? "truck" : "auto"),
                  Set(assessment.appliedFields).count == assessment.appliedFields.count,
                  profile.requiredFields == Set(assessment.appliedFields), !assessment.limitations.isEmpty,
                  let last = route.geometry.coordinates.last else { throw CSMDriverRoutingError.invalidMappedProfile }
            guard let feature = features.first(where: { $0.id == route.routeId }), feature.type == "Feature",
                  let featureAssessment = feature.properties.mappedProfileAssessment,
                  try canonical.string(featureAssessment) == canonical.string(assessment),
                  try canonical.string(feature.geometry) == canonical.string(route.geometry) else { throw CSMDriverRoutingError.invalidMappedProfile }
            let mile = assessment.lastMile
            guard mile.target.lat == request.to.lat, mile.target.lon == request.to.lon,
                  mile.mappedEndpoint.lat == last[1], mile.mappedEndpoint.lon == last[0],
                  mile.distanceM.isFinite, (0...25).contains(mile.distanceM) else { throw CSMDriverRoutingError.invalidMappedProfile }
            let equal = mile.target.lat == mile.mappedEndpoint.lat && mile.target.lon == mile.mappedEndpoint.lon
            guard mile.state == (equal ? "mapped_target" : "target_guidance_only") else { throw CSMDriverRoutingError.invalidMappedProfile }
            // Independently bound endpoint distance; do not trust a supplied snap radius.
            let rad = Double.pi / 180
            let deltaLat = (mile.target.lat - mile.mappedEndpoint.lat) * rad
            let deltaLon = (mile.target.lon - mile.mappedEndpoint.lon) * rad
            let a = pow(sin(deltaLat / 2), 2) + cos(mile.target.lat * rad) * cos(mile.mappedEndpoint.lat * rad) * pow(sin(deltaLon / 2), 2)
            let distance = 6_371_000 * 2 * asin(sqrt(min(1, a)))
            guard distance <= 25, abs(distance - mile.distanceM) <= 0.5 else { throw CSMDriverRoutingError.invalidMappedProfile }
        }
        var verified = self; verified.mappedProfileVerified = true; return verified
    }
}

public extension CSMCommunicationRuntime {
    func drivingRoutes(from: CSMRoutePoint, to: CSMRoutePoint, vehicleProfile: CSMMappedVehicleProfile,
                       alternatives: Int = 3) async throws -> CSMDriverRouteResponse {
        guard from.isValid, to.isValid else { throw CSMDriverRoutingError.invalidCoordinates }
        guard vehicleProfile.isValid else { throw CSMDriverRoutingError.invalidVehicle }
        await startIfNeeded()
        guard try await drivingCapabilities().mappedProfiles?.permits(vehicleProfile) == true else { throw CSMDriverRoutingError.safetyRequirementsUnavailable }
        let request = CSMDriverRouteRequest(from: from, to: to, alternatives: min(3, max(1, alternatives)),
            includeRoadAttributes: true, vehicle: nil, vehicleProfile: vehicleProfile)
        let raw = try await driverReportService.drivingRoutes(request)
        let response = try await Task.detached {
            try raw.verifyingKnownClosures(for: request).verifyingMappedProfile(request)
        }.value
        _ = try response.navigationRoutes()
        return response
    }
}
