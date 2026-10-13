# Host voice suspension handoff

Source integration following published authentication pin
`5b346c517e7d993ad948fdd00132eefbc953352c`. Use the immutable revision supplied
with the handoff. Jízda integration and physical-device acceptance remain
separate from the source and simulator results below.

## Public additions

- `VoiceCallService.existingHostState`: optional readback without initialization.
- `VoiceCallService.suspendExisting(expectedScope:expectedGeneration:)`: local
  stop of an existing service; `notInitialized`, `ownerMismatch`,
  `automaticPolicy` or `suspended(VoiceCallHostState)`.
- `service.resumeForHostCommunication(expectedScope:expectedGeneration:)`:
  checks the current enabled account snapshot before activating resources;
  `systemCleanupPending` means existing OS reports/registry references must drain
  before another provider may be allocated.
- `service.hostState`: opaque scope/generation, local `suspended` and
  `serverAssistanceRequired`. None of these values confirms remote revocation.
- Runtime `startVoiceCall`, `voiceCall`, `activeVoiceCalls` and
  `transitionVoiceCall` accept optional `expectedScope`/`expectedGeneration`.
  Supply both or neither. Explicit hosts are fenced even when both are omitted;
  automatic existing callers keep their default path.

No server schema, permission, distribution key or provider credential changes.

The built-in adapter freezes the selected issuer/subject, opaque SDK scope and
generation for these four operations. It checks account/credential changes across
token acquisition and refresh, rejects a wrong bearer, and rechecks the current
host on MainActor before each HTTP attempt starts. Unsupported custom scoped
adapters fail closed; never bridge them to the old unscoped overloads. Local token
claim parsing selects the actor; it does not replace server token verification.

## Jízda sequence

Keep `CSMCommunicationActivationPolicy=explicit_host_consent` and one COP login
in the existing account screen. Do not read `VoiceCallService.shared` from OFF
UI, app launch, a hidden chat surface or a cleanup callback.

For OFF, capture the current account snapshot before disabling the feature and
call the static noncreating suspension using its nonempty scope and generation.
Then await the existing SDK `setHostCommunicationEnabled(false, expectedScope:)`
operation. Read its new snapshot after completion; do not reuse an old enabled
generation. Keep registration removal pending when the SDK reports it pending.
Voice's local stop never calls the remote transition API. Report server assistance
when an existing or in-flight call could require remote cleanup. This marker is
account-scoped and survives local ON; it is not proof of a completed server cleanup.

The host account screen and authenticated shared-vehicle functions need not wait
for Matrix/pusher bootstrap to finish. During the host's own pending enable
operation, use its current owner ticket, a freshly read matching scope and new
SDK generation, `enabled=true` and verified authentication/routing state. The
snapshot is producer permission, not chat transport readiness. Invalidate the
ticket immediately on OFF/account change and recheck it after every await.
Pending registration removal must never be bypassed. Track chat availability
separately; do not create Voice from a hidden or disabled chat surface.

For Voice ON, complete the existing scoped enable operation and read its new current
enabled snapshot. Only then obtain the service and call scoped resume with that
snapshot. An account change or an old OFF result cannot stop the newer owner's
call. The service's local readback is not permission to bypass the current SDK
snapshot or its server checks.

An unaccepted incoming invitation is closed only in this application's local
UI/CallKit. It must not send global decline/end, including when COP Mobile uses
the same account. A delivered late VoIP push can still require a brief system
report followed immediately by local end; OFF does not claim confirmed removal
of a server registration or promise that APNs has no in-flight deliveries.
The same rule applies when OFF occurs during a foreground CallKit report. The
original binding completes and ends that local report; it does not decline the
shared invitation. At most two system bindings are retained. A blocked resume
keeps the service suspended rather than creating a third provider. Show the
`systemCleanupPending` state and retry only with a newly read current enabled SDK
snapshot after OS cleanup; do not treat the retained voice owner as current consent
or start a repeated activation loop.

## Verification status

The final targeted native run passed **65/65, terminal exit 0**. Controlled
cases cover cold OFF, delayed permission/start-response/report/notification work, A→B, same UUID
after OFF/ON, local-only cleanup, captured endpoint and completion exactly once.
Additional cases hold foreground reports, count duplicate late reports, enforce
the provider cap and ensure old audio callbacks cannot stop or activate B's engine.
The standalone automatic and China/unknown distribution branches are regression
gates. The five scoped HTTP cases use the real production adapter and OIDC token
provider with synthetic Keychain/URLProtocol controls; they issue no live COP,
OpenAI or APNs requests. The complete mandatory `scripts/check.sh` gate passed
with **terminal exit 0** on the same Swift source.

| Final gate | Result |
| --- | --- |
| Skeleton, pinned Apple toolchain, device contract, iOS project | Passed |
| COP Mobile app unit / UI | 30 / 5 passed |
| Complete shared package | 285 considered: 283 passed, 2 existing skips, 0 failures |
| Accessibility | 2 passed |
| Diff check and exact changed-Swift-source parity | Passed |

The existing skipped cases were `MappedProfileTests`' private live eight-route
replay (fixture absent from the source repository) and `MatrixLocalStoreTests`'
system Keychain create/reopen (unhosted package runner lacks entitlement,
OSStatus -34018). They require separate evidence; neither is recorded as passed.
All 65 targeted cases, including the new Voice and scoped HTTP tests, ran without
skips. HTTPClient and OIDC lifecycle regression suites also ran in the full gate.

The interim controlled run reached 55 tests with one failure, then its stuck
runner was terminated (exit 143). Host consent (20), host surface (2) and lifecycle
(18) passed. The failed Voice assertion incorrectly prohibited B's permitted poll
while A's old permission result was held; the corrected test permits only work
owned by B and still forbids any old A operation. This is not a final passing gate.
The first 65-test run also exposed one fixture-only failure: separately generated
synthetic JWT claim dictionaries had nondeterministic key order. The fixture now
uses sorted JSON keys; the assertion comparing the exact outbound bearer remains
unchanged. That run was terminated with exit 143 after its 65/1 result; both logs
are retained. The next run produced the passing 65/65 and actual terminal 0 above.

Toolchain: Xcode 27.1 (27A9275), iOS SDK 27.1, iOS 27.1 simulator
`FDD3B2FB-E099-4658-A875-5B6E1F553AD7`. Base source remains published authentication
pin `5b346c517e7d993ad948fdd00132eefbc953352c`. The exact 13 changed Swift-file
manifest for the passing run hashes to
`dd247450b724aaaffd840d429fc432de2a8134d3222a76f5930e0eb4f9338994`.

Real iPhone APNs/PushKit/CallKit/audio, foreground/background/locked screen and
Jízda + COP Mobile using one account remain **unverified**. No production change
or physical installation is claimed. In particular, simulator control tests do
not establish physical CallKit provider retirement or audio timing after OFF/ON.

Architecture: [ADR 0024](adr/0024-host-owned-voice-suspension.md).
