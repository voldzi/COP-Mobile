# Jízda lifecycle completion — source candidate

Date: 2026-10-11. This is a new immutable transfer delta, not production or
physical acceptance. Preserve the earlier first-phase archive and frozen host.

## Exact opt-in and identity

Use together `CSMAppScope=jizda_app_link`, `CSMOIDCClientId=jizda-mobile`,
`CSMOIDCRedirectScheme=jizda-cop` and the registered callback
`jizda-cop://oauth/callback`. COP/Messaging dedicated client provisioning must
be accepted before opt-in. Misconfigured dedicated identity fails closed.
Legacy csm-mobile preserves behavior and omits installationId. Do not copy
an old refresh token, reset users or erase SwiftData.

The installation UUID and accepted fence are in Keychain, scoped to issuer,
client, COP URL, actor and UUID. Migration accepts only the exact valid legacy
app-instance UUID. A device ID prefix or cached linked state proves neither
app ownership nor server authorization.

## Host launch and foreground

Before constructing voice, Dispatch, location or measurement producers, call
`copStartJizdaLifecycle()`. Auth-only restoration precedes a mandatory live
authenticated HTTPS link GET (no cache/cookies/redirect, HTTP200 only).
The SDK reconstructs Matrix transport before permitting producers; valid
bootstrap cache alone does not establish queue or sync readiness.

Public methods/events:

- `copJizdaLifecycleSnapshot()`;
- `copPrepareJizdaLifecycle(expectedScope:)` for fresh verification;
- `Notification.Name.csmJizdaLifecycleReadinessChanged`, with no payload.

The snapshot has readiness, opaque account scope hash and process-local
generation. `copJizdaLifecycleSnapshotIsCurrent(snapshot)` compares the full
current snapshot, including readiness, and rejects nil scope. A ready snapshot
from before a same-epoch accepted fence must fail. Only
`snapshot.permitsProducers` authorizes producer creation. On each event, read
the current snapshot and stop host-owned services when false. Recheck its
generation after every host await; never reuse an old snapshot. Unknown,
unavailable, fenced or transport-preparing state must not start producers.
Foreground reconstructs queues/sync/timeline before resuming; native Matrix
restore/resume checks revision and cancellation before queue/sync enabling.
Recovery bootstrap sends the same secure installationId.

Voice control and delayed session/media responses preserve captured account
and lifecycle generation. SDK cannot revoke a copied provider token or stop
host-owned audio; those need real provider and host acceptance.

## Measurements and migration

SDK accepts unchanged legacy client or exact dedicated opt-in. Grant/submit
require ready lifecycle before and after waits. Own read/revoke remain possible
when Matrix transport is unavailable. Do not regrant consent, restart collection
or upload old RAM queues on login.
COP intake remains exactclient and pilot subject cohort. Coordinated migration
requires both clients in COP's OIDC allowlist and explicit cleanup clients
csm-mobile,jizda-mobile so oldclient can read/revoke. Contributor remains
subject+UTCday and every accepted batch remains shadow_only. Narrowly adjust
the host-specific old csm-mobile guard.

## Contact, retention and incomplete cleanup

Approved contact: **podpora@zeleznalady.cz**. Use plain
`mailto:podpora@zeleznalady.cz` with no prefilled subject/content.
COP policy is `cop-communication-retention-90d-30d-180d-v1`. Explicit excerpt
expires at min(created+90days,firstclosure+30days), audit without text within
180days. Blocking lasts until unblock or account deletion. Disabling new
intake must preserve enforcement/retention and existing own receipts.
The SDK safety UI preserves an existing report retry and confirmed unblock
when intake capabilities arefalse; new report/block stays disabled. Block
cleanup captures the original actor/outbox and rechecks generation around
awaits, including before the host's onBlocked callback.

Unlink preserves common COP account/COP Mobile/vehicles/history/SwiftData.
Attested Matrix devices can be selectively removed in Messaging source.
Unknown legacy devices and LiveKit shared participant/token rejoin remain
pending; 202 is not completion. Whole-account erasure has a separate server
contract but lacks all11 provider proofs; no functioning deletion URL is
exposed. No production flag or real account was changed.

## Merge and verification

Use the complete v2manifest, hashes and base revision. Apply to a new frozen
snapshot and preserve newer expectedNotificationScope send-ack and
onAccountProfileRequested callback. Do not overwrite CommunicationModel or
host integration wholesale. Exact approved toolchain is Xcode27.1(27A9275),
iPhoneOS SDK27.1, minimumiOS26. Only Jízda owner runs serialized native
builds/physical installs. Isolated Foundation/source checks do not replace
native SDK/UI/real Matrix/APNs/LiveKit/two-phone acceptance.

Record coldstart, foreground transport/timeline reconstruction, accountchange
during awaits, fence during registration/voice/GPS/recovery, oldclient read/revoke,
503, restart and guard-preserving rollback separately. Exact published revisions
and executed checks are in the v2handoff manifest.

### Final frozen source verification — 2026-10-11

- 431 isolated Foundation checks passed on the final source.
- 52 source-boundary assertions passed; 14 Swift files syntax parsed.
- Skeleton, iOS project configuration, 19 device-contract fixtures and diff checks passed.
- 33 native XCTest cases are prepared; **0 were executed natively** for this delta.
- All 13 changed Swift files match the SHA-256 evidence manifest.

The harness uses synthetic HTTPS/Matrix clients and an injected Keychain adapter.
It does not establish native MatrixRustSDK, APNs, LiveKit, two-phone or physical
device acceptance. No production feature was activated. Jízda owns the serialized
native build and physical acceptance of this exact published delta.
