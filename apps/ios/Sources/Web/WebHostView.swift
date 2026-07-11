import SwiftUI
@preconcurrency import WebKit

struct WebHostView: UIViewRepresentable {
  let configuration: AppConfiguration
  let model: AppModel

  func makeCoordinator() -> Coordinator {
    Coordinator(configuration: configuration, model: model)
  }

  func makeUIView(context: Context) -> WKWebView {
    let webConfiguration = WKWebViewConfiguration()
    webConfiguration.websiteDataStore = .default()
    webConfiguration.limitsNavigationsToAppBoundDomains = true
    webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = true
    webConfiguration.allowsInlineMediaPlayback = true
    webConfiguration.mediaTypesRequiringUserActionForPlayback = []

    let contentController = WKUserContentController()
    let contentWorld = WKContentWorld.world(name: BridgeScripts.contentWorldName)
    let bridge = DeviceBridgeCoordinator(
      originPolicy: OriginPolicy(
        bridgeOrigins: configuration.bridgeOrigins,
        navigationOrigins: configuration.navigationOrigins
      )
    )
    let handler = BridgeMessageHandler(bridge: bridge)
    contentController.addScriptMessageHandler(
      handler, contentWorld: contentWorld, name: BridgeScripts.handlerName)
    contentController.addUserScript(
      WKUserScript(
        source: BridgeScripts.isolatedRelay(),
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true,
        in: contentWorld
      )
    )
    if let pageFacade = try? BridgeScripts.pageFacade(allowedOrigins: configuration.bridgeOrigins) {
      contentController.addUserScript(
        WKUserScript(
          source: pageFacade,
          injectionTime: .atDocumentStart,
          forMainFrameOnly: true,
          in: .page
        )
      )
    }
    webConfiguration.userContentController = contentController

    let webView = WKWebView(frame: .zero, configuration: webConfiguration)
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    webView.scrollView.contentInsetAdjustmentBehavior = .automatic
    #if DEBUG
      webView.isInspectable = true
    #else
      webView.isInspectable = false
    #endif

    handler.webView = webView
    let tapHaptics = UITapGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.webContentTapped))
    tapHaptics.cancelsTouchesInView = false
    tapHaptics.delegate = context.coordinator
    webView.addGestureRecognizer(tapHaptics)
    bridge.eventSink = { [weak webView] event in
      guard let webView else { return }
      Task { @MainActor in
        _ = try? await webView.callAsyncJavaScript(
          "window.\(BridgeScripts.nativeReceiverName)(message)",
          arguments: ["message": event],
          in: nil,
          contentWorld: contentWorld
        )
      }
    }
    context.coordinator.attach(
      webView: webView,
      bridge: bridge,
      handler: handler,
      contentController: contentController,
      contentWorld: contentWorld
    )
    context.coordinator.tapHaptics = tapHaptics
    context.coordinator.loadInitialPage()
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {
    context.coordinator.reloadIfNeeded(token: model.reloadToken)
  }

  static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
    coordinator.teardown()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
  }

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
    private let appConfiguration: AppConfiguration
    private let model: AppModel
    private let originPolicy: OriginPolicy
    private weak var webView: WKWebView?
    private var bridge: DeviceBridgeCoordinator?
    private var handler: BridgeMessageHandler?
    private weak var contentController: WKUserContentController?
    private var contentWorld: WKContentWorld?
    private var lastReloadToken = 0
    fileprivate weak var tapHaptics: UITapGestureRecognizer?

    init(configuration: AppConfiguration, model: AppModel) {
      appConfiguration = configuration
      self.model = model
      originPolicy = OriginPolicy(
        bridgeOrigins: configuration.bridgeOrigins,
        navigationOrigins: configuration.navigationOrigins
      )
    }

    func attach(
      webView: WKWebView,
      bridge: DeviceBridgeCoordinator,
      handler: BridgeMessageHandler,
      contentController: WKUserContentController,
      contentWorld: WKContentWorld
    ) {
      self.webView = webView
      self.bridge = bridge
      self.handler = handler
      self.contentController = contentController
      self.contentWorld = contentWorld
    }

    func loadInitialPage() {
      guard let webView else { return }
      model.webDidStartLoading()
      webView.load(
        URLRequest(
          url: appConfiguration.initialURL, cachePolicy: .useProtocolCachePolicy,
          timeoutInterval: 30))
    }

    func reloadIfNeeded(token: Int) {
      guard token != lastReloadToken else { return }
      lastReloadToken = token
      loadInitialPage()
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard let url = navigationAction.request.url else {
        bridge?.invalidateSession()
        model.webWasBlocked()
        return .cancel
      }

      if originPolicy.allowsInternalNavigation(to: url) {
        return .allow
      }

      bridge?.invalidateSession()
      if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
        _ = await UIApplication.shared.open(url)
      } else {
        model.webWasBlocked()
      }
      return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
      bridge?.navigationDidCommit(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard originPolicy.allowsInternalNavigation(to: webView.url ?? appConfiguration.initialURL)
      else {
        model.webWasBlocked()
        return
      }
      model.webDidBecomeReady()
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: any Error
    ) {
      bridge?.invalidateSession()
      model.webDidFail()
    }

    func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
    ) {
      bridge?.invalidateSession()
      model.webDidFail()
    }

    func webView(
      _ webView: WKWebView,
      requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo,
      type: WKMediaCaptureType,
      decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
      guard originPolicy.allowsMicrophoneCapture(
        frameURL: frame.request.url,
        mainFrameURL: webView.url,
        requestingScheme: origin.protocol,
        requestingHost: origin.host,
        requestingPort: origin.port,
        isMainFrame: frame.isMainFrame,
        microphoneOnly: type == .microphone
      ) else {
        decisionHandler(.deny)
        return
      }
      VoiceCallService.shared.requestMicrophoneAndPrepare { granted in
        decisionHandler(granted ? .grant : .deny)
      }
    }

    @objc func webContentTapped() {
      let feedback = UISelectionFeedbackGenerator()
      feedback.prepare()
      feedback.selectionChanged()
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      true
    }

    func teardown() {
      bridge?.invalidateSession()
      if let tapHaptics {
        webView?.removeGestureRecognizer(tapHaptics)
      }
      if let contentWorld {
        contentController?.removeScriptMessageHandler(
          forName: BridgeScripts.handlerName, contentWorld: contentWorld)
      }
      handler = nil
    }
  }
}
