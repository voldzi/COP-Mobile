# Project Agent Guide

## Mission

This repository contains COP Mobile, a thin native iOS/iPadOS host for the
existing COP web application and a future Android host. Native code exposes
device capabilities; it must not duplicate COP chat, map, reporting, domain
workflow, authorization decisions, or AI orchestration.

The deployment target is iOS/iPadOS 26 or newer. Use the approved, exactly
pinned Xcode 27 beta toolchain and capability-gate newer APIs.

## Working Style

- Prefer retrieval before broad scans.
- Use Chroma MCP `search_code`, `search_docs`, `search_all`, then
  `get_file_context` when available.
- CLI fallback:
  `"/Users/voldzi/Documents/Development/18 2026/chromadb/tools/chroma-dev.sh" search-all "<query>" --root . --limit 5`.
- If retrieval is unavailable or insufficient, use targeted direct inspection
  and state that once.
- Read the COP contract and nearby implementation before changing bridge,
  authentication, offline, push, or relay behavior.
- Keep edits scoped and update affected current-state documentation and ADRs in
  the same change.

## Sources of Truth

- `README.md` and `docs/README.md` for project status and documentation map.
- `docs/architecture.md` for system boundaries and data flow.
- `docs/product-design.md` for the user experience and native surfaces.
- `docs/api.md` for consumed APIs and the COP Device API boundary.
- `docs/security.md` for bridge, storage, permission, push, and relay controls.
- `docs/test-strategy.md` for verification and real-device acceptance.
- `docs/adr/` for architecture decisions.
- `apps/ios/` and `apps/android/` once platform targets exist.
- COP `openapi/openapi.json` remains authoritative for COP REST APIs.
- COP owns the authoritative Device API schemas and TypeScript web SDK; this
  repository consumes a pinned contract artifact and validates shared fixtures.
- `AGENTS.md` and `CLAUDE.md` stay aligned unless an ADR documents a deliberate
  platform-specific difference.

## Architecture Invariants

- Web = UI, chat, map, business logic, domain outbox, and authorization.
- Native = secure host, permissions, sensors, notifications, protected local
  technical storage, Share Extension, background tracking, and transports.
- The bridge is versioned, schema-validated, main-frame only, origin-restricted,
  capability-based, rate-limited, and reset on navigation or WebView reload.
- Never expose a generic filesystem, arbitrary network request, reflection, or
  code-execution method to JavaScript.
- Large assets cross the bridge only as opaque handles; never as base64 or an
  absolute path.
- Background work is native-owned and durable. WebView timers are never a
  background execution mechanism.
- iOS relay is foreground/opportunistic. Production relay and sensitive relay
  payloads remain disabled until explicit security and interoperability gates
  pass.
- Do not use CallKit/PushKit for anything other than a real VoIP call.
- Do not claim guaranteed ringing, exact sensor accuracy, continuous iOS mesh,
  or successful delivery without platform/server acknowledgement.

## Related Repositories

- COP: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/01 COP`
- Legacy native reference: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/04 CSM messenger`
- CSM Messaging: `/Users/voldzi/Documents/Development/18 2026/DELTA_ACR/05 Messaging`

Do not modify a related repository merely for convenience. Contract changes
must be intentionally scoped, compatibility-safe, documented, and validated in
the owning repository.

## Environment

- Current phase: iOS feasibility host; XcodeGen/Swift target exists, but Xcode
  27 beta CI and physical-device acceptance are still open.
- Minimum target: iOS/iPadOS 26.
- Planned iOS baseline: Swift 6, SwiftUI, Observation, Swift Concurrency,
  WebKit, Core Location, Core Motion, UserNotifications, Keychain, and XcodeGen.
- Planned Android baseline: Kotlin, Compose, Coroutines, AndroidX WebKit, and
  the same device contract after iOS stabilization.
- Production builds must use the approved exact Xcode 27 beta / iOS SDK 27
  build recorded in ADR 0007 and enforced by the toolchain verifier.
- No REST server is provided by this repository, so it has no OpenAPI document.

## Validation

Current mandatory checks:

```bash
bash scripts/check.sh
python3 scripts/validate-device-contract.py
python3 scripts/validate-ios-project.py
```

`scripts/check.sh` includes `scripts/verify-apple-toolchain.sh`; do not bypass
the exact Xcode/SDK pin. Radio, background execution, push,
Share Extension, auth/offline acceptance and sensors require physical devices;
simulator success is insufficient.

If retrieval scope changes, run:

```bash
"/Users/voldzi/Documents/Development/18 2026/chromadb/tools/chroma-dev.sh" reindex --root .
```

## Security and Privacy

- Never commit secrets, APNs keys, provisioning profiles, signing identities,
  access/refresh tokens, Matrix recovery material, or production managed config.
- Never log exact location, notification payload content, shared files, chat
  content, auth tokens, raw peer identifiers, or cryptographic keys.
- Ask permissions only after an explicit user action and provide a usable
  denied/restricted fallback.
- Critical Alerts require Apple entitlement and explicit user authorization;
  a feature flag is not an entitlement.
- Relay transports do not replace end-to-end payload security, device identity,
  key distribution, rotation, or revocation.

## Application Skeleton Standards

- Keep `README.md`, `AGENTS.md`, `CLAUDE.md`, `.env.example`, all flat mandatory
  documents, `docs/adr/`, and `scripts/validate-skeleton.sh` present.
- Active documentation belongs in `docs/`; superseded analysis belongs in
  `docs/archive/`.
- This application provides no REST API. `docs/api.md` must retain the standard
  no-REST-API statement and point to consumed authoritative contracts.
- Never create undocumented endpoints or manually fork an authoritative schema.
- Never add secrets or undocumented configuration semantics.

## Change Discipline

- Preserve user changes and avoid broad formatting.
- Significant changes to architecture, contract, storage, auth, permissions,
  background behavior, distribution, or relay require an ADR.
- Keep release, privacy, permission, operations, and test documentation aligned
  with behavior.
- State every check not run and why; never report an emulator or mock as a
  physical-device result.

## Compact Instructions

- Preserve the current goal, touched files, commands already run, verification
  status, toolchain state, retrieval availability, and open production gates.
