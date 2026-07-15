# ADR 0010: Dedicated non-blocking WebKit runtime

## Status

Accepted — 2026-07-15

## Context

COP Mobile originally used `WKWebsiteDataStore.default()` and the same browser
service worker as Safari/PWA. On a physical iPhone, a stale service-worker
navigation repeatedly committed without finishing. A subsequent startup repair
waited for `WKWebsiteDataStore.removeData`, whose completion handler could also
remain pending. The result was an unbounded `Načítám COP` screen before a new
`WKWebView` even existed.

The native app already owns APNs/PushKit, its communication store and its
startup lifecycle. Sharing browser PWA navigation state provides little value
inside this boundary and couples first paint to opaque WebKit maintenance.

## Decision

- COP Mobile uses a stable, named, persistent `WKWebsiteDataStore` dedicated to
  this application. It is not the Safari/default profile and persists web OIDC,
  cookies, Local Storage and IndexedDB across normal launches.
- `WKWebView` is created immediately. Cache deletion, schema migration or an
  interrupted-navigation marker may never gate first paint.
- COP web detects the document-start native transport and does not register its
  browser service worker in COP Mobile. Safari and installed PWA clients retain
  their service worker.
- A navigation has an eight-second deadline, receives one retry with local and
  remote caches ignored, and then transitions to the local SwiftUI fallback.
- Automatic recovery does not delete cookies, Local Storage, IndexedDB, OIDC or
  native Matrix data. Any destructive reset remains an explicit support action.

## Consequences

- A corrupted Safari/PWA profile cannot block COP Mobile startup.
- Web authentication remains persistent but is isolated in the native host
  profile; the first build using this decision may require one fresh map login.
- Browser service-worker offline navigation is not claimed in COP Mobile. A
  guaranteed offline shell requires a separately versioned embedded artifact or
  another future ADR.
- Startup and failure behavior are bounded and testable without relying on a
  WebKit data-removal completion callback.

## Validation

- physical-device cold starts after install, force quit and interrupted load;
- proof that native transport suppresses service-worker registration while a
  normal browser still registers it;
- persistent login and IndexedDB state across two normal launches;
- eight-second retry and local fallback under unavailable HTTPS/TLS;
- no blank WebView or unbounded loading screen.
