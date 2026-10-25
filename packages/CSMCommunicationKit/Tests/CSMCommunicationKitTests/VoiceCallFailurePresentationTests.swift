import Foundation
import XCTest
@testable import CSMCommunicationKit

final class VoiceCallFailurePresentationTests: XCTestCase {
    func testPolicyServiceFailureExplainsUnstartedCallWithoutExposingTransport() {
        let value = CSMVoiceCallFailurePresentation.message(for: HTTPResponseFailure(statusCode: 503, code: "COMMUNICATION_POLICY_UNAVAILABLE"))
        XCTAssertTrue(value.contains("ověřit"))
        XCTAssertTrue(value.contains("nebyl zahájen"))
        XCTAssertFalse(value.contains("HTTP"))
        XCTAssertFalse(value.contains("COMMUNICATION_"))
    }

    func testUnknownServerOrLocalizedErrorCannotLeakTechnicalOrUntrustedText() {
        struct Untrusted: LocalizedError { var errorDescription: String? { "private token / internal exception" } }
        let errors: [any Error] = [HTTPResponseFailure(statusCode: 500, code: "PRIVATE_INTERNAL_CODE"), Untrusted()]
        for error in errors {
            let value = CSMVoiceCallFailurePresentation.message(for: error)
            XCTAssertFalse(value.contains("PRIVATE"))
            XCTAssertFalse(value.contains("private token"))
            XCTAssertFalse(value.contains("500"))
        }
    }

    func testPermissionAndNetworkErrorsRetainActionableInstructions() {
        XCTAssertTrue(CSMVoiceCallFailurePresentation.message(for: CSMVoiceCallControlError.authenticationRequired).contains("Přihlášení"))
        XCTAssertTrue(CSMVoiceCallFailurePresentation.message(for: URLError(.notConnectedToInternet)).contains("připojení"))
        XCTAssertTrue(CSMVoiceCallFailurePresentation.message(for: HTTPResponseFailure(statusCode: 403, code: nil)).contains("blokování"))
    }
}
