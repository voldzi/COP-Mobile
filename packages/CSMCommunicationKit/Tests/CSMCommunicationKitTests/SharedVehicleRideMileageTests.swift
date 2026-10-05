import Foundation
import XCTest
@testable import CSMCommunicationKit

final class SharedVehicleRideMileageTests: XCTestCase {
    func testRideDetailsRoundtripKeepsStableTripAndNoGps() throws {
        let id = UUID()
        let value = CSMSharedVehicleRecordData.ride_summary(.init(kind: .ride_summary, distanceKm: "10.125", durationSeconds: 60, purpose: .work, details: .init(tripId: id, startedAt: "2026-10-05T02:00:00Z", endedAt: "2026-10-05T03:00:00Z")))
        let bytes = try JSONEncoder().encode(value)
        guard case .ride_summary(let decoded) = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: bytes) else { return XCTFail() }
        XCTAssertEqual(decoded.details?.tripId, id); XCTAssertNil(decoded.details?.endOdometerKm)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("latitude"))
        let legacy = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: Data(#"{"kind":"ride_summary","distanceKm":"10","durationSeconds":60,"purpose":"work"}"#.utf8))
        XCTAssertNil(legacy.recordDetailsVersion)
    }
    func testCalculatedMileageNeverBecomesKnownAndChecksExactBasisAndRevision() throws {
        let value = CSMSharedVehicleOdometerSnapshotV2(status: .estimated, dataRevision: 8, valueKm: "130.375", observedAt: "2026-10-05T04:00:00.000Z", basisKm: "100", basisObservedAt: "2026-10-05T01:00:00Z", basisSource: .init(recordId: UUID(), recordRevision: 1, recordKind: .odometer), includedRideCount: 2, unconfirmedDistanceKm: "30.375")
        let restored = try JSONDecoder().decode(CSMSharedVehicleOdometerSnapshotV2.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.estimatedValueKm(for: 8), "130.375")
        XCTAssertNil(restored.knownValueKm(for: 8)); XCTAssertNil(restored.estimatedValueKm(for: 7))
        let bad = CSMSharedVehicleOdometerSnapshotV2(status: .estimated, dataRevision: 8, valueKm: "999", observedAt: value.observedAt, basisKm: value.basisKm, basisObservedAt: value.basisObservedAt, basisSource: value.basisSource, includedRideCount: 2, unconfirmedDistanceKm: value.unconfirmedDistanceKm)
        XCTAssertNil(bad.estimatedValueKm(for: 8))
    }
    func testActualRideEndAndReviewUnknownUnsupportedVersionsRemainDistinct() {
        let actual = CSMSharedVehicleOdometerSnapshotV2(status: .known, dataRevision: 8, valueKm: "112", observedAt: "2026-10-05T03:00:00Z", source: .init(recordId: UUID(), recordRevision: 1, recordKind: .ride_summary))
        XCTAssertEqual(actual.knownValueKm(for: 8), "112"); XCTAssertNil(actual.estimatedValueKm(for: 8))
        for value in [CSMSharedVehicleOdometerSnapshotV2(status: .unknown, dataRevision: 8), .init(status: .reviewRequired, dataRevision: 8, reason: .anchor_overlap), .init(version: 3, status: .known, dataRevision: 8, valueKm: actual.valueKm, observedAt: actual.observedAt, source: actual.source)] {
            XCTAssertNil(value.knownValueKm(for: 8)); XCTAssertNil(value.estimatedValueKm(for: 8))
        }
    }
    func testCapabilitiesAndInitialOdometerAreExplicitAndLegacyUnknown() throws {
        let caps = CSMMobilityCapabilities(contractVersion: .cop_mobility_capabilities_v1, sharedVehiclesEnabled: true, dispatchEnabled: false, maxVehicleMembers: 5, maxGroupMembers: 200, registration: .unverified, dispatchTransport: .recipient_encrypted_latest_only, currencies: [.CZK], serverTimestamp: "2026-10-05T12:00:00Z", invitationDelivery: .verified_account_inbox)
        XCTAssertFalse(caps.supportsOdometerSnapshotV2); XCTAssertFalse(caps.supportsRideDetailsV1); XCTAssertFalse(caps.supportsInitialOdometer); XCTAssertFalse(caps.supportsCommutativeRideInsert)
        let seed = CSMSharedVehicleRecordData.odometer(.init(kind: .odometer, odometerKm: "100", initial: true))
        guard case .odometer(let decoded) = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: JSONEncoder().encode(seed)) else { return XCTFail() }
        XCTAssertEqual(decoded.initial, true)
    }
}
