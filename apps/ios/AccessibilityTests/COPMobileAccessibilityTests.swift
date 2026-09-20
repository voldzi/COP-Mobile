import XCTest

final class COPMobileAccessibilityTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["COP_UI_TESTING"] = "1"
        app.launchEnvironment["COP_UI_TEST_INITIAL_SURFACE"] = "chat"
        app.launchEnvironment["CSM_FORCE_PREVIEW_SERVICES"] = "1"
        app.launchEnvironment["CSM_RESET_UI_TEST_STATE"] = "1"
        app.launchEnvironment["CSM_PREVIEW_SIGNED_OUT"] = "0"
    }

    func testSignedOutCommunicationWorkspacePassesAccessibilityAudit() throws {
        app.launchEnvironment["CSM_PREVIEW_SIGNED_OUT"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["Přihlásit"].waitForExistence(timeout: 12))

        try app.performAccessibilityAudit(
            for: [
                .contrast,
                .dynamicType,
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
                .textClipped,
                .trait
            ]
        )
    }

    func testConversationWorkspacePassesAccessibilityAudit() throws {
        app.launch()
        XCTAssertTrue(app.otherElements["chat.workspace"].waitForExistence(timeout: 12))

        try app.performAccessibilityAudit(
            for: [
                .contrast,
                .dynamicType,
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
                .textClipped,
                .trait
            ]
        )
    }
}
