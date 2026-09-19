import XCTest

final class COPMobileLaunchUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchEnvironment["COP_UI_TESTING"] = "1"
    app.launchEnvironment["COP_UI_TEST_INITIAL_SURFACE"] = "chat"
    app.launchEnvironment["CSM_FORCE_PREVIEW_SERVICES"] = "1"
    app.launchEnvironment["CSM_RESET_UI_TEST_STATE"] = "1"
  }

  func testNativeChatLaunchesWithoutWebKitOrSystemPermissionPrompt() {
    app.launch()

    XCTAssertTrue(
      app.otherElements["chat.workspace"].waitForExistence(timeout: 8),
      "UI smoke režim musí otevřít nativní chat bez WebKitu a systémového dialogu oprávnění."
    )
    XCTAssertFalse(
      app.alerts.firstMatch.exists,
      "Otevření samotného chatu nesmí vyvolat systémový dialog o oprávnění."
    )
    XCTAssertTrue(app.buttons["chat.createDirect"].exists || app.otherElements["chat.emptyConversationState"].exists)
  }

  func testChatRemainsReachableWhileMapLoads() {
    app.launchEnvironment["COP_UI_TEST_INITIAL_SURFACE"] = "cop"
    app.launch()

    let openChat = app.buttons["app.openNativeChat"]
    XCTAssertTrue(openChat.waitForExistence(timeout: 8))
    openChat.tap()
    XCTAssertTrue(app.otherElements["chat.workspace"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.alerts.firstMatch.exists)
  }

  func testChatRemainsReachableAfterMapFailure() {
    app.launchEnvironment["COP_UI_TEST_INITIAL_SURFACE"] = "cop"
    app.launchEnvironment["COP_UI_TEST_INITIAL_PHASE"] = "offline"
    app.launch()

    let fallback = app.descendants(matching: .any)["app.technicalFallback"]
    XCTAssertTrue(
      fallback.waitForExistence(timeout: 8),
      "Offline start must expose the technical fallback regardless of the accessibility role assigned by the current iOS runtime."
    )
    let openChat = app.buttons["Otevřít komunikaci"]
    XCTAssertTrue(openChat.waitForExistence(timeout: 4))
    openChat.tap()
    XCTAssertTrue(app.otherElements["chat.workspace"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.alerts.firstMatch.exists)
  }

  func testSignedOutNativeChatOffersExplicitSignIn() {
    app.launchEnvironment["CSM_PREVIEW_SIGNED_OUT"] = "1"
    app.launch()

    XCTAssertTrue(
      app.buttons["Přihlásit"].waitForExistence(timeout: 8),
      "Odhlášený stav musí uživatele srozumitelně navést k přihlášení."
    )
  }
}
