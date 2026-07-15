import Foundation
import XCTest

@testable import COPMobile

final class WebNavigationResponsePolicyTests: XCTestCase {
  func testSuccessfulMainFrameResponseIsAllowed() throws {
    let response = try makeResponse(statusCode: 200)

    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: true,
        recoveryAttempted: false
      ),
      .allow
    )
  }

  func testRedirectMainFrameResponseIsAllowed() throws {
    let response = try makeResponse(statusCode: 302)

    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: true,
        recoveryAttempted: false
      ),
      .allow
    )
  }

  func testBadGatewayRetriesOnlyOnce() throws {
    let response = try makeResponse(statusCode: 502)

    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: true,
        recoveryAttempted: false
      ),
      .retry
    )
    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: true,
        recoveryAttempted: true
      ),
      .fail
    )
  }

  func testClientErrorFailsWithoutRenderingServerPage() throws {
    let response = try makeResponse(statusCode: 401)

    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: true,
        recoveryAttempted: false
      ),
      .fail
    )
  }

  func testSubframeErrorDoesNotReplaceTheApplicationSurface() throws {
    let response = try makeResponse(statusCode: 502)

    XCTAssertEqual(
      WebNavigationResponsePolicy.action(
        for: response,
        isForMainFrame: false,
        recoveryAttempted: false
      ),
      .allow
    )
  }

  private func makeResponse(statusCode: Int) throws -> HTTPURLResponse {
    try XCTUnwrap(
      HTTPURLResponse(
        url: URL(string: "https://cop.zeleznalady.cz/")!,
        statusCode: statusCode,
        httpVersion: "HTTP/2",
        headerFields: ["Content-Type": "text/html"]
      )
    )
  }
}
