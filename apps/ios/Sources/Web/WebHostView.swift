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
      ),
      openNativeChat: model.openNativeChat
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
    let coordinator = context.coordinator
    bridge.eventSink = { [weak webView, weak bridge, weak coordinator] event in
      guard let webView else {
        bridge?.eventDeliveryDidFail(event)
        return
      }
      Task { @MainActor in
        do {
          _ = try await webView.callAsyncJavaScript(
            "window.\(BridgeScripts.nativeReceiverName)(message)",
            arguments: ["message": event],
            in: nil,
            contentWorld: contentWorld
          )
          coordinator?.bridgeEventDeliveryDidSucceed()
        } catch {
          bridge?.eventDeliveryDidFail(event)
          coordinator?.recoverFromBridgeEventDeliveryFailure()
        }
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
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate
  {
    private let appConfiguration: AppConfiguration
    private let model: AppModel
    private let originPolicy: OriginPolicy
    private weak var webView: WKWebView?
    private var bridge: DeviceBridgeCoordinator?
    private var handler: BridgeMessageHandler?
    private weak var contentController: WKUserContentController?
    private var contentWorld: WKContentWorld?
    private var lastReloadToken = 0
    private var bridgeEventRecoveryAttempted = false
    private var webRuntimeRecoveryAttempted = false
    private var loadGeneration = 0
    fileprivate weak var tapHaptics: UITapGestureRecognizer?

    private static let initialLoadDeadline: TimeInterval = 8
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
      webRuntimeRecoveryAttempted = false
      startNavigation(cachePolicy: .useProtocolCachePolicy)
    }

    private func startNavigation(cachePolicy: URLRequest.CachePolicy) {
      guard let webView else { return }
      loadGeneration += 1
      let generation = loadGeneration
      model.webDidStartLoading()
      webView.load(
        URLRequest(
          url: appConfiguration.initialURL, cachePolicy: cachePolicy,
          timeoutInterval: 30))
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialLoadDeadline) { [weak self] in
        guard let self, self.loadGeneration == generation else { return }
        Task { @MainActor in
          await self.handleLoadDeadline()
        }
      }
    }

    private func handleLoadDeadline() async {
      guard let webView else { return }
      if webRuntimeRecoveryAttempted {
        finishNavigationAttempt()
        bridge?.invalidateSession()
        model.webDidFail()
        return
      }

      webRuntimeRecoveryAttempted = true
      loadGeneration += 1
      let recoveryGeneration = loadGeneration
      bridge?.invalidateSession()
      webView.stopLoading()
      await PersistentWebRuntime.clearTransientData(
        from: webView.configuration.websiteDataStore
      )
      guard loadGeneration == recoveryGeneration else { return }
      startNavigation(cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
    }

    private func finishNavigationAttempt() {
      loadGeneration += 1
    }

    private func isCancelledNavigation(_ error: any Error) -> Bool {
      let error = error as NSError
      return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }

    func reloadIfNeeded(token: Int) {
      guard token != lastReloadToken else { return }
      lastReloadToken = token
      loadInitialPage()
    }

    func bridgeEventDeliveryDidSucceed() {
      bridgeEventRecoveryAttempted = false
    }

    func recoverFromBridgeEventDeliveryFailure() {
      guard !bridgeEventRecoveryAttempted else { return }
      bridgeEventRecoveryAttempted = true
      model.invalidateWebMedia()
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
      PersistentWebRuntime.markNavigationCommitted()
      bridge?.navigationDidCommit(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard originPolicy.allowsInternalNavigation(to: webView.url ?? appConfiguration.initialURL)
      else {
        finishNavigationAttempt()
        PersistentWebRuntime.markNavigationCompleted()
        model.webWasBlocked()
        return
      }
      finishNavigationAttempt()
      PersistentWebRuntime.markNavigationCompleted()
      model.webDidBecomeReady()
    }

    func webView(
      _ webView: WKWebView,
      didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: any Error
    ) {
      guard !isCancelledNavigation(error) else { return }
      finishNavigationAttempt()
      PersistentWebRuntime.markNavigationCompleted()
      bridge?.invalidateSession()
      model.webDidFail()
    }

    func webView(
      _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error
    ) {
      guard !isCancelledNavigation(error) else { return }
      finishNavigationAttempt()
      PersistentWebRuntime.markNavigationCompleted()
      bridge?.invalidateSession()
      model.webDidFail()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      finishNavigationAttempt()
      PersistentWebRuntime.markNavigationCompleted()
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
      guard
        originPolicy.allowsMicrophoneCapture(
          frameURL: frame.request.url,
          mainFrameURL: webView.url,
          requestingScheme: origin.protocol,
          requestingHost: origin.host,
          requestingPort: origin.port,
          isMainFrame: frame.isMainFrame,
          microphoneOnly: type == .microphone
        )
      else {
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
      finishNavigationAttempt()
      bridge?.invalidateSession()
      bridge?.detachEventReceiver()
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

@MainActor
enum PersistentWebRuntime {
  private static let cacheSchemaVersion = 1
  private static let cacheSchemaKey = "COPWebRuntimeCacheSchemaVersion"
  private static let interruptedNavigationKey = "COPWebRuntimeNavigationInterrupted"
  private static let transientWebsiteDataTypes: Set<String> = [
    WKWebsiteDataTypeFetchCache,
    WKWebsiteDataTypeDiskCache,
    WKWebsiteDataTypeMemoryCache,
    WKWebsiteDataTypeServiceWorkerRegistrations,
  ]

  static func prepareForLaunch() async {
    await prepareForLaunch(defaults: .standard) {
      await clearTransientData(from: .default())
    }
  }

  static func prepareForLaunch(
    defaults: UserDefaults,
    clearTransientData: @MainActor () async -> Void
  ) async {
    let cacheSchemaChanged = defaults.integer(forKey: cacheSchemaKey) < cacheSchemaVersion
    let previousNavigationWasInterrupted = defaults.bool(forKey: interruptedNavigationKey)
    if cacheSchemaChanged || previousNavigationWasInterrupted {
      await clearTransientData()
    }
    defaults.set(cacheSchemaVersion, forKey: cacheSchemaKey)
    defaults.set(false, forKey: interruptedNavigationKey)
  }

  static func markNavigationCommitted(defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: interruptedNavigationKey)
  }

  static func markNavigationCompleted(defaults: UserDefaults = .standard) {
    defaults.set(false, forKey: interruptedNavigationKey)
  }

  static func clearTransientData(from dataStore: WKWebsiteDataStore) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      dataStore.removeData(
        ofTypes: transientWebsiteDataTypes,
        modifiedSince: .distantPast
      ) {
        continuation.resume()
      }
    }
  }
}
