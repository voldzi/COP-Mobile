import XCTest
@testable import CSMCommunicationKit

final class SharedVehicleAuditProfileTests: XCTestCase {
    func testProfileRetainsWholeCombinationAndRejectsUnsafeIntent() throws {
        let trailer = CSMSharedVehicleMappedTrailer(heightM: 2.4, widthM: 2, lengthM: 6, loadedWeightKg: 2000)
        let dimensions = CSMSharedVehicleMappedDimensions(heightM: 3, widthM: 2.5, lengthM: 10, loadedWeightKg: 5000, trailer: trailer)
        let p = CSMSharedVehicleRoutingProfile(mappedProfile: .init(intent: "car_with_trailer", vehicle: dimensions), powertrain: .plugInHybrid)
        XCTAssertTrue(p.isValid)
        let decoded = try JSONDecoder().decode(CSMSharedVehicleRoutingProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.mappedProfile.vehicle?.trailer?.loadedWeightKg, 2000)
        XCTAssertFalse(CSMSharedVehicleRoutingProfile(mappedProfile: .init(intent: "commercial_truck"), powertrain: .combustion).isValid)
        XCTAssertFalse(CSMSharedVehicleRoutingProfile(mappedProfile: .init(intent: "car", driverDeclaredAuthorization: true), powertrain: .electric).isValid)
        XCTAssertFalse(CSMSharedVehicleRoutingProfile(version: 2, mappedProfile: .init(intent: "car"), powertrain: .electric).isValid)
        XCTAssertFalse(CSMSharedVehicleRoutingProfile(mappedProfile: .init(intent: "unknown"), powertrain: .electric).isValid)
        let broken = CSMSharedVehicleMappedDimensions(heightM: 3, widthM: 2.5, lengthM: 10, loadedWeightKg: 1000, trailer: trailer)
        XCTAssertFalse(CSMSharedVehicleRoutingProfile(mappedProfile: .init(intent: "car_with_trailer", vehicle: broken), powertrain: .combustion).isValid)
    }
    func testLegacyVehicleAndVerifiedOwnerScope() throws {
        let owner = UUID(), local = UUID(), id = UUID(), other = UUID()
        let vehicle = CSMSharedVehicle(contractVersion: .cop_shared_vehicles_v1, vehicleId: id, details: .init(name: "Synthetic"), dataRevision: 4, membershipRevision: 2,
            members: [.init(accountId: owner, displayName: "Synthetic", role: .owner, capabilities: [.readVehicle], joinedAt: "2026-10-05T01:00:00Z")], createdAt: "2026-10-05T01:00:00Z", updatedAt: "2026-10-05T01:00:00Z", deleted: false, ownerBinding: .init(localVehicleId: local, ownerAccountId: owner))
        XCTAssertEqual(vehicle.verifiedOwnerVehicleId(for: owner), local)
        XCTAssertNil(vehicle.verifiedOwnerVehicleId(for: other))
        XCTAssertNil(vehicle.currentRoutingProfile(for: 4))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(vehicle)) as? [String: Any]); json.removeValue(forKey: "ownerBinding")
        let legacy = try JSONDecoder().decode(CSMSharedVehicle.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.ownerBinding); XCTAssertNil(legacy.activeCareReminders)
    }
    func testExactCorrectionAndAuditRoundtrip() throws {
        let recordId = UUID(), op = UUID()
        let request = CSMSharedVehicleRecordWrite(operationId: op, expectedDataRevision: 8, expectedMembershipRevision: 2, recordId: recordId, expectedRecordRevision: 3, occurredAt: "2026-10-05T01:00:00Z", timeZone: "UTC", data: .expense(.init(kind: .expense, category: .parking, amount: .init(currency: .CZK, minorUnits: "1200"))), correction: .init(recordId: recordId, recordRevision: 3, reason: "Synthetic correction"))
        let decoded = try JSONDecoder().decode(CSMSharedVehicleRecordWrite.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.correction?.recordId, recordId); XCTAssertEqual(decoded.correction?.recordRevision, 3); XCTAssertEqual(decoded.operationId, op)
        let audit = CSMSharedVehicleRecordAudit(action: "void", operationId: op, previousRecordId: recordId, previousRecordRevision: 3, reason: "Synthetic void")
        XCTAssertEqual(try JSONDecoder().decode(CSMSharedVehicleRecordAudit.self, from: JSONEncoder().encode(audit)).action, "void")
    }
    func testCareRequiresCompleteMatchingRevision() {
        let item = CSMSharedVehicleActiveCareItem(recordId: UUID(), recordRevision: 2, title: "Synthetic", dueAt: "2026-10-06T01:00:00.123Z", dueOdometerKm: "200.125")
        XCTAssertEqual(CSMSharedVehicleActiveCareReminders(dataRevision: 4, state: "complete", items: [item]).currentItems(for: 4)?.count, 1)
        XCTAssertNil(CSMSharedVehicleActiveCareReminders(dataRevision: 4, state: "complete", items: [item]).currentItems(for: 5))
        XCTAssertNil(CSMSharedVehicleActiveCareReminders(dataRevision: 4, state: "unavailable", items: []).currentItems(for: 4))
        XCTAssertNil(CSMSharedVehicleActiveCareReminders(dataRevision: 4, state: "complete", items: [item, item]).currentItems(for: 4))
        XCTAssertNil(CSMSharedVehicleActiveCareReminders(version: 2, dataRevision: 4, state: "complete", items: [item]).currentItems(for: 4))
    }
}
