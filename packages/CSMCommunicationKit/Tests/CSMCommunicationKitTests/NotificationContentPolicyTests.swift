import CSMNotificationCore
import XCTest

final class NotificationContentPolicyTests: XCTestCase {
    func testDirectMessageIsPresentedWithoutServerPlaintext() {
        let result = CSMNotificationContentPolicy.presentation(
            userInfo: [
                "category": "message.direct",
                "roomId": "!private-room:example.test",
                "eventId": "$event",
                "title": "SERVER TITLE MUST NOT LEAK",
                "body": "SERVER BODY MUST NOT LEAK",
                "accessToken": "secret"
            ],
            preferredLanguage: "cs-CZ"
        )

        XCTAssertEqual(result.title, "Nová zabezpečená zpráva")
        XCTAssertFalse(result.body.contains("SERVER"))
        XCTAssertEqual(result.categoryIdentifier, "CSM_CHAT")
        XCTAssertEqual(result.sanitizedUserInfo["roomId"], "!private-room:example.test")
        XCTAssertNil(result.sanitizedUserInfo["accessToken"])
        XCTAssertNil(result.sanitizedUserInfo["title"])
        XCTAssertNotNil(result.threadIdentifier)
        XCTAssertFalse(result.threadIdentifier?.contains("private-room") == true)
    }

    func testSafetyAlertUsesSafetyCategoryAndEnglishFallback() {
        let result = CSMNotificationContentPolicy.presentation(
            userInfo: ["type": "safety_alert", "alert_id": "alert-42"],
            preferredLanguage: "en-US"
        )

        XCTAssertEqual(result.title, "Safety alert")
        XCTAssertEqual(result.categoryIdentifier, "CSM_SAFETY_ALERT")
        XCTAssertEqual(result.sanitizedUserInfo["alertId"], "alert-42")
        XCTAssertNotNil(result.targetContentIdentifier)
    }

    func testRejectsCredentialedOrUntrustedDeepLinksAndControlCharacters() {
        let credentialed = CSMNotificationContentPolicy.presentation(
            userInfo: ["deepLink": "https://user:password@cop.zeleznalady.cz/chat"]
        )
        let untrusted = CSMNotificationContentPolicy.presentation(
            userInfo: ["deepLink": "https://evil.example/chat", "roomId": "room\u{0000}id"]
        )

        XCTAssertNil(credentialed.sanitizedUserInfo["deepLink"])
        XCTAssertNil(untrusted.sanitizedUserInfo["deepLink"])
        XCTAssertNil(untrusted.sanitizedUserInfo["roomId"])
    }

    func testOpaqueThreadIdentifierIsStable() {
        let first = CSMNotificationContentPolicy.presentation(
            userInfo: ["category": "message.group", "roomId": "!stable:example.test"]
        )
        let second = CSMNotificationContentPolicy.presentation(
            userInfo: ["category": "message.group", "roomId": "!stable:example.test"]
        )

        XCTAssertEqual(first.threadIdentifier, second.threadIdentifier)
        XCTAssertEqual(first.threadIdentifier?.count, 29)
    }
}
