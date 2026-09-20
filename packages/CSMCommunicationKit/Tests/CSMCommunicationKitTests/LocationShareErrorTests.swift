import XCTest
@testable import CSMCommunicationKit

final class LocationShareErrorTests: XCTestCase {
    func testPermissionDeniedMessageIsReusableByAnyHostApplication() {
        let message = CSMCommunicationLocationShareError.permissionDenied.errorDescription
        XCTAssertEqual(
            message,
            "Přístup k poloze je vypnutý. Povolte jej pro tuto aplikaci v Nastavení."
        )
        XCTAssertFalse(message?.contains("COP Mobile") == true)
    }
}
