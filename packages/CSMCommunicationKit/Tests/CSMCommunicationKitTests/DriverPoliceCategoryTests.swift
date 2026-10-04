import XCTest
@testable import CSMCommunicationKit

final class DriverPoliceCategoryTests: XCTestCase {
    @MainActor func testAllPublicCategoriesMapExactlyWithoutHazardFallback() {
        XCTAssertEqual(CSMDriverReportCategory.policePatrol.rawValue, "police_patrol")
        for category in CSMDriverReportCategory.allCases {
            XCTAssertEqual(CSMCommunicationRuntime.internalCategory(category).rawValue, category.rawValue)
        }
        let query = try? DriverReportQuery.nearby(latitude: 50, longitude: 14, radiusMeters: 1000)
        XCTAssertTrue(query?.first?.queryItems.first(where: {$0.name == "categories"})?.value?.contains("police_patrol") == true)
    }
}
