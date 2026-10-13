# ADR 0024: Local suspension of an existing host voice service

Status: validated source candidate, not yet published; native host/device acceptance pending.
Date: 2026-10-13. Follows [ADR 0023](0023-host-owned-communication-activation.md).

## Decision

An explicit host OFF operation must not construct `VoiceCallService.shared`.
The additive static `suspendExisting(expectedScope:expectedGeneration:)` reads
only an existing backing instance. An absent instance returns `notInitialized`.
The signed `CSMCommunicationActivationPolicy` retains the standalone automatic
default. Explicit OFF and invalid policy create no CallKit, PushKit or audio
resources, including when a host accidentally reads `shared`.

Explicit activation binds the service and each operation to the opaque account
scope, SDK generation, private voice epoch and captured installation endpoint.
`resumeForHostCommunication` validates the current enabled SDK snapshot; an old
account or OFF/ON generation cannot authorize a producer. The four runtime voice
methods freeze explicit ownership before `startIfNeeded` and recheck it before
calling the model. Optional arguments retain automatic source compatibility,
but their omission cannot bypass explicit host consent.

The four model operations pass an immutable request-local issuer, subject,
opaque scope and SDK generation into the production HTTP adapter. Scoped token
acquisition checks the credential revision and selected actor after Keychain and
refresh awaits. HTTP rejects a different selected bearer and unsupported scoped
adapters instead of using an unscoped fallback. Each transport attempt validates
the current model on MainActor immediately before starting its URLSession task,
with no suspension between that check and task resume. Local JWT claim comparison
binds token selection only; COP remains responsible for signature, permission and
authorization checks. No token or actor context is logged or persisted by this
fence. Automatic calls without a requested fence retain their existing path.

Suspension fences producers before awaiting anything, cancels call-start,
polling, reconciliation and token-recovery work, clears the local token and sets
the installation's PushKit `desiredPushTypes` to an empty set. It stops only the
owned microphone/media path and local presentation. Its teardown emits neither
a server call transition nor a timeline-change notification. It does not sign
out OAuth/Matrix, delete history, kick a LiveKit identity or terminate a call
held by another application/device. Remote cleanup is unsupported by the current
producer-gated voice API and needs server assistance; local OFF is not remote
call or grant revocation. The assistance marker belongs to its captured account
scope, does not appear for another account, and is not cleared by local ON.

CallKit provider and PushKit registry identities belong to a voice epoch.
Retired providers remain report-only while an owned registry or incoming report
still exists. They cannot activate audio or produce work for a newer account.
There are at most two retained bindings in total: one active plus one retired,
or two retired while activation waits. `systemCleanupPending` rejects another
resume before audio initialization or provider allocation. Pending report counts
include repeated late deliveries and foreground reconciliation. A retired binding
is removed and its provider invalidated only after its registry and every report
completion have drained; no timer treats a pending OS report as completed.
Room observers bind the actual Room identity, call UUID and captured owner;
events from an old room cannot update a newly active one.

Apple documents a single provider for the current user and leaves account mapping
to the application. The automatic COP Mobile path retains that lifetime. Explicit
hosts use separate epoch identities because audio activation/deactivation callbacks
do not carry a call UUID; the old identity must not change a new owner's engine.
The bounded report-only overlap above is a source design, not proof of native
provider-lifetime or audio acceptance. It requires the physical tests below.
[Apple's provider lifecycle guidance](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit).

An incoming VoIP push already delivered to a retained system provider still
receives the mandatory CallKit report. A retired or invalidated owner performs
only report, local end and completion exactly once, without authentication,
reconciliation, media or server decline. If OFF occurs during a pending report,
its completion ends the report on the original provider and cannot remove a
same-UUID call belonging to a newer epoch. Existing terminal-push bookkeeping
remains local; server delivery policy for terminal VoIP pushes is a separate
review. [Apple's PushKit rule](https://developer.apple.com/documentation/pushkit/pkpushregistrydelegate/pushregistry(_:didreceiveincomingpushwith:for:completion:)).

The signed global/China distribution decision is unchanged. China and unknown
distribution never construct CallKit or PushKit. The automatic COP Mobile
startup continues using its existing system/in-app behavior.

## Acceptance

Controlled tests must cover cold noncreating OFF, blocked producer callbacks,
permission/start/report awaits, account and same-UUID epoch changes, local-only
held incoming cleanup, once/reentrant completion and automatic/China regression.
Tests must also hold a foreground reconciliation report across OFF, verify the
two-binding cap until duplicate reports drain, and deliver retired audio callbacks
while a newer binding owns audio. A legitimate new-account poll is allowed; an
old-account permission result must neither start/install a call nor poll under
the new identity.
Runtime tests must pause A at `startIfNeeded`, establish enabled B, then prove
that the old request sends no voice operation as B. The repository's complete
`scripts/check.sh` runs on the final source.

The final targeted native run passed 65/65 with terminal exit 0 on Xcode 27.1
build 27A9275, iOS SDK 27.1 and the iOS 27.1 simulator. The suites covered host
consent (20), embedded surface (2), lifecycle contracts (18), Voice controls (20)
and actual production HTTP/token-provider code with a synthetic URLProtocol (5).
The complete `scripts/check.sh` gate also passed with terminal exit 0 on the same
Swift source: skeleton/toolchain/device/iOS contract checks, 30 app unit tests,
5 app UI tests, 285 package tests (283 passed, 2 existing environment-dependent
skips), 2 accessibility tests and diff checking. The skipped cases require a
private recorded-route replay and an entitled system Keychain runner; neither is
represented as passed. No new Voice/scoped HTTP test was skipped. This is not a
physical-device or server acceptance.

Physical iPhone audio, CallKit/PushKit delivery and simultaneous Jízda/COP Mobile
acceptance are not established by simulator or fake controls. They remain
unverified. This source change activates no production server or provider feature.

Integration: [host voice handoff](../host-voice-suspension-handoff.md).
