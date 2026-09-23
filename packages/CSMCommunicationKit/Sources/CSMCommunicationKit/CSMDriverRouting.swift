import Foundation

/// COP is the sole network boundary. No provider URLs or credentials are accepted.
public struct CSMRoutePoint: Codable, Sendable {
    public var lat: Double
    public var lon: Double
    public init(latitude: Double, longitude: Double) { lat = latitude; lon = longitude }
    var isValid: Bool { lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon) }
}

struct CSMDriverRouteRequest: Encodable, Sendable {
    var from: CSMRoutePoint
    var to: CSMRoutePoint
    let profileId = "car"
    let includeSteps = true
    var alternatives: Int
    var includeRoadAttributes: Bool?
    var vehicle: CSMRouteVehicle?
}

/// Actual recorded dimensions only. Unknown values must remain nil.
public struct CSMRouteVehicle: Codable, Sendable {
    public let heightM: Double?
    public let widthM: Double?
    public let lengthM: Double?
    public let weightTonnes: Double?

    public init(heightM: Double? = nil, widthM: Double? = nil, lengthM: Double? = nil, weightTonnes: Double? = nil) {
        self.heightM = heightM
        self.widthM = widthM
        self.lengthM = lengthM
        self.weightTonnes = weightTonnes
    }

    var isValid: Bool {
        let fields = [(heightM, 8.0), (widthM, 5.0), (lengthM, 30.0), (weightTonnes, 100.0)]
        return fields.contains(where: { $0.0 != nil }) && fields.allSatisfy { field in
            field.0.map { value in value.isFinite && value > 0 && value <= field.1 } ?? true
        }
    }
}

public struct CSMDriverRouteResponse: Codable, Sendable {
    public let generatedAt: Date?
    public let coverage: CSMRouteCoverage?
    public let routes: [CSMDriverRoute]
    public let traffic: CSMRouteTraffic?
    public let warnings: [String]

    public var requiresMapKitFallback: Bool {
        coverage?.state == "outside_coverage" || routes.isEmpty
    }

    public func navigationRoutes() throws -> [CSMDriverRoute] {
        let usable = routes.prefix(3).filter { $0.isNavigable }.sorted { ($0.rank ?? 1) < ($1.rank ?? 1) }
        guard !usable.isEmpty else { throw CSMDriverRoutingError.noNavigableRoute }
        return usable
    }
}

public struct CSMRoutingDataset: Codable, Sendable {
    public let version: String
    public let builtAt: Date
}

public struct CSMRouteCoverage: Codable, Sendable {
    /// covered, partial, outside_coverage or unknown.
    public let state: String
    public let reason: String?
    public let routingDataset: CSMRoutingDataset?
    public let sourceAgeSeconds: Int?
}

public struct CSMRouteSpeedLimit: Codable, Sendable {
    public let beginShapeIndex: Int
    public let endShapeIndex: Int
    public let direction: String
    public let valueKph: Double?
    /// Only explicit is a posted limit. Derived and unknown are not legal certainty.
    public let status: String
    public let source: String
}

public struct CSMRouteRestriction: Codable, Sendable {
    public let kind: String
    public let beginShapeIndex: Int
    public let endShapeIndex: Int
    /// Current closure data is advisory, never a verified legal prohibition.
    public let assessment: String
    public let source: String
}

public struct CSMRouteRoadAttributes: Codable, Sendable {
    public let state: String
    public let reason: String?
    public let source: String
    public let routingDataset: CSMRoutingDataset?
    public let sourceAgeSeconds: Int?
    public let observedAt: Date
    public let matchedEdgeCount: Int
    public let geometryMismatchCount: Int
    public let knownSpeedLimitCoveragePercent: Double
    public let vehicleRestrictionsState: String
    public let speedLimits: [CSMRouteSpeedLimit]
    public let restrictions: [CSMRouteRestriction]
}

public struct CSMRouteVehicleAssessment: Codable, Sendable {
    public let state: String
    public let providerCosting: String
    public let appliedFields: [String]
    public let limitations: [String]
}

public struct CSMRouteGeometry: Codable, Sendable {
    public let type: String
    public let coordinates: [[Double]]
    var isValid: Bool {
        type == "LineString" && (2...200_000).contains(coordinates.count) && coordinates.allSatisfy {
            $0.count >= 2 && CSMRoutePoint(latitude: $0[1], longitude: $0[0]).isValid
        }
    }
}

public struct CSMDriverRoute: Codable, Sendable {
    public let routeId: String
    public let rank: Int?
    public let status: String?
    public let geometry: CSMRouteGeometry
    public let distanceM: Double
    public let durationSeconds: Double
    public let steps: [CSMRouteStep]
    public let quality: CSMRouteQuality?
    public let traffic: CSMRouteTraffic?
    public let warnings: [String]?
    public let roadAttributes: CSMRouteRoadAttributes?
    public let vehicleAssessment: CSMRouteVehicleAssessment?

    public var isNavigable: Bool {
        guard geometry.isValid, distanceM.isFinite, distanceM > 0,
              durationSeconds.isFinite, durationSeconds > 0,
              quality?.mode == "engine_route", quality?.engine == "valhalla",
              status == "ok" || status == "partial", !steps.isEmpty, steps.count <= 10_000 else { return false }
        var previousEnd = 0
        for step in steps {
            guard let start = step.beginShapeIndex, let end = step.endShapeIndex,
                  start == previousEnd, end >= start, end < geometry.coordinates.count,
                  step.durationSeconds.isFinite, step.durationSeconds >= 0,
                  step.distanceM.isFinite, step.distanceM >= 0 else { return false }
            previousEnd = end
        }
        return previousEnd == geometry.coordinates.count - 1
    }
}

public struct CSMRouteQuality: Codable, Sendable {
    public let mode: String?
    public let engine: String?
}

public struct CSMRouteStep: Codable, Sendable {
    public let index: Int
    public let instructionLocalized: [String: String]
    public let distanceM: Double
    public let durationSeconds: Double
    public let roadName: String?
    public let maneuverType: Int?
    public let roundaboutExitCount: Int?
    public let lanes: [CSMRouteLane]?
    /// Indices in the complete response route geometry, including joined legs.
    public let beginShapeIndex: Int?
    public let endShapeIndex: Int?
}

/// Raw provider masks. Presentation and lane choice remain owned by the host.
public struct CSMRouteLane: Codable, Sendable {
    public let directions: Int
    public let active: Int?
    public let valid: Int?
}

public struct CSMRouteTraffic: Codable, Sendable {
    public let liveSpeeds: CSMLiveSpeeds?
}

public struct CSMLiveSpeeds: Codable, Sendable {
    public let enabled: Bool?
    public let state: String?
    public let updatedAt: Date?
    public let sourceObservedAt: Date?
    public let ageSeconds: Double?
    public let appliedFlowCount: Int?
    public let appliedEdgeCount: Int?
    public let mappingCoveragePercent: Double?
    public let routingDataset: String?
    public let detail: String?

    public func effectiveAge(at now: Date, receivedAt: Date) -> Double? {
        let measured = sourceObservedAt.map { max(0, now.timeIntervalSince($0)) }
        let aged = ageSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 + max(0, now.timeIntervalSince(receivedAt)) : nil }
        return [measured, aged].compactMap { $0 }.max()
    }

    public func presentation(at now: Date, receivedAt: Date) -> (title: String, warning: String?) {
        let age = effectiveAge(at: now, receivedAt: receivedAt)
        guard enabled == true else {
            return ("Živá doprava není dostupná", "Výpočet může používat běžné mapové rychlosti.")
        }
        if state == "failed" {
            return ("Živá doprava není dostupná", "Část výpočtu může používat běžné mapové rychlosti.")
        }
        if state == "stale" || (age ?? 0) > 900 {
            return ("Živá doprava je zastaralá", "Část výpočtu může používat běžné mapové rychlosti.")
        }
        if state == "idle" { return ("Živá doprava čeká na data", "Adaptivní režim čeká na automobilový dotaz.") }
        if state == "degraded" {
            return ("Živá doprava s omezeným pokrytím", "Část trasy může používat běžné mapové rychlosti.")
        }
        if state == "ok", age != nil {
            return ("Živá doprava aktivní", nil)
        }
        return ("Stav živé dopravy není ověřen", "Část výpočtu může používat běžné mapové rychlosti.")
    }
}

public enum CSMDriverRoutingError: LocalizedError {
    case invalidCoordinates
    case invalidVehicle
    case noNavigableRoute
    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: "Pro výpočet trasy není dostupná platná poloha."
        case .invalidVehicle: "Rozměry nebo hmotnost vybraného vozidla nejsou platné."
        case .noNavigableRoute: "COP nyní neposkytl úplnou silniční trasu s navigačními pokyny. Zkuste výpočet znovu."
        }
    }
}

public extension CSMCommunicationRuntime {
    func drivingRoutes(
        from: CSMRoutePoint,
        to: CSMRoutePoint,
        alternatives: Int = 3,
        includeRoadAttributes: Bool = false,
        vehicle: CSMRouteVehicle? = nil
    ) async throws -> CSMDriverRouteResponse {
        guard from.isValid, to.isValid else { throw CSMDriverRoutingError.invalidCoordinates }
        guard vehicle?.isValid ?? true else { throw CSMDriverRoutingError.invalidVehicle }
        await startIfNeeded()
        let response = try await driverReportService.drivingRoutes(
            CSMDriverRouteRequest(
                from: from,
                to: to,
                alternatives: min(3, max(1, alternatives)),
                includeRoadAttributes: includeRoadAttributes ? true : nil,
                vehicle: vehicle
            )
        )
        // Preserve a typed outside-coverage/empty result so the host can start
        // real MapKit routing rather than losing the reason in a generic error.
        if !response.requiresMapKitFallback {
            _ = try response.navigationRoutes()
        }
        return response
    }
}
