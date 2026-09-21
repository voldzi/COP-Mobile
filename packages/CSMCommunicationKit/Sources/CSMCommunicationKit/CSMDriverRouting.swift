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
}

public struct CSMDriverRouteResponse: Codable, Sendable {
    public let generatedAt: Date?
    public let routes: [CSMDriverRoute]
    public let traffic: CSMRouteTraffic?
    public let warnings: [String]

    public func navigationRoutes() throws -> [CSMDriverRoute] {
        let usable = routes.prefix(3).filter { $0.isNavigable }.sorted { ($0.rank ?? 1) < ($1.rank ?? 1) }
        guard !usable.isEmpty else { throw CSMDriverRoutingError.noNavigableRoute }
        return usable
    }
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
            return ("Živá doprava není aktivní", "Výpočet může používat běžné mapové rychlosti.")
        }
        if state == "stale" || state == "failed" || (age ?? 0) > 900 {
            return ("Živá doprava není aktuální", "Část výpočtu může používat běžné mapové rychlosti.")
        }
        if state == "idle" { return ("Živá doprava čeká na data", "Adaptivní režim čeká na automobilový dotaz.") }
        if state == "degraded" {
            return ("Živá doprava aktivní", "Živá data mají částečné pokrytí nebo omezenou kvalitu.")
        }
        if state == "ok", age != nil {
            return ("Živá doprava aktivní", nil)
        }
        return ("Stav živé dopravy není ověřen", "Část výpočtu může používat běžné mapové rychlosti.")
    }
}

public enum CSMDriverRoutingError: LocalizedError {
    case invalidCoordinates
    case noNavigableRoute
    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates: "Pro výpočet trasy není dostupná platná poloha."
        case .noNavigableRoute: "COP nyní neposkytl úplnou silniční trasu s navigačními pokyny. Zkuste výpočet znovu."
        }
    }
}

public extension CSMCommunicationRuntime {
    func drivingRoutes(from: CSMRoutePoint, to: CSMRoutePoint, alternatives: Int = 3) async throws -> CSMDriverRouteResponse {
        guard from.isValid, to.isValid else { throw CSMDriverRoutingError.invalidCoordinates }
        await startIfNeeded()
        let response = try await driverReportService.drivingRoutes(
            CSMDriverRouteRequest(from: from, to: to, alternatives: min(3, max(1, alternatives)))
        )
        _ = try response.navigationRoutes()
        return response
    }
}
