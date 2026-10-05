# Shared COP OIDC session — Jízda integration handoff

## Implementation

The device OIDC registry is shared by COP API/chat authentication, mobility and driver routing. The existing unpublished driver-measurement transport in this local checkout was also changed to use this registry; its preexisting uncommitted feature is not published as part of this fix.

Refresh has one owner, commits rotated tokens before releasing concurrent callers, checks session revision and confines invalid-grant cleanup to the original generation. Temporary network, locked credential storage and provider failures do not delete credentials. Restoration does not call Matrix sign-out, erase history or clear conversations.

## Public Swift interface

- `CSMMobilityFailureKind.classify(_ error: any Error) -> CSMMobilityFailureKind`.
- Cases: `authenticationRequired`, `accountChanged`, `temporaryNetwork`, `serviceUnavailable`, `configuration`, `invalidResponse`, `forbidden`, `rateLimited`, `cancelled`, `unknown`.
- `CSMCOPSessionError: LocalizedError, Sendable` exposes only `kind`.
- `CSMCOPSessionStatus`: `ready`, `signedOut`, `authenticationRequired`, `accountChanged`, `temporarilyUnavailable`, `configuration`.
- `runtime.mobilityCOPSessionStatus(expectedScope: String) async -> CSMCOPSessionStatus` checks/refreshed OIDC without Matrix logout. `ready` means a locally usable correctly bound credential, not successful authorization at every server endpoint.
- `runtime.mobilityRestoreSession(expectedScope: String) async throws` is an explicit user action for `authenticationRequired`. Do not call it for network/503/429 recovery. It forces browser authentication, checks the same issuer/subject before saving credentials and rejects a changed session. Concurrent renewal taps share one browser operation.
- Existing `mobilitySignIn(switchAccount: false)` checks OIDC when chat remains signed in and renews only confirmed expiration. It no longer blindly skips expired OIDC because Matrix chat works.
- Existing HTTP `CSMMobilityServiceFailure` remains unchanged: preserve status/code/correlation/Retry-After. Decoder errors mean `invalidResponse`; they are not expiration.

## Jízda integration

Keep account, capabilities, vehicles and invitations outcomes distinct. Clear permission-bearing capabilities when their validation fails. Show the renewal action only for authentication failures, retry for transient failure, and explicit account switching for `accountChanged`. Retain chat and account display during service outages without treating stale permissions as valid. Never log credentials, payload, coordinates or actor identifiers.

## Verification

Exact Xcode 27.1 (27A9269), iOS SDK 27.1 verified. Full package simulator regression: 104 tests, 0 failures, 1 skipped private road replay (103 passed), including 13 new OIDC/restoration tests. Skeleton, 19 device contract fixtures, iOS project validation and diff check passed. The first model test run exposed an empty preview fixture; the existing chat cache is now explicitly seeded and all final tests pass. Physical iPhone expired OIDC + working Matrix, cancellation, offline-to-online restoration and real IdP rotation remain unverified. No production user data was created and no server deployment is needed for this SDK change.
