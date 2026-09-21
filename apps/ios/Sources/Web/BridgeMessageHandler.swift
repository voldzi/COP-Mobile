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
    let envelope = message.body as? [String: Any]
    let bridgeMessage = envelope?["message"] ?? message.body
    let userInitiated = envelope?["userInitiated"] as? Bool ?? false
    let response = await bridge.handle(
      message: bridgeMessage,
      context: DeviceBridgeCoordinator.RequestContext(
        isMainFrame: message.frameInfo.isMainFrame,
        frameURL: message.frameInfo.request.url,
        mainFrameURL: webView?.url,
        isUserInitiated: userInitiated
      )
    )
    return (response, nil)
  }
}
