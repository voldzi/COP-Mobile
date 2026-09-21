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
            // Freshness ages in memory even when no new response arrives.
            XCTAssertNotNil(live.presentation(at: date.addingTimeInterval(901), receivedAt: date).warning)
        }
    }

    func testUnknownFreshnessDoesNotClaimVerifiedLiveTraffic() throws {
        let live = try CSMJSONCoding.decoder.decode(CSMLiveSpeeds.self, from: Data(#"{"enabled":true,"state":"ok"}"#.utf8))
        XCTAssertNotNil(live.presentation(at: .now, receivedAt: .now).warning)
    }

    private func decode(_ json: String) throws -> CSMDriverRouteResponse {
        try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: Data(json.utf8))
    }
}
