import Foundation
import XCTest

@testable import CSMCommunicationKit

final class MatrixPushGatewayURLPolicyTests: XCTestCase {
    func testAlwaysResolvesCanonicalGatewayAtOriginRoot() throws {
        for base in [
            "https://messaging.example",
            "https://messaging.example/",
            "https://messaging.example///",
            "https://messaging.example/api/v1",
            "https://messaging.example/api/v1/",
            "https://messaging.example/api/v1/matrix/push/notify",
            "https://messaging.example/_matrix/push/v1/notify"
        ] {
            let resolved = MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base)))
            XCTAssertEqual(resolved?.absoluteString, "https://messaging.example/_matrix/push/v1/notify", base)
            XCTAssertNotEqual(resolved?.path, "/api/v1/matrix/push/notify", base)
        }
    }

    func testPreservesConfiguredOriginAndExplicitPort() throws {
        for (base, expected) in [
            ("https://messaging.example:8443/api/v1/", "https://messaging.example:8443/_matrix/push/v1/notify"),
            ("https://messaging.example:443/", "https://messaging.example:443/_matrix/push/v1/notify"),
            ("https://[2001:db8::1]:8443/api/v1", "https://[2001:db8::1]:8443/_matrix/push/v1/notify")
        ] {
            let resolved = MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base)))
            XCTAssertEqual(resolved?.absoluteString, expected)
        }
    }

    func testRejectsNonHTTPSOrMissingAuthority() throws {
        for base in ["http://messaging.example/", "ftp://messaging.example/", "file:///tmp/gateway", "/api/v1", "https:/api/v1"] {
            XCTAssertNil(MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base))), base)
        }
    }

    func testRejectsRelativeURLWithOtherwiseTrustedBase() throws {
        let base = try XCTUnwrap(URL(string: "https://messaging.example/"))
        let relative = try XCTUnwrap(URL(string: "api/v1", relativeTo: base))
        XCTAssertNil(MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: relative))
    }

    func testRejectsUserInformationIncludingEmptyUser() throws {
        for base in [
            "https://user@messaging.example/",
            "https://user:password@messaging.example/",
            "https://@messaging.example/",
            "https://:password@messaging.example/"
        ] {
            XCTAssertNil(MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base))), base)
        }
    }

    func testRejectsQueryOrFragmentIncludingEmptyDelimiters() throws {
        for base in [
            "https://messaging.example/api/v1?token=synthetic",
            "https://messaging.example/?",
            "https://messaging.example/#fragment",
            "https://messaging.example/#"
        ] {
            XCTAssertNil(MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base))), base)
        }
    }

    func testRejectsOutOfRangePort() throws {
        for base in ["https://messaging.example:0/", "https://messaging.example:65536/"] {
            XCTAssertNil(MatrixPushGatewayURLPolicy.resolve(messagingBaseURL: try XCTUnwrap(URL(string: base))), base)
        }
    }
}
