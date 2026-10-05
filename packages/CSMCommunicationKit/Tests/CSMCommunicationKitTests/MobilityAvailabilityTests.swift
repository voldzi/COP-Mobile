import Foundation
import XCTest
@testable import CSMCommunicationKit

final class MobilityAvailabilityTests: XCTestCase {
    private let legacy = #"{"contractVersion":"cop-mobility-capabilities-v1","sharedVehiclesEnabled":true,"dispatchEnabled":true,"maxVehicleMembers":5,"maxGroupMembers":200,"registration":"unverified","dispatchTransport":"recipient_encrypted_latest_only","currencies":["CZK"],"serverTimestamp":"2026-10-05T12:00:00Z","invitationDelivery":"verified_account_inbox"}"#
    func testOldServerResponseRemainsCompatibleAndDoesNotInventReadiness() throws {
        let value = try JSONDecoder().decode(CSMMobilityCapabilities.self, from: Data(legacy.utf8))
        XCTAssertTrue(value.dispatchEnabled)
        XCTAssertNil(value.serviceAvailability)
    }
    func testVehicleAvailabilityIsIndependentOfDispatchForEveryState() throws {
        for state in ["ready", "recovering", "unavailable", "disabled"] {
            let body = String(legacy.dropLast()) + #", "serviceAvailability":{"sharedVehicles":"ready","dispatch":""# + state + #"","checkedAt":"2026-10-05T12:00:00Z"}}"#
            let value = try JSONDecoder().decode(CSMMobilityCapabilities.self, from: Data(body.utf8))
            XCTAssertEqual(value.serviceAvailability?.sharedVehicles, .ready)
            XCTAssertEqual(value.serviceAvailability?.dispatch.rawValue, state)
        }
    }
    func testUnexpectedAvailabilityFailsDecodingInsteadOfClaimingReady() {
        let body = String(legacy.dropLast()) + #", "serviceAvailability":{"sharedVehicles":"ready","dispatch":"invented","checkedAt":"2026-10-05T12:00:00Z"}}"#
        XCTAssertThrowsError(try JSONDecoder().decode(CSMMobilityCapabilities.self, from: Data(body.utf8)))
    }
}
