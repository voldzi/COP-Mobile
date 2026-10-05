import Foundation
import XCTest
@testable import CSMCommunicationKit

final class SharedVehicleOdometerSnapshotTests: XCTestCase {
    func testKnownTypedSnapshotRoundtripAndRevisionGate() throws {
        let value = CSMSharedVehicleOdometerSnapshot(status: .known, dataRevision: 8, valueKm: "120.5", observedAt: "2026-10-05T11:00:00.123Z", source: .init(recordId: UUID(), recordRevision: 1, recordKind: .energy))
        let restored = try JSONDecoder().decode(CSMSharedVehicleOdometerSnapshot.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.knownValueKm(for: 8), "120.5")
        XCTAssertNil(restored.knownValueKm(for: 7))
    }
    func testUnknownReviewAndUnsupportedVersionDoNotBecomeZeroOrKnown() {
        for value in [CSMSharedVehicleOdometerSnapshot(status: .unknown, dataRevision: 1, reason: .no_observations), .init(status: .reviewRequired, dataRevision: 1, reason: .decreasing_observation), .init(version: 2, status: .known, dataRevision: 1, valueKm: "100")] {
            XCTAssertNil(value.knownValueKm(for: 1))
        }
        XCTAssertNil(CSMSharedVehicleOdometerSnapshot(status: .known, dataRevision: 1, valueKm: "bad").knownValueKm(for: 1))
    }
    func testLegacyVehicleStillDecodesWithNoSnapshot() throws {
        let json = #"{"contractVersion":"cop-shared-vehicles-v1","vehicleId":"00000000-0000-4000-8000-000000000001","details":{"name":"Synthetic"},"dataRevision":1,"membershipRevision":1,"members":[],"createdAt":"2026-10-05T11:00:00Z","updatedAt":"2026-10-05T11:00:00Z","deleted":false}"#
        XCTAssertNil(try JSONDecoder().decode(CSMSharedVehicle.self, from: Data(json.utf8)).odometerSnapshot)
    }
}
