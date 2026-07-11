import Foundation

enum BridgeScripts {
  static let contentWorldName = "COPDeviceBridge"
  static let handlerName = "copDevice"
  private static let requestEvent = "__copDeviceRequestV1"
  private static let responseEvent = "__copDeviceResponseV1"

  static func isolatedRelay() -> String {
    """
    (() => {
      if (window.top !== window) return;
      window.addEventListener('\(requestEvent)', event => {
        if (typeof event.detail !== 'string') return;
        let message;
        try { message = JSON.parse(event.detail); } catch { return; }
        window.webkit.messageHandlers.\(handlerName).postMessage(message).then(
          response => window.dispatchEvent(new CustomEvent('\(responseEvent)', { detail: JSON.stringify(response) })),
          () => window.dispatchEvent(new CustomEvent('\(responseEvent)', { detail: JSON.stringify({
            kind: 'blocked',
            id: typeof message.id === 'string' ? message.id : '00000000-0000-4000-8000-000000000000',
            sentAt: new Date().toISOString(),
            error: { code: 'TRANSPORT_UNAVAILABLE', message: 'Native transport failed.', retryable: true }
          }) }))
        );
      });
    })();
    """
  }

  static func pageFacade(allowedOrigins: Set<WebOrigin>) throws -> String {
    let values = allowedOrigins.map(\.description).sorted()
    let encoded = try JSONSerialization.data(withJSONObject: values)
    guard let literal = String(data: encoded, encoding: .utf8) else {
      throw AppConfigurationError.invalidValue("bridge origins")
    }
    return """
      (() => {
        if (window.top !== window) return;
        const allowedOrigins = new Set(\(literal));
        if (!allowedOrigins.has(window.location.origin)) return;
        const listeners = new Set();
        window.addEventListener('\(responseEvent)', event => {
          if (typeof event.detail !== 'string') return;
          let message;
          try { message = JSON.parse(event.detail); } catch { return; }
          for (const listener of Array.from(listeners)) {
            try { listener(message); } catch { /* listener isolation */ }
          }
        });
        const transport = Object.freeze({
          postMessage(message) {
            const encoded = JSON.stringify(message);
            window.dispatchEvent(new CustomEvent('\(requestEvent)', { detail: encoded }));
          },
          subscribe(listener) {
            if (typeof listener !== 'function') throw new TypeError('listener must be a function');
            listeners.add(listener);
            return () => listeners.delete(listener);
          }
        });
        Object.defineProperty(window, '__COP_DEVICE_NATIVE_TRANSPORT__', {
          value: transport,
          configurable: false,
          enumerable: false,
          writable: false
        });
      })();
      """
  }
}
