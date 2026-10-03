import XCTest
@testable import CSMCommunicationKit

final class RoadTripTests: XCTestCase {
    static let now = ISO8601DateFormatter().date(from: "2026-10-03T12:00:00Z")!
    static func trip() -> CSMRoadTrip {
        CSMRoadTrip(requestId: UUID(uuidString: "2c78031f-0db9-430f-bfc8-e527df399aba")!, intent: .car,
            vehicle: CSMRoadTripVehicle(heightM: 1.8, widthM: 1.9, lengthM: 4.5, loadedWeightKg: 1900),
            preferences: CSMRoadTripPreferences(avoidTolls: false, preferPaved: true),
            waypoints: [CSMRoadTripWaypoint(type: .stop, point: CSMRoadTripPoint(latitude: 50.5, longitude: 14.5))])
    }
    func testImmutableSnapshotEncodesExactSIUnitsAndMandatoryRequirements() throws {
        let trip = Self.trip()
        XCTAssertTrue(trip.isValid)
        let request = CSMDriverRouteRequest(from: .init(latitude: 50, longitude: 14), to: .init(latitude: 51, longitude: 15),
            alternatives: 2, includeRoadAttributes: true, trip: trip, avoid: ["road_closure"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(request)) as? [String: Any])
        XCTAssertEqual(json["profileId"] as? String, "car")
        XCTAssertEqual(json["avoid"] as? [String], ["road_closure"])
        XCTAssertNil(json["vehicle"]); XCTAssertNil(json["via"]); XCTAssertNil(json["departureTime"])
        let snapshot = try XCTUnwrap(json["trip"] as? [String: Any])
        XCTAssertEqual(snapshot["version"] as? String, "sim-road-trip-v1")
        let vehicle = try XCTUnwrap(snapshot["vehicle"] as? [String: Any])
        XCTAssertEqual(vehicle["loadedWeightKg"] as? Double, 1900)
        XCTAssertNil(vehicle["weightTonnes"])
        XCTAssertEqual(snapshot["requirements"] as? [String: String], ["roadClosures": "mandatory", "legalAccess": "mandatory", "vehicleLimits": "mandatory"])
        XCTAssertEqual(try CSMJSONCoding.decoder.decode(CSMRoadTrip.self, from: CSMJSONCoding.encoder.encode(trip)), trip)
    }
    func testInvalidCompleteVehicleOrTrailerNeverBecomesAnUnconstrainedCar() {
        for vehicle in [
            CSMRoadTripVehicle(heightM: .nan, widthM: 2, lengthM: 5, loadedWeightKg: 1800),
            CSMRoadTripVehicle(heightM: 2, widthM: 2, lengthM: 5, loadedWeightKg: 0),
            CSMRoadTripVehicle(heightM: 2, widthM: 2, lengthM: 5, loadedWeightKg: 1800, axleLoadKg: 2000),
            CSMRoadTripVehicle(heightM: 2, widthM: 2, lengthM: 5, loadedWeightKg: 1800, trailer: .init(attached: true))
        ] { XCTAssertFalse(vehicle.isValid) }
        XCTAssertFalse(CSMRoadTrip(intent: .carWithTrailer, vehicle: Self.trip().vehicle,
            preferences: .init(avoidTolls: false, preferPaved: false)).isValid)
        XCTAssertFalse(CSMRoadTripTrailer(attached: false, heightM: 1).isValid)
    }
    func testStrictRouteRequiresMatchingSnapshotFreshnessAndEveryVariant() throws {
        let response = try decodeFixture()
        XCTAssertEqual(try response.navigationRoutes(for: Self.trip(), at: Self.now).count, 1)
        for mutate in [
            { (a: inout [String: Any]) in a["requestId"] = UUID().uuidString },
            { (a: inout [String: Any]) in a["appliedHash"] = String(repeating: "b", count: 64) },
            { (a: inout [String: Any]) in a["validUntil"] = "2026-10-03T12:00:00Z" },
            { (a: inout [String: Any]) in a["validUntil"] = "2026-10-03T12:30:00Z" },
            { (a: inout [String: Any]) in a["engine"] = ["provider": "valhalla", "version": "fixture", "costing": "auto", "fallbackUsed": true] },
            { (a: inout [String: Any]) in a["vehicleLimits"] = ["state": "partial", "appliedFields": ["heightM"], "coverage": "mapped_restrictions_incomplete"] },
            { (a: inout [String: Any]) in a["waypoints"] = ["state": "applied", "orderedCount": 0] }
        ] {
            let unsafe = try decodeFixture(mutate: mutate, addSecondVariant: true)
            XCTAssertThrowsError(try unsafe.navigationRoutes(for: Self.trip(), at: Self.now))
        }
        XCTAssertThrowsError(try response.navigationRoutes(for: Self.trip(), at: Self.now.addingTimeInterval(601)))
        let changed = CSMRoadTrip(intent: .car, vehicle: Self.trip().vehicle, preferences: .init(avoidTolls: true, preferPaved: true))
        XCTAssertThrowsError(try response.navigationRoutes(for: changed, at: Self.now))
    }
    func testOldOrEmptyResponseCannotSatisfyStrictTripOrGrantFallback() throws {
        for json in [DriverRoutingTests.fixture, #"{"coverage":{"state":"outside_coverage"},"routes":[],"warnings":[]}"#] {
            let response = try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: Data(json.utf8))
            XCTAssertThrowsError(try response.navigationRoutes(for: Self.trip(), at: Self.now))
        }
    }
    func testStructuredRoundaboutPreservesPhaseCountAndProviderNames() throws {
        let value = try CSMJSONCoding.decoder.decode(CSMRouteRoundabout.self, from: Data(#"{"phase":"enter","source":"valhalla_maneuver","countState":"provider_supplied","exitCount":4,"exitRoadNames":["445"],"signNames":["Vrbno"]}"#.utf8))
        XCTAssertEqual(value.phase, "enter"); XCTAssertEqual(value.exitCount, 4); XCTAssertEqual(value.signNames, ["Vrbno"])
    }
    private func decodeFixture(mutate: ((inout [String: Any]) -> Void)? = nil, addSecondVariant: Bool = false) throws -> CSMDriverRouteResponse {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DriverRoutingTests.fixture.utf8)) as? [String: Any])
        var routes = try XCTUnwrap(json["routes"] as? [[String: Any]])
        let dataset: [String: Any] = ["version": "test-graph", "builtAt": "2026-10-02T00:00:00Z"]
        json["coverage"] = ["state": "covered", "routingDataset": dataset]
        var assessment: [String: Any] = [
            "version": "sim-road-trip-assessment-v1", "requestId": Self.trip().requestId,
            "requestHash": String(repeating: "a", count: 64), "appliedHash": String(repeating: "a", count: 64),
            "appliedTrip": try JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(Self.trip())),
            "engine": ["provider": "valhalla", "version": "fixture", "costing": "auto", "fallbackUsed": false],
            "geometryHash": String(repeating: "c", count: 64),
            "routingDataset": ["version": "test-graph", "builtAt": "2026-10-02T00:00:00Z", "sourceAgeSeconds": 129600, "freshness": "current"],
            "closures": ["state": "applied", "revision": "synthetic-review", "observedAt": "2026-10-03T11:55:00Z", "validUntil": "2026-10-03T12:15:00Z", "appliedClosureCount": 0, "coverage": "authoritative_reviewed_snapshot"],
            "vehicleLimits": ["state": "provider_costing_applied", "appliedFields": ["heightM", "widthM", "lengthM", "loadedWeightKg"], "coverage": "mapped_restrictions_incomplete"],
            "waypoints": ["state": "applied", "orderedCount": 1], "lastMile": "not_requested",
            "validUntil": "2026-10-03T12:10:00Z", "limitations": ["Synthetic SDK fixture; hashes are verified by COP, not this fixture."]
        ]
        routes[0]["assessment"] = assessment
        if addSecondVariant { routes.append(routes[0]); routes[1]["routeId"] = "variant-2" }
        mutate?(&assessment); routes[routes.count - 1]["assessment"] = assessment
        json["routes"] = routes
        return try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
