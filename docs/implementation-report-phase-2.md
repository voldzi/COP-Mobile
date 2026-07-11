# Phase 2 iOS feasibility report

## Status

In progress. The repository now contains a buildable iOS/iPadOS 26 feasibility
host, but Phase 2 is not accepted until the approved Xcode 27 beta CI job and
physical-device scenarios complete. Simulator success is not a physical-device
or release-distribution claim.

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
| Approved Apple toolchain gate | Pass | Xcode 27.0 beta `27A5218g` / SDK 27.0 |
| GitHub iOS job | Runner online, job assigned | outbound run-service endpoint currently times out |
| Signed generic iOS device builds | Pass | Debug + Release, confirmed Team/bundle/profile |
| Signed-app entitlement audit | Pass | only app ID, Team ID and debug `get-task-allow` |
| Physical iPhone launch | Pass | iPhone 16 Pro Max / iOS 27.0, production COP map rendered |
| Physical iPad | Not run | required before Phase 2 acceptance |
| Real Keycloak login/refresh/logout | Not run | physical-device OQ-002 |
| Warm-cache process-kill airplane start | Not run | physical-device OQ-013 |
| Signing configuration | Confirmed | Team `LM6W548X36`, bundle `cz.zeleznalady.csm.messenger` |
| Signed device install | Pass | `CSM Dev 0.1.0 (1)` replaced approved legacy test install |
| TestFlight | Not run | distribution gate |

The simulator tests cover exact-origin policy, lookalike origins and ports,
main-frame enforcement, compatible/incompatible handshake, session invalidation,
truthful capabilities, duplicate request IDs and selected pinned fixtures.

## Remaining Phase 2 gates

1. The trusted runner `voldzi-mac-cop-mobile-xcode27` is registered, online and
   protected from `pull_request` jobs. Complete the assigned iOS job when
   outbound HTTPS to the GitHub Actions run-service endpoint is reachable.
2. Confirm the real staging COP and OIDC origins; until then the Staging build
   cannot leave its configuration fallback.
3. Add a physical iPad with iPadOS 26 or newer.
4. On the physical iPhone and iPad, test COP chat, actual
   Keycloak lifecycle, bridge absence in iframe/OIDC/external origins, process
   kill and fresh/warm offline start.
5. Record device/OS builds and results here without tokens, exact location,
   private content or screenshots containing sensitive data.
