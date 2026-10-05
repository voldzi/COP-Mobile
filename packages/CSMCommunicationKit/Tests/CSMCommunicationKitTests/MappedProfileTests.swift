import XCTest
@testable import CSMCommunicationKit

final class MappedProfileTests: XCTestCase {
    private let profile = CSMMappedVehicleProfile(intent: "car")
    private var request: CSMDriverRouteRequest {
        .init(from: .init(latitude: 50.08, longitude: 14.42), to: .init(latitude: 50.1, longitude: 14.45),
              alternatives: 3, includeRoadAttributes: true, vehicleProfile: profile)
    }
    private func fixture(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> CSMDriverRouteResponse {
        let now = Date(), date = ISO8601DateFormatter(), canonical = try RoutingCanonicalJSON()
        var body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(DriverRoutingTests.fixture.utf8)) as? [String: Any])
        var route = try XCTUnwrap((body["routes"] as? [[String: Any]])?.first)
        var query = try XCTUnwrap(JSONSerialization.jsonObject(with: CSMJSONCoding.encoder.encode(request)) as? [String: Any])
        query["via"] = []; query["avoid"] = []
        func hash(_ value: Any) throws -> String {
            try canonical.hash(CSMJSONCoding.decoder.decode(CSMJSONValue.self, from: JSONSerialization.data(withJSONObject: value)))
        }
        let dataset: [String: Any] = ["version": "synthetic", "builtAt": date.string(from: now.addingTimeInterval(-3600))]
        let engine: [String: Any] = ["provider": "valhalla", "version": "3.8.3", "costing": "auto", "fallbackUsed": false]
        let geometry = try XCTUnwrap(route["geometry"] as? [String: Any])
        let last = try XCTUnwrap((geometry["coordinates"] as? [[Double]])?.last)
        let endpoint: [String: Any] = ["lat": last[1], "lon": last[0]]
        let target: [String: Any] = ["lat": request.to.lat, "lon": request.to.lon]
        let same = last[1] == request.to.lat && last[0] == request.to.lon
        // Fixture geometry must finish exactly at this test target.
        XCTAssertTrue(same)
        let closure: [String: Any] = ["version": "sim-known-road-closures-v1", "state": "applied", "coverage": "incomplete",
            "revision": String(repeating: "a", count: 64), "observedAt": date.string(from: now.addingTimeInterval(-10)),
            "validUntil": date.string(from: now.addingTimeInterval(300)), "appliedClosureCount": 0,
            "geometryHash": try hash(geometry), "requestHash": try hash(query), "exclusions": [],
            "routingDataset": dataset, "engine": engine, "limitations": ["Synthetic incomplete coverage"]]
        let assessment: [String: Any] = ["version": "sim-mapped-road-profile-assessment-v1", "state": "applied",
            "coverage": "mapped_restrictions_incomplete", "appliedProfile": query["vehicleProfile"]!,
            "profileHash": try canonical.hash(profile), "requestHash": try hash(query), "geometryHash": try hash(geometry),
            "engine": engine, "routingDataset": dataset, "appliedFields": [], "validUntil": date.string(from: now.addingTimeInterval(290)),
            "lastMile": ["state": "mapped_target", "target": target, "mappedEndpoint": endpoint, "distanceM": 0],
            "limitations": ["Synthetic incomplete coverage"]]
        route["knownClosures"] = closure; route["mappedProfileAssessment"] = assessment
        body["query"] = query; body["coverage"] = ["state": "covered", "routingDataset": dataset]
        body["routes"] = [route]
        body["features"] = [["id": route["routeId"]!, "type": "Feature", "geometry": geometry,
            "properties": ["mappedProfileAssessment": assessment]]]
        mutate(&body)
        return try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: JSONSerialization.data(withJSONObject: body))
    }

    func testProofExpiryAndSerializationCannotCreateAcceptance() throws {
        let raw = try fixture()
        XCTAssertThrowsError(try raw.navigationRoutes())
        let verified = try raw.verifyingKnownClosures(for: request).verifyingMappedProfile(request)
        XCTAssertEqual(try verified.navigationRoutes().count, 1)
        XCTAssertThrowsError(try verified.requireValidMappedProfile(at: Date().addingTimeInterval(600)))
        let decoded = try CSMJSONCoding.decoder.decode(CSMDriverRouteResponse.self, from: CSMJSONCoding.encoder.encode(verified))
        XCTAssertThrowsError(try decoded.requireValidMappedProfile())
    }

    func testRejectsFeatureMismatchAndUnsolicitedProfile() throws {
        let raw = try fixture()
        var ordinary = request; ordinary.vehicleProfile = nil
        XCTAssertThrowsError(try raw.verifyingMappedProfile(ordinary))
        let changed = try fixture { $0["features"] = [] }
        XCTAssertThrowsError(try changed.verifyingKnownClosures(for: request).verifyingMappedProfile(request))
    }

    func testRejectsAppliedProfileHashCostingAndLastMileMutations() throws {
        for field in ["profileHash", "requestHash", "geometryHash", "coverage", "state", "engine", "lastMile", "validUntil"] {
            let raw = try fixture { body in
                var routes = body["routes"] as! [[String: Any]]
                var assessment = routes[0]["mappedProfileAssessment"] as! [String: Any]
                switch field {
                case "engine": assessment[field] = ["provider": "valhalla", "version": "3.8.3", "costing": "truck", "fallbackUsed": false]
                case "lastMile":
                    var mile = assessment[field] as! [String: Any]; mile["distanceM"] = 26; assessment[field] = mile
                case "validUntil": assessment[field] = "2020-01-01T00:00:00Z"
                default: assessment[field] = "invalid"
                }
                routes[0]["mappedProfileAssessment"] = assessment; body["routes"] = routes
            }
            XCTAssertThrowsError(try raw.verifyingKnownClosures(for: request).verifyingMappedProfile(request), field)
        }
    }

    func testActualRecordedEightRoutesAtTheirOriginalTimestampWhenAvailable() throws {
        let url = URL(fileURLWithPath: "/private/tmp/cop-mapped-live-accepted.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Private live acceptance replay is not part of the source repository") }
        struct Record: Decodable {
            struct Sample: Decodable {
                struct Request: Decodable { let from, to: CSMRoutePoint; let alternatives: Int; let includeRoadAttributes: Bool; let vehicleProfile: CSMMappedVehicleProfile }
                let request: Request; let response: CSMDriverRouteResponse
            }
            let samples: [Sample]
        }
        let record = try CSMJSONCoding.decoder.decode(Record.self, from: Data(contentsOf: url))
        XCTAssertEqual(record.samples.count, 8)
        for sample in record.samples {
            let request = CSMDriverRouteRequest(from: sample.request.from, to: sample.request.to, alternatives: sample.request.alternatives,
                includeRoadAttributes: sample.request.includeRoadAttributes, vehicleProfile: sample.request.vehicleProfile)
            let originalTime = try XCTUnwrap(sample.response.routes.first?.knownClosures?.observedAt).addingTimeInterval(1)
            let response = try sample.response.verifyingKnownClosures(for: request, at: originalTime).verifyingMappedProfile(request, at: originalTime)
            try response.requireValidMappedProfile(at: originalTime)
            XCTAssertTrue(response.mappedProfileVerified)
        }
    }
}
