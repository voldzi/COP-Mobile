import XCTest
import UserNotifications
@testable import CSMCommunicationKit

final class PushCategoryCoexistenceTests: XCTestCase {
    @MainActor
    func testSDKCategoryUpdatePreservesRideStartAndReplacesOnlyOwnedActions() {
        let ride = UNNotificationCategory(identifier: "RIDE_START_CATEGORY", actions: [UNNotificationAction(identifier: "START_RIDE", title: "Start", options: [.foreground])], intentIdentifiers: [])
        let other = UNNotificationCategory(identifier: "HOST_OTHER", actions: [], intentIdentifiers: [])
        let oldSDK = UNNotificationCategory(identifier: CSMNotificationCategoryIdentifier.chat, actions: [], intentIdentifiers: [])
        let updatedSDK = UNNotificationCategory(identifier: CSMNotificationCategoryIdentifier.chat, actions: [UNNotificationAction(identifier: "CSM_OPEN", title: "Open", options: [.foreground])], intentIdentifiers: [])
        let result = PushNotificationManager.mergingNotificationCategories(existing: [ride,other,oldSDK], owned: [updatedSDK])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.first { $0.identifier == "RIDE_START_CATEGORY" }?.actions.map(\.identifier), ["START_RIDE"])
        XCTAssertTrue(result.contains { $0.identifier == "HOST_OTHER" })
        XCTAssertEqual(result.first { $0.identifier == CSMNotificationCategoryIdentifier.chat }?.actions.map(\.identifier), ["CSM_OPEN"])
    }
}
