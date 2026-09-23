import XCTest
@testable import CSMCommunicationKit

final class DriverRoutingTests: XCTestCase {
    static let fixture = #"{"generatedAt":"2026-09-21T00:00:00Z","warnings":[],"routes":[{"routeId":"test-road","status":"ok","geometry":{"type":"LineString","coordinates":[[14.42,50.08],[14.43,50.085],[14.45,50.1]]},"distanceM":3600,"durationSeconds":2400,"quality":{"mode":"engine_route","engine":"valhalla"},"steps":[{"index":0,"instructionLocalized":{"cs":"Pokračujte po trase."},"distanceM":3600,"durationSeconds":2400,"maneuverType":1,"beginShapeIndex":0,"endShapeIndex":2},{"index":1,"instructionLocalized":{"cs":"Jste v cíli."},"distanceM":0,"durationSeconds":0,"maneuverType":4,"beginShapeIndex":2,"endShapeIndex":2}]}]}"#

    func testFullRoutePreservesSIMTimeAndArrivalWhenLiveDataMissing() throws {
        let response = try decode(Self.fixture)
        let route = try XCTUnwrap(response.navigationRoutes().first)
        XCTAssertEqual(route.durationSeconds, 2400)
        XCTAssertEqual(route.steps.last?.maneuverType, 4)
        XCTAssertEqual(route.steps.last?.beginShapeIndex, route.steps.last?.endShapeIndex)
        XCTAssertNil(response.traffic)
    }

    func testRejectsStraightFallbackAndIncompleteManeuverGeometry() throws {
        for fixture in [
            Self.fixture.replacingOccurrences(of: "engine_route", with: "direct_fallback"),
            Self.fixture.replacingOccurrences(of: "\"endShapeIndex\":2", with: "\"endShapeIndex\":9"),
            Self.fixture.replacingOccurrences(of: "\"beginShapeIndex\":0", with: "\"beginShapeIndex\":1"),
            Self.fixture.replacingOccurrences(of: "[14.43,50.085]", with: "[194.43,50.085]"),
            Self.fixture.replacingOccurrences(of: "\"durationSeconds\":2400", with: "\"durationSeconds\":0")
        ] {
            XCTAssertThrowsError(try decode(fixture).navigationRoutes())
        }
    }

    func testTrafficStatesNeverInvalidateAnOtherwiseUsableRoute() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-21T00:00:00Z"))
        for state in ["ok", "degraded", "idle", "stale", "failed", "future_state"] {
            let traffic = #""traffic":{"liveSpeeds":{"enabled":true,"state":"STATE","ageSeconds":60,"mappingCoveragePercent":40.89,"appliedFlowCount":10,"appliedEdgeCount":20,"routingDataset":"test","detail":"test","updatedAt":"2026-09-21T00:00:00Z","sourceObservedAt":"2026-09-20T23:59:00Z"}},"#.replacingOccurrences(of: "STATE", with: state)
            let response = try decode("{" + traffic + Self.fixture.dropFirst())
            XCTAssertEqual(try response.navigationRoutes().count, 1)
            let live = try XCTUnwrap(response.traffic?.liveSpeeds)
            XCTAssertEqual(live.mappingCoveragePercent, 40.89)
            XCTAssertEqual(live.appliedFlowCount, 10)
            XCTAssertEqual(live.appliedEdgeCount, 20)
            XCTAssertEqual(live.routingDataset, "test")
            XCTAssertEqual(live.detail, "test")
            let status = live.presentation(at: date, receivedAt: date)
            XCTAssertEqual(status.warning == nil, state == "ok")
            if state == "degraded" {
                XCTAssertEqual(status.title, "Živá doprava s omezeným pokrytím")
            }
            if state == "stale" {
                XCTAssertEqual(status.title, "Živá doprava je zastaralá")
            }
            if state == "failed" {
                XCTAssertEqual(status.title, "Živá doprava není dostupná")
            }
            // Freshness ages in memory even when no new response arrives.
            XCTAssertNotNil(live.presentation(at: date.addingTimeInterval(901), receivedAt: date).warning)
        }
    }

    func testPreservesOptionalProviderLaneMasks() throws {
        let fixture = Self.fixture.replacingOccurrences(of: "\"maneuverType\":1", with: "\"maneuverType\":1,\"lanes\":[{\"directions\":2,\"active\":2},{\"directions\":64}]")
        let route = try XCTUnwrap(decode(fixture).navigationRoutes().first)
        XCTAssertEqual(route.steps[0].lanes?.first?.active, 2)
        XCTAssertEqual(route.steps[0].lanes?.last?.directions, 64)
        XCTAssertNil(route.steps[0].lanes?.last?.active)
    }

    func testUnknownFreshnessDoesNotClaimVerifiedLiveTraffic() throws {
        let live = try CSMJSONCoding.decoder.decode(CSMLiveSpeeds.self, from: Data(#"{"enabled":true,"state":"ok"}"#.utf8))
        XCTAssertNotNil(live.presentation(at: .now, receivedAt: .now).warning)
    }

    func testDisabledTrafficDoesNotClaimFreshLiveSpeeds() throws {
        let live = try CSMJSONCoding.decoder.decode(CSMLiveSpeeds.self, from: Data(#"{"enabled":false,"state":"failed"}"#.utf8))
        let status = live.presentation(at: .now, receivedAt: .now)
        XCTAssertEqual(status.title, "Živá doprava není dostupná")
        XCTAssertNotNil(status.warning)
    }

    func testOptionalDirectedAttributesStayBoundToTheirRouteAndDecodeOldResponses() throws {
        let oldResponse = try decode(Self.fixture)
        XCTAssertNil(oldResponse.coverage)
        XCTAssertNil(oldResponse.routes[0].roadAttributes)

        let enriched = Self.fixture
            .replacingOccurrences(of: #""warnings":[],"routes""#, with: #""warnings":[],"coverage":{"state":"covered","routingDataset":{"version":"test-graph","builtAt":"2026-09-20T03:00:00Z"},"sourceAgeSeconds":259200},"routes""#)
            .replacingOccurrences(of: #""quality":{"mode":"engine_route""#, with: #""roadAttributes":{"state":"ok","source":"valhalla_trace_attributes","observedAt":"2026-09-23T03:00:00Z","matchedEdgeCount":2,"geometryMismatchCount":0,"knownSpeedLimitCoveragePercent":75,"vehicleRestrictionsState":"not_evaluated","speedLimits":[{"beginShapeIndex":0,"endShapeIndex":1,"direction":"along_route","valueKph":50,"status":"explicit","source":"valhalla_graph_osm_maxspeed"},{"beginShapeIndex":1,"endShapeIndex":2,"direction":"along_route","status":"unknown","source":"unknown"}],"restrictions":[]},"vehicleAssessment":{"state":"partially_evaluated","providerCosting":"truck","appliedFields":["heightM"],"limitations":["Incomplete vehicle profile."]},"quality":{"mode":"engine_route""#)
        let response = try decode(enriched)
        XCTAssertEqual(response.coverage?.state, "covered")
        XCTAssertEqual(response.coverage?.routingDataset?.version, "test-graph")
        XCTAssertEqual(response.routes[0].roadAttributes?.speedLimits[0].valueKph, 50)
        XCTAssertNil(response.routes[0].roadAttributes?.speedLimits[1].valueKph)
        XCTAssertEqual(response.routes[0].vehicleAssessment?.state, "partially_evaluated")
        XCTAssertEqual(try response.navigationRoutes()[0].durationSeconds, 2400)
    }

    func testOutsideCoverageCanReachMapKitFallback() throws {
        let response = try decode(#"{"coverage":{"state":"outside_coverage","reason":"No navigable graph route."},"routes":[],"warnings":[]}"#)
        XCTAssertEqual(response.coverage?.state, "outside_coverage")
        XCTAssertTrue(response.routes.isEmpty)
        XCTAssertTrue(response.requiresMapKitFallback)
    }

    func testVehicleValuesAreValidatedAndOptionalRequestFieldsStayOptional() throws {
        XCTAssertTrue(CSMRouteVehicle(heightM: 1.8, weightTonnes: 1.9).isValid)
        XCTAssertFalse(CSMRouteVehicle().isValid)
        XCTAssertFalse(CSMRouteVehicle(heightM: .nan).isValid)
        XCTAssertFalse(CSMRouteVehicle(widthM: 6).isValid)
        let request = CSMDriverRouteRequest(
            from: CSMRoutePoint(latitude: 50.08, longitude: 14.42),
            to: CSMRoutePoint(latitude: 50.09, longitude: 14.43),
            alternatives: 2,
            includeRoadAttributes: nil,
            vehicle: nil
        )
        let encoded = try CSMJSONCoding.encoder.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["includeRoadAttributes"])
        XCTAssertNil(json["vehicle"])
        let enrichedRequest = CSMDriverRouteRequest(
            from: request.from,
            to: request.to,
            alternatives: 2,
            includeRoadAttributes: true,
            vehicle: CSMRouteVehicle(heightM: 1.8, weightTonnes: 1.9)
        )
        let enrichedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(enrichedRequest)) as? [String: Any])
        XCTAssertEqual(enrichedJSON["includeRoadAttributes"] as? Bool, true)
        XCTAssertEqual((enrichedJSON["vehicle"] as? [String: Double])?["heightM"], 1.8)
    }

    private func decode(_ json: String) throws -> CSMDriverRouteResponse {
        try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: Data(json.utf8))
    }
}
