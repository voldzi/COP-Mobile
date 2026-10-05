import XCTest
@testable import CSMCommunicationKit

final class KnownClosuresTests: XCTestCase {
    private var request: CSMDriverRouteRequest {
        .init(from: .init(latitude: 50.08, longitude: 14.42), to: .init(latitude: 50.1, longitude: 14.45),
              alternatives: 3, includeRoadAttributes: true)
    }
    private func fixture(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> CSMDriverRouteResponse {
        let now = Date()
        let date = ISO8601DateFormatter()
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DriverRoutingTests.fixture.utf8)) as? [String: Any])
        var body = raw
        var route = try XCTUnwrap((raw["routes"] as? [[String: Any]])?.first)
        var query = try XCTUnwrap(JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(request)) as? [String: Any])
        query["via"] = []; query["avoid"] = []
        let dataset: [String: Any] = ["version": "fixture-v1", "builtAt": date.string(from: now.addingTimeInterval(-3600))]
        let canonical = try RoutingCanonicalJSON()
        func hash(_ object: Any) throws -> String {
            let value = try CSMJSONCoding.decoder.decode(CSMJSONValue.self, from: JSONSerialization.data(withJSONObject: object))
            return try canonical.hash(value)
        }
        route["knownClosures"] = [
            "version": "sim-known-road-closures-v1", "state": "applied", "coverage": "incomplete",
            "revision": String(repeating: "a", count: 64), "observedAt": date.string(from: now.addingTimeInterval(-10)),
            "validUntil": date.string(from: now.addingTimeInterval(300)), "appliedClosureCount": 1,
            "geometryHash": try hash(route["geometry"]!), "requestHash": try hash(query),
            "exclusions": [["closureId": "reviewed-bridge", "sourceDirection": "unknown", "enforcedDirection": "both",
                            "enforcementReason": "conservative_whole_structure_avoidance", "reviewedGeometryHash": String(repeating: "b", count: 64)]],
            "routingDataset": dataset, "engine": ["provider": "valhalla", "version": "test", "fallbackUsed": false],
            "limitations": ["Incomplete coverage"]
        ] as [String: Any]
        body["query"] = query; body["coverage"] = ["state": "covered", "routingDataset": dataset]
        body["routes"] = [route]
        mutate(&body)
        return try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func testAcceptedProofExpiresAndIsNotRestoredByDecoding() throws {
        let raw = try fixture()
        XCTAssertThrowsError(try raw.navigationRoutes())
        let verified = try raw.verifyingKnownClosures(for: request)
        XCTAssertEqual(try verified.navigationRoutes().count, 1)
        XCTAssertTrue(verified.routes[0].knownClosures?.usesConservativeAvoidance == true)
        XCTAssertThrowsError(try verified.requireValidKnownClosures(at: .now.addingTimeInterval(601)))
        let restored = try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: CSMJSONCoding.encoder.encode(verified))
        XCTAssertThrowsError(try restored.navigationRoutes())
    }

    func testRejectsChangedRequestEvenWithMatchingHash() throws {
        var changed = request
        changed.to = .init(latitude: 50.11, longitude: 14.45)
        XCTAssertThrowsError(try fixture().verifyingKnownClosures(for: changed))
    }

    func testRejectsEvidenceMutationsAndDoesNotFilterBadAlternative() throws {
        for field in ["geometryHash", "requestHash", "revision", "coverage", "version", "appliedClosureCount", "validUntil", "exclusions", "engine"] {
            let raw = try fixture { body in
                var routes = body["routes"] as! [[String: Any]]
                var bad = routes[0]
                var evidence = bad["knownClosures"] as! [String: Any]
                switch field {
                case "appliedClosureCount": evidence[field] = 0
                case "validUntil": evidence[field] = "2020-01-01T00:00:00Z"
                case "exclusions": evidence[field] = [["closureId": "reviewed-bridge", "sourceDirection": "unknown", "enforcedDirection": "both", "enforcementReason": "source_both_direction", "reviewedGeometryHash": String(repeating: "b", count: 64)]]
                case "engine": evidence[field] = ["provider": "valhalla", "version": "test", "fallbackUsed": true]
                default: evidence[field] = "invalid"
                }
                bad["knownClosures"] = evidence; bad["routeId"] = "bad-variant"; routes.append(bad); body["routes"] = routes
            }
            XCTAssertThrowsError(try raw.verifyingKnownClosures(for: request), field)
        }
    }

    func testECMAScriptCanonicalHashVectors() throws {
        let canonical = try RoutingCanonicalJSON()
        let values: [(Double, String)] = [(-0.0, "0"), (1, "1"), (1e-7, "1e-7"), (1e-6, "0.000001"),
                                         (1e20, "100000000000000000000"), (1e21, "1e+21"), (.leastNonzeroMagnitude, "5e-324")]
        for (number, expected) in values {
            XCTAssertEqual(try canonical.string(CSMJSONValue.object(["n": .number(number)])), "{\"n\":\(expected)}")
        }
        XCTAssertEqual(try canonical.hash(CSMJSONValue.object(["n": .number(1e-7)])), "747d6d23b64d1b2d579adb832b44de31c91c875bbef7a8e397f5d183a746b54b")
        let unicode = CSMJSONValue.object(["😀": .number(1), "\u{ffff}": .number(2)])
        XCTAssertEqual(try canonical.hash(unicode), "c6b1b96b618d8be475f379fe69c6646b44d7a5d3c01630c43509562f09d1024b")
    }
}
