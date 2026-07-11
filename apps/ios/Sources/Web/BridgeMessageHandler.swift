import Foundation
@preconcurrency import WebKit

@MainActor
final class BridgeMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
  private let bridge: DeviceBridgeCoordinator
  weak var webView: WKWebView?

  init(bridge: DeviceBridgeCoordinator) {
    self.bridge = bridge
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) async -> (Any?, String?) {
    let response = await bridge.handle(
      message: message.body,
      context: DeviceBridgeCoordinator.RequestContext(
        isMainFrame: message.frameInfo.isMainFrame,
        frameURL: message.frameInfo.request.url,
        mainFrameURL: webView?.url
      )
    )
    return (response, nil)
  }
}
