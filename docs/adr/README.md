# Architecture Decision Records

Use ADRs for important, costly, risky, or hard-to-reverse technical decisions.

## Rules

- one ADR per decision
- keep ADRs short and decision-first
- include status and consequences
- do not rewrite history; supersede with a new ADR when needed

## Naming

- `0000-template.md`
- `0001-short-decision-title.md`
- `0002-another-decision.md`

## Current Decisions

- `0001-initial-architecture.md` — thin hybrid host and iOS 26 baseline
- `0002-versioned-secure-device-bridge.md` — COP Device API and WebView boundary
- `0003-remote-web-and-offline-bootstrap.md` — HTTPS web, cache and local fallback
- `0004-native-owned-background-tracking.md` — durable tracking outside WebView
- `0005-notification-delivery-boundaries.md` — audible, Critical and VoIP limits
- `0006-relay-experiment-production-gate.md` — relay POC and production gates
- `0007-approved-xcode-27-beta-toolchain.md` — pinned Xcode 27 beta build and CI boundary
- `0008-real-voip-pushkit-callkit.md` — real incoming-call wake and CallKit lifecycle
- `0009-native-communications-surface.md` — native E2EE chat and the superseded staged call design
- `0010-dedicated-webkit-runtime.md` — dedicated persistent WebKit profile without a browser service worker or blocking startup cleanup
- `0011-standalone-owned-communication-kit.md` — COP Mobile-owned local communication package without a legacy application dependency
- `0012-server-owned-direct-voice-calls.md` — direct native CallKit/PushKit/LiveKit calls with COP API as state authority
- `0013-bounded-native-chat-state.md` — screen-owned stores, one reducer, paged timeline, persistent outbox and measurable performance gates
- `0014-communication-only-native-domain.md` — communication-only native runtime; map, reports and business workflow remain in web COP
