# Phase 2 iOS feasibility report

## Status

In progress. The repository now contains a buildable iOS/iPadOS 26 feasibility
host, but Phase 2 is not accepted until the stable-Xcode CI job and physical
device scenarios complete. Simulator or beta-Xcode success is not a release
claim.

## Implemented baseline

- XcodeGen 2.44.1 source project with Swift 6, iOS/iPadOS 26.0 deployment
  target and Debug/Staging/Release configurations;
- persistent `WKWebsiteDataStore.default()` host for the existing remote COP
  web, with App-Bound Domains and exact origin comparison;
- production bridge only on `https://cop.zeleznalady.cz`; OIDC navigation on
  `https://login.zeleznalady.cz` never receives Device API;
- explicit debug-only `http://localhost:4311`; staging is deliberately
  unconfigured and fails closed while OQ-001 remains open;
- named `WKContentWorld`, `WKScriptMessageHandlerWithReply`, main-frame checks,
  64 KiB JSON limit and session invalidation on navigation;
- protocol `1.0.0` handshake and read-only `system.getCapabilities` response;
  every other namespace is truthfully `unsupported` in this phase;
- bounded duplicate request-ID cache that rejects reuse with different
  content;
- native loading, blocked and fresh-install/offline fallback surfaces with
  Retry and non-sensitive diagnostic codes;
- external links leave the internal WebView; no native auth token handling,
  permission prompt, sensor, background mode, entitlement or storage exists;
- COP Device contract `1.0.0` pinned to COP commit
  `38db4442fc6aa4d5df0cf788e9e0e9d9aa61e576` with shared fixtures as a
  read-only artifact.

## Verification performed

| Check | Result | Evidence boundary |
| --- | --- | --- |
| Repository skeleton | Pass | local shell |
| Contract lock/manifest integrity | Pass, 19 fixtures | local Python validator |
| Release/debug/staging config audit | Pass | local Python validator |
| XcodeGen generation | Pass | XcodeGen 2.44.1 |
| Swift build and tests | Pass, 8 tests | iOS 26.5 simulator |
| Toolchain used locally | Compatibility only | Xcode 27.0 beta / SDK 27.0 |
| Stable Apple toolchain gate | Correctly rejects local toolchain | requires CI Xcode 26.5 |
| Physical iPhone/iPad | Not run | required before Phase 2 acceptance |
| Real Keycloak login/refresh/logout | Not run | physical-device OQ-002 |
| Warm-cache process-kill airplane start | Not run | physical-device OQ-013 |
| Signing/TestFlight | Not run | OQ-004 and Apple team input |

The simulator tests cover exact-origin policy, lookalike origins and ports,
main-frame enforcement, compatible/incompatible handshake, session invalidation,
truthful capabilities, duplicate request IDs and selected pinned fixtures.

## Remaining Phase 2 gates

1. Run GitHub `macos-26` CI with stable Xcode 26.5 and iOS 26 SDK. The workflow
   explicitly selects `/Applications/Xcode_26.5.app` and rejects other major
   toolchains.
2. Confirm the real staging COP and OIDC origins; until then the Staging build
   cannot leave its configuration fallback.
3. Confirm Apple Team, bundle-ID succession and signing policy before a signed
   device build.
4. On a physical iPhone and iPad with iOS/iPadOS 26, test COP map/chat, actual
   Keycloak lifecycle, bridge absence in iframe/OIDC/external origins, process
   kill and fresh/warm offline start.
5. Record device/OS builds and results here without tokens, exact location,
   private content or screenshots containing sensitive data.
