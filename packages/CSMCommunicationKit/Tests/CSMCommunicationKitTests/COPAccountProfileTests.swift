import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import CSMCommunicationKit

final class COPAccountProfileTests: XCTestCase {
    func testProfileIsBoundToVerifiedSubjectIssuerAndBoundedRevision() throws {
        let profile = try fixture()
        XCTAssertTrue(COPProfileBoundary.matches(profile, issuer: "https://synthetic.test", subject: "synthetic-a"))
        XCTAssertFalse(COPProfileBoundary.matches(profile, issuer: "https://other.test", subject: "synthetic-a"))
        XCTAssertFalse(COPProfileBoundary.matches(profile, issuer: "https://synthetic.test", subject: "synthetic-b"))
        XCTAssertFalse(COPProfileBoundary.validRevision("\"\r\nInjected: value"))
        XCTAssertFalse(COPProfileBoundary.matches(try fixture(avatar: "https://private.example/image"), issuer: "https://synthetic.test", subject: "synthetic-a"))
        XCTAssertFalse(COPProfileBoundary.matches(try fixture(revision: "short"), issuer: "https://synthetic.test", subject: "synthetic-a"))
    }
    func testLoginHintIsPresentationOnlyAndCannotOverridePKCEOrPrompt() throws {
        let url = try OIDCAuthorizationRequestBuilder.makeURL(authorizationEndpoint: URL(string: "https://synthetic.test/authorize")!, clientId: "client", redirectURI: "csm://oauth/callback", scope: "openid", state: "STATE", nonce: "NONCE", challenge: "CHALLENGE", challengeMethod: "S256", policy: .init(forceAuthentication: true), loginHint: " test+one@example.test ")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first(where: {$0.name == "login_hint"})?.value, "test+one@example.test")
        XCTAssertEqual(items.first(where: {$0.name == "state"})?.value, "STATE")
        XCTAssertEqual(items.first(where: {$0.name == "nonce"})?.value, "NONCE")
        XCTAssertEqual(items.first(where: {$0.name == "code_challenge_method"})?.value, "S256")
        XCTAssertEqual(items.first(where: {$0.name == "prompt"})?.value, "login")
        XCTAssertEqual(items.filter({$0.name == "login_hint"}).count, 1)
        XCTAssertNil(try validatedCOPLoginHint(nil)); XCTAssertNil(try validatedCOPLoginHint(" "))
        for hint in ["a@example.test\r\n", "a b@example.test", "not-an-email", String(repeating: "x", count: 255)+"@example.test"] {
            XCTAssertThrowsError(try validatedCOPLoginHint(hint))
        }
    }
    @MainActor func testAvatarIsFreshBoundedRasterWithoutOriginalGPSMetadata() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1100, height: 600)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1100, height: 600))
        }
        let source = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(source, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 50.0, kCGImagePropertyGPSLongitude: 14.0], kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "SYNTHETIC_PRIVATE_METADATA"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let prepared = try COPAvatarImage.prepare(source as Data)
        XCTAssertLessThanOrEqual(prepared.count, 180000)
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(prepared as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 512)
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertFalse(String(decoding: prepared, as: UTF8.self).contains("SYNTHETIC_PRIVATE_METADATA"))
        XCTAssertThrowsError(try COPAvatarImage.prepare(Data()))
        XCTAssertThrowsError(try COPAvatarImage.prepare(Data(repeating: 0, count: 10485761)))
        XCTAssertThrowsError(try COPAvatarImage.prepare(Data("bad image".utf8)))
    }
    private func fixture(avatar: String? = nil, revision: String = String(repeating: "a", count: 64)) throws -> CSMCOPAccountProfile {
        let values: [String: Any] = ["contractVersion": "cop-account-profile-v1", "subjectId": "synthetic-a", "issuer": "https://synthetic.test", "displayName": "Synthetic", "email": "synthetic@example.test", "emailVerified": true, "avatarDataUrl": avatar as Any? ?? NSNull(), "revision": revision, "updatedAt": NSNull(), "serverTimestamp": "2026-10-05T12:00:00Z"]
        return try JSONDecoder().decode(CSMCOPAccountProfile.self, from: JSONSerialization.data(withJSONObject: values))
    }
}
