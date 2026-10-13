# ADR 0025: Read-only host authentication witness

Status: source accepted and native gates completed; host/device acceptance pending.
Date: 2026-10-13. Follows [ADR 0023](0023-host-owned-communication-activation.md).

## Decision

`CSMCommunicationRuntime.hostAuthenticationSnapshot` is a synchronous, noncreating
read of verified COP identity and any required local unlock. Its public fields are
`identityReady`, `isVerifyingIdentity`, optional opaque `scope` and the current SDK
`generation`. No subject, credential, private context or producer capability is
included. Scope is absent until identity is ready.

The model maintains a separate, memory-only verification witness. Each identity
restore, login, bootstrap or recheck owns a fresh attempt. It clears an earlier
proof before its first identity await and publishes readiness only after the COP
bootstrap and required local unlock have completed for the current attempt.
Readiness is published before Matrix, pusher or device-registration awaits. A
failed recheck leaves the witness unready even when an existing OIDC session is
retained. Old identity and unlock completions, catches and loading defers cannot
finish a newer attempt. This witness is not the existing producer permission.
An ON attempt clears its old proof before publishing the new SDK generation and
keeps the same verification owner through the COP recheck and local unlock.

`.csmHostAuthenticationChanged` is a payloadless wakeup on begin, finish,
invalidation and local SDK generation changes. Hosts must reread the snapshot;
notification order or a captured snapshot does not establish current readiness.

Local communication OFF preserves a verified account and routing identity while
the returned SDK generation advances. An identity witness alone never starts
Matrix/APNs/PushKit, authorizes sharing, proves a remote grant or enables calls.
The existing communication snapshot, pending registration removal and scoped
operation fences remain authoritative for those separate checks. Standalone
COP Mobile's automatic default and the existing single native login remain.
Temporary verification is neither OFF nor logout and is not an instruction to
terminate an already admitted Voice service. New host admission uses a fresh
identity witness, while the existing `hostCommunicationSnapshot` remains the
producer authority. The host keeps `VoiceServicesAvailable` separate and only
makes it available after its authorized enable operation has completed, as
described in the Voice handoff.

A same-owner recheck publishes `identityReady=false`,
`isVerifyingIdentity=true`, `scope=nil`; a failed recheck publishes
`false`, `false`, `nil`. This read-only nil scope is not an OFF or account-change
signal and must not revoke a completed Voice admission. Failed COP identity
rechecks may retain the signed-in account and prior communication permission
while the authoritative fresh communication snapshot remains enabled with the
matching actual Voice owner and epoch. Its scope/generation/removal state stays
authoritative for existing services. A required biometric failure can legitimately
lock the session and change that authority. Only new pending admission requires
a fresh identity proof. The witness changes no producer permission or remote grant.

## Host use

Jízda can make Já and account-dependent car presentation responsive while an
already authorized enable operation waits for Matrix. It needs its own pending
operation ticket and fresh matching opaque scope/generation. Communication and
Voice producers still require a fresh enabled communication snapshot; no second
login, OAuth client, dedicated app link or producer bypass is introduced.

## Validation boundary

Seven deterministic fixture tests cover cold noncreating reads and payloadless
wakeups; held COP identity and local unlock; verified identity during held Matrix;
failed own recheck; old identity completion/defer and failed unlock versus a newer
account; and OFF preserving identity/routing with a fresh generation. Fixtures
inject authentication, push, messaging and driver transport explicitly.
The synchronous consent-wakeup case rejects an old identity proof on
the new ON generation, stays unready through held COP and unlock work, and then
is ready while Matrix remains held.

The seven new tests include the synchronous ON wakeup case. Actual validation on
Xcode 27.1 (27A9275), iOS SDK 27.1 and simulator
`FDD3B2FB-E099-4658-A875-5B6E1F553AD7`:

| Gate | Actual result |
| --- | --- |
| Changed Swift syntax / diff check | Passed |
| Final targeted suite | 72/72 passed, no skips, terminal exit 0 |
| Mandatory `scripts/check.sh` | Passed, terminal exit 0 |
| COP Mobile app unit / UI | 30/30 and 5/5 passed |
| Complete shared XCTest package | 292 considered: 290 passed, 2 existing skips, 0 failures |
| Package Swift Testing | 2/2 passed |
| Accessibility | 2/2 passed |

The existing skips are the unavailable private recorded eight-route fixture and
the unhosted runner's missing Keychain entitlement (OSStatus -34018). Neither is
recorded as passed. All 72 targeted cases ran without skips.

The first targeted run reached 72 tests with one fixture failure: the OFF test
mistakenly expected the preview provider to return a routing catalog, but that
fixture intentionally throws `safetyRequirementsUnavailable`. The corrected test
asserts this exact error, an actual auth-only transport counter increment, and
preserved identity/SDK generation boundaries without claiming valid navigation.
The old runner stalled after complete results; only its verified owned xcodebuild
was terminated (exit 143). The next targeted run passed with actual terminal 0.

Source base: published `7fbe8878d7a47d39fc3eff11a642511df99281be`.
The final exact three changed Swift-file manifest is
`/private/tmp/cop-sdk-auth-witness-final-source-20261013.json`, SHA256
`0470b15b9fa401728b9ad219459b548756f8589444537c3a9fb5f91397d010dd`.
Local logs: `cop-sdk-auth-witness-targeted-20261013.log` (first 72/1),
`cop-sdk-auth-witness-final-targeted-20261013.log` and
`cop-sdk-auth-witness-check-20261013.log`, all under `/private/tmp`.
No Swift changed after the final targeted/full gate.

Physical Face ID, APNs, background operation, CarPlay and Jízda host acceptance
remain unverified. No production change, physical installation or new OAuth client
is claimed by this local validation. Use the immutable source commit delivered
with this document; publication is a separate result from these native tests.
