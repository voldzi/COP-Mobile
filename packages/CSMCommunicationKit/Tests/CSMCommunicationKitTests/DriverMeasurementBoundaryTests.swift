import XCTest
@testable import CSMCommunicationKit

final class DriverMeasurementBoundaryTests: XCTestCase {
    func testMinimizedSyntheticBatchAndForbiddenIdentity() throws {
        let point: [String: Any] = ["sampleId": UUID().uuidString, "observedAt": "2026-10-02T00:00:00Z",
            "lat": 50, "lon": 14, "horizontalAccuracyM": 3, "speedMps": 10, "speedAccuracyMps": 0.5,
            "headingDeg": 90, "headingAccuracyDeg": 5, "positionSource": "gps", "motion": "driving", "reducedAccuracy": false]
        var batch: [String: Any] = ["contractVersion": "cop-driver-measurements-v1", "batchId": UUID().uuidString,
            "contributorDay": "2026-10-02", "vehicleClass": "passenger_car", "points": [point, point, point]]
        XCTAssertTrue(CSMDriverMeasurementBatchPolicy.accepts(try JSONSerialization.data(withJSONObject: batch)))
        batch["contributorIdDay"] = "forbidden"
        XCTAssertFalse(CSMDriverMeasurementBatchPolicy.accepts(try JSONSerialization.data(withJSONObject: batch)))
        batch.removeValue(forKey: "contributorIdDay")
        var leaked = point; leaked["token"] = "forbidden"
        batch["points"] = [leaked, point, point]
        XCTAssertFalse(CSMDriverMeasurementBatchPolicy.accepts(try JSONSerialization.data(withJSONObject: batch)))
    }
    func testSessionMismatchFailsClosed() {
        XCTAssertFalse(CSMDriverMeasurementBatchPolicy.matchesSession(current: nil, expected: "a"))
        XCTAssertFalse(CSMDriverMeasurementBatchPolicy.matchesSession(current: "a", expected: "b"))
        XCTAssertFalse(CSMDriverMeasurementBatchPolicy.matchesSession(current: "", expected: ""))
        XCTAssertTrue(CSMDriverMeasurementBatchPolicy.matchesSession(current: "a", expected: "a"))
    }
}
