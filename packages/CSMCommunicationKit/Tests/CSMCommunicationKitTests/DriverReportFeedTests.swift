import Foundation
import XCTest
@testable import CSMCommunicationKit

final class DriverReportFeedTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNearbyQueryFiltersOnServerBeforeResultLimit() throws {
        let query = try XCTUnwrap(DriverReportQuery.nearby(latitude: 50.08, longitude: 14.42, radiusMeters: 10_000).first)
        XCTAssertLessThan(query.west, 14.3)
        XCTAssertGreaterThan(query.east, 14.5)
        XCTAssertLessThan(query.south, 50.0)
        XCTAssertGreaterThan(query.north, 50.16)
        let params = Dictionary(uniqueKeysWithValues: query.queryItems.map { ($0.name, $0.value!) })
        XCTAssertEqual(params["limit"], "500")
        XCTAssertEqual(params["includeExpired"], "false")
        XCTAssertEqual(params["statuses"], "submitted,published")
        XCTAssertTrue(params["categories"]!.contains("traffic_accident"))
        XCTAssertFalse(params["categories"]!.contains("utility_outage"))
    }

    func testDatelineQuerySplitsAndPolarQueryRemainsValid() throws {
        let queries = try DriverReportQuery.nearby(latitude: 0, longitude: 179.99, radiusMeters: 10_000)
        XCTAssertEqual(queries.count, 2)
        for query in queries {
            XCTAssertGreaterThanOrEqual(query.west, -180)
            XCTAssertLessThanOrEqual(query.east, 180)
            XCTAssertLessThan(query.west, query.east)
        }
        let polar = try XCTUnwrap(DriverReportQuery.nearby(latitude: 90, longitude: 0, radiusMeters: 10_000).first)
        XCTAssertEqual(polar.west, -180)
        XCTAssertEqual(polar.east, 180)
    }

    func testInvalidAndUnboundedQueriesAreRejected() {
        XCTAssertThrowsError(try DriverReportQuery.nearby(latitude: .nan, longitude: 14, radiusMeters: 10_000))
        XCTAssertThrowsError(try DriverReportQuery.nearby(latitude: 50, longitude: 14, radiusMeters: .infinity))
        XCTAssertThrowsError(try DriverReportQuery.nearby(latitude: 50, longitude: 14, radiusMeters: 50_001))
    }

    func testFeedRejectsExpiredInactiveDistantAndNonTrafficObservations() {
        var expired = report("expired"); expired.validUntil = now
        var resolved = report("resolved"); resolved.status = "resolved"
        var distant = report("distant"); distant.location.lat = 51
        var unrelated = report("unrelated"); unrelated.category = .fire
        let valid = report("valid")
        let feed = DriverReportFeedProjector.project(
            [expired, resolved, distant, unrelated, valid, valid], latitude: 50.08, longitude: 14.42,
            radiusMeters: 10_000, now: now, mayBeIncomplete: true
        )
        XCTAssertEqual(feed.reports.map(\.id), ["valid"])
        XCTAssertTrue(feed.mayBeIncomplete)
        XCTAssertEqual(feed.fetchedAt, now)
        XCTAssertEqual(feed.reports.first?.confidence, .low)
    }

    func testFeedSortsByDistanceAndDecodesLegacyMissingSummaries() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let legacy = try decoder.decode(CommunityReport.self, from: Data(#"{"reportId":"legacy","category":"traffic_congestion","title":"Kolona","location":{"lat":50.08,"lon":14.42},"observedAt":"2026-01-01T12:00:00Z","status":"submitted","properties":{"validUntil":"2030-01-01T12:00:00Z"}}"#.utf8))
        XCTAssertEqual(legacy.confirmations.totalCount, 0)
        XCTAssertNotNil(legacy.validUntil)
        var far = report("far"); far.location.lat = 50.1
        let feed = DriverReportFeedProjector.project([far, legacy], latitude: 50.08, longitude: 14.42, radiusMeters: 10_000, now: now, mayBeIncomplete: false)
        XCTAssertEqual(feed.reports.map(\.id), ["legacy", "far"])
    }

    private func report(_ id: String) -> CommunityReport {
        CommunityReport(reportId: id, category: .trafficAccident, title: "Nehoda", description: nil,
            location: GeoPoint(lat: 50.08, lon: 14.42, accuracyM: 5, source: "device"), severity: .warning,
            status: "submitted", groupId: nil, groupName: nil, attachmentCount: 0,
            observedAt: now.addingTimeInterval(-30), validUntil: now.addingTimeInterval(600))
    }
}
