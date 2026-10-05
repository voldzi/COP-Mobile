import Foundation
import XCTest
@testable import CSMCommunicationKit

final class SharedVehicleRecordDetailsTests: XCTestCase {
    func testEnergyDetailsRoundtripAndOmitUnknownLegacyFields() throws {
        let data = CSMSharedVehicleRecordData.energy(.init(kind: .energy, unit: .liters, quantity: "40.5", amount: .init(currency: .CZK, minorUnits: "162000"), details: .init(kind: .refueling, odometerKm: "12345.7", note: "Synthetic note", refueling: .init(fuelType: "natural95", fullTank: true, quantityBeforeRefueling: "5", station: .init(name: "Synthetic station", provider: "Synthetic provider", address: "Synthetic address")))))
        let json = try JSONEncoder().encode(data)
        let restored = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: json)
        let first = try JSONSerialization.jsonObject(with: json) as! NSDictionary
        let second = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! NSDictionary
        XCTAssertEqual(first, second)
        let legacy = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: Data("{\"kind\":\"energy\",\"unit\":\"liters\",\"quantity\":\"1\"}".utf8))
        guard case .energy(let value) = legacy else { return XCTFail() }
        XCTAssertNil(value.details); XCTAssertNil(value.amount)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("latitude"))
    }
    func testServiceRemainsOneRecordWithDistinctItemIdsAndSingleTotal() throws {
        let data = CSMSharedVehicleRecordData.service(.init(kind: .service, title: "Servis", amount: .init(currency: .CZK, minorUnits: "300000"), details: .init(note: "Synthetic", items: [.init(itemId: UUID(), title: "Synthetic work", categoryId: "synthetic-category", amount: .init(currency: .CZK, minorUnits: "100000")), .init(itemId: UUID(), title: "Synthetic part", amount: .init(currency: .CZK, minorUnits: "200000"))])))
        let json = try JSONEncoder().encode(data)
        guard case .service(let decoded) = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: json) else { return XCTFail() }
        XCTAssertEqual(decoded.details?.items?.count, 2)
        XCTAssertEqual(decoded.amount?.minorUnits, "300000")
        XCTAssertEqual(decoded.details?.items?.first?.categoryId, "synthetic-category")
        XCTAssertNotEqual(decoded.details?.items?.first?.itemId, decoded.details?.items?.last?.itemId)
    }
    func testUnsupportedVersionIsRetainedForReadOnlyDetectionAndLegacyDoesNotAdvertiseSupport() throws {
        let data = try JSONDecoder().decode(CSMSharedVehicleRecordData.self, from: Data("{\"kind\":\"service\",\"title\":\"Synthetic\",\"details\":{\"version\":2}}".utf8))
        XCTAssertEqual(data.recordDetailsVersion, 2)
        XCTAssertFalse(data.canEditRecordDetailsV1)
        let cap = CSMMobilityCapabilities(contractVersion: .cop_mobility_capabilities_v1, sharedVehiclesEnabled: true, dispatchEnabled: false, maxVehicleMembers: 5, maxGroupMembers: 200, registration: .unverified, dispatchTransport: .recipient_encrypted_latest_only, currencies: [.CZK], serverTimestamp: "2026-10-05T12:00:00Z", invitationDelivery: .verified_account_inbox)
        XCTAssertFalse(cap.supportsRecordDetailsV1)
        let supported = CSMMobilityCapabilities(contractVersion: .cop_mobility_capabilities_v1, sharedVehiclesEnabled: true, dispatchEnabled: false, maxVehicleMembers: 5, maxGroupMembers: 200, registration: .unverified, dispatchTransport: .recipient_encrypted_latest_only, currencies: [.CZK], serverTimestamp: "2026-10-05T12:00:00Z", invitationDelivery: .verified_account_inbox, recordDetailsVersions: [1], recordEnergyUnits: ["liters", "kWh"], supportedRefuelingFuelTypes: ["natural95"])
        XCTAssertTrue(supported.supportsRecordDetailsV1)
    }
    func testChargingExplicitLocationAndBatteryRoundtripWithoutCoordinates() throws {
        let details = CSMSharedVehicleEnergyDetails(kind: .charging, note: "🙂", charging: .init(source: .publicDC, provider: "Synthetic", locationName: "Synthetic selected place", location: .init(name: "Synthetic", address: "Synthetic address"), batteryPercentBefore: "20", batteryPercentAfter: "80.5"))
        let data = try JSONEncoder().encode(details)
        let restored = try JSONDecoder().decode(CSMSharedVehicleEnergyDetails.self, from: data)
        XCTAssertEqual(restored.charging?.source, .publicDC)
        XCTAssertEqual(restored.charging?.batteryPercentAfter, "80.5")
        XCTAssertEqual(restored.charging?.location?.address, "Synthetic address")
        XCTAssertEqual(restored.note, "🙂")
    }
}
