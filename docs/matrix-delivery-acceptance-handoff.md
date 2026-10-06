# Jízda / COP Mobile — Matrix delivery and voice successor acceptance

## Scope and integration

Successor branch: `codex/matrix-send-ack-safety`, based on immutable complete release
`9d060a768fd0e0857830698af1e25bfca3ec0a7d` (including the complete `108f4c2` union).
The publication commit is supplied with the final handoff; do not pin a dirty tree.

Use the whole `packages/CSMCommunicationKit` tree. The existing
`CSMCommunicationHost` API and server contracts are unchanged. No host migration,
account reset, installation seed change, data wipe or trust bypass is required.
Over-install preserving Keychain, Matrix stores, encrypted outbox, local history,
SwiftData/CloudKit and memberships. [ADR 0022](adr/0022-exact-matrix-delivery-and-lifecycle.md)
defines storage and lifecycle semantics.

## Implemented boundaries

- An encrypted durable journal records each draft part before SDK queue entry.
  It retains original provider/homeserver/user/device scope and Matrix room ID;
  a new room binding for the same COP conversation cannot consume the old journal.
- `queuing` with unknown SDK ID and `queued` without exact acknowledgement remain
  pending across restart. Neither timeout nor exception creates a fresh send.
- Full native transaction IDs are retained without prefix normalization/truncation.
  An exact queue `sentEvent` or own remote event's `unsigned.transaction_id` binds
  the original transaction to a `$` server event. Every multipart part must be
  confirmed; upload completion alone does not acknowledge delivery.
- Text, reply, attachment, location and safety event sends share the guarded path.
  All app producers of SDK queue events are serialized. The pinned SDK replays
  existing queue items synchronously before returning the subscription handle;
  those IDs form the excluded baseline. Ambiguous fresh IDs do not select an ACK.
- No implicit `ignoreDeviceTrustAndResend` / `withdrawVerificationAndResend` is
  performed. Bounded queue failure categories communicate an explicit action.
  Unknown or old unscoped drafts remain held. Pending uncertain submissions cannot
  be deleted through ordinary pending redaction/discard.
- The host surface resolves access directly from the observed authentication/model
  and its expected subject, so a completed process warm start cannot strand it
  behind a cached checking state. Loading, locked and mismatched identities remain
  blocked by the same identity policy.
- Token refresh/reconfiguration terminates stale timeline streams, reattaches the
  selected conversation and fences async timeline cache creation/snapshot delivery.
  A late A configure cannot suspend current B. Sign-out stops the live-location
  producer before invalidating the transport; late registration callbacks cannot
  publish into a signed-out or different account.
- Waiting for an answer is distinct from room/media/server-ACK setup. Setup and
  waiting for the server media acknowledgement retain one absolute 45-second budget across bounded setup stages.
  Ringing expiry remains the server's responsibility. Both native readiness and
  server `connected` are required for connected UI/CallKit.

### Verified upstream queue boundary

Swift Matrix dependency `7605a7b64a7a3219a82c36a95f37b79b6de204ca` (26.09.17)
points to Rust `9c2fdc6531dd4b60a95ff573bba96c3ea4009b9d`.
Its [room subscription implementation](https://github.com/matrix-org/matrix-rust-sdk/blob/9c2fdc6531dd4b60a95ff573bba96c3ea4009b9d/bindings/matrix-sdk-ffi/src/room/mod.rs)
delivers initial local echoes before returning the handle. The FFI SendHandle does
not expose a transaction getter. Tests exercise replay, delayed duplicate replay,
ambiguous fresh IDs, full-ID equality and wrong-room ACK rejection using the
actual SDK callback types. This is source and simulator evidence, not a live
Matrix delivery test.

## Privacy-safe diagnostics

Registration emits only `stage` (`cop_ticket`, `messaging_registration` or
`registration_preparation`), HTTP status and an allowlisted error code. Unknown
server text becomes `unknown_code`; transport/client failures are bounded.
No ticket, token, body, identity, key or endpoint URL is included in this new log.
Read the registration diagnostic after both devices resume; a COP 202 alone does
not prove the second Messaging registration succeeded.

Voice diagnostics retain at most 96 entries and record bounded phase/stage,
direction, room/peer/audio/microphone booleans and a random per-call correlation.
It is not a call, user or room ID. No raw exception or media credentials are added.
Export metadata only; do not share chat bodies or notification payloads.

## Verification

2026-10-06 targeted suite: **42 tests, 0 failures, explicit exit 0**.
`/private/tmp/cop-matrix-send-ack-targeted-final.log`.
Covers actual timeline-cache invalidation, stale configure/logout, non-vacuous
pusher prevention, exact/late ACK, encrypted restart, concurrent store writers,
multipart resume, account isolation, room rebind and account switch while removing
an acknowledged draft; HTTP categories and voice server-ACK deadline.

Additional regression gates: **7 voice deadline/policy tests, 0 failures**, and
**13 surface/journal tests, 0 failures**, both explicit exit 0.
`/private/tmp/cop-matrix-send-ack-voice-deadline-tests.log` and
`/private/tmp/cop-matrix-send-ack-surface-final-tests.log`.
The latter exercises actual warm-start state and a verified identity while push
preparation is paused, plus room-local failure diagnostics before live snapshot.

Full required `scripts/check.sh`: **explicit exit 0**, completed 2026-10-06
16:28 CEST on simulator `101C6F6D-5BD8-41EC-8183-9EBED780FDD7`, exact
Xcode27.1/27A9269, SDK27.1, minimum iOS26 unchanged.
`/private/tmp/cop-matrix-send-ack-check-final.log`.

- Skeleton, exact toolchain, 19 Device API fixtures and iOS project validation PASS.
- COP Mobile: 30 unit tests and 5 launch UI tests, 0 failures.
- SDK: 200 XCTest tests, 2 skips, 0 failures; 2 Swift Testing tests PASS.
- Accessibility: 2 tests, 0 failures; final git diff whitespace check PASS.
- Skips: optional private recorded-route fixture absent and system Keychain runner
  entitlement OSStatus -34018. Actual pinned Rust cipher/store tests ran separately
  and passed; this does not prove a locked physical phone's Keychain behavior.

The last code revision remained unchanged through this successful full gate.
Later documentation completion does not introduce source/configuration changes.
Retrieval in the isolated SDK root was unavailable; targeted source inspection
was used. No successful Chroma reindex is claimed.

Before the startup corrections, three full gates failed at map-to-chat workspace
assertions (2, 3, then 1 UI failures). Actual exported hierarchy showed the
"Otevírám chat" indicator. They are retained as `check-first-ui-failure.log`,
`check-second-ui-failure.log`, `check-third-ui-failure.log` under the same prefix;
UI test timeouts and assertions were not weakened. Cached access state and
blocking non-identity setup were subsequently corrected and covered by the
actual runtime/model regression tests. These findings do not prove the cause of
the earlier physical missing receiver message.

Earlier fixture errors and the terminated unbounded test wait are retained in
`/private/tmp/cop-matrix-send-ack-*-fixture-*.log`; they are not successful gates.

## Actual device and production evidence before this successor

Jízda1.2(17), SDK9d, was installed and launched independently on both actual phones.
Actual direction Jiřina→Jiří worked; Jiří→Jiřina did not deliver the controlled TEST
although the sender showed a tick. Calls failed; no live two-way audio acceptance.
The receiver screenshot still ended before the controlled sender message/call.
Registration on both phones logged HTTPResponseFailure but hid status and stage.
A receive reconfigure was observed; the source stream defect is proven, its causal
role in this particular missing message is an inference requiring successor tests.

Read-only COP/Messaging metadata confirmed both accounts have one shared direct,
encrypted conversation, the same Matrix room binding/canonical key and exactly two
matching members. It did not prove the actual phone's selected room or Matrix
membership/device mapping. COP ticket/device/call endpoints succeeded in the
controlled window. A generic local 45-second voice failure is not proof of HTTP503.

Actual upstream Messaging/Matrix is on `comm.home.cz`, not the local similarly
named container on docker.home.cz. Read-only health/version checks succeeded;
actual APNs delivery logs and SFU reachability remain unverified due to unavailable
approved SSH access to that upstream. No production restart/config/network change
was performed. Jízda's standalone read-only UI runner passed on both installed
phones without app reset; this proves UI control, not delivery.

## Joint phone acceptance (Jízda owns device operations)

1. Pin the published complete successor, pass Jízda build/gates and over-install
   without reset. Independently record both installed versions and running PIDs.
2. Confirm the selected canonical conversation/room and device registration
   status for each phone without exporting identifiers or secrets.
3. Unique controlled TEST in each direction. Record sender pending→exact ACK and
   actual receiver item/decryption. `sent` alone does not prove receiver receipt.
4. Same-account token refresh/background→foreground while this chat is selected;
   new receive must continue without changing chats. Offline send/restart must
   not create another SDK transaction. Multipart and trust-required errors must
   not repeat confirmed parts or bypass trust.
5. Account change/sign-out during stream/configure/send; no cross-account pending
   publication, pusher or late completion. Restore the original account normally.
6. Both directions: foreground outgoing/incoming, accept/reject/cancel/no-answer;
   actual bidirectional audio, app switching/audio route; lock/background push.
   Compare stage booleans with server state; validate bounded server-ACK outage.
7. Preserve crypto/recovery/outbox. Explicit trust/backup recovery is a separate
   user-authorized flow; do not use resets to manufacture a passing result.

Update actual results separately. Do not mark chat, incoming push or voice fixed
until this device matrix passes. Outstanding upstream/APNs access is a concrete
external blocker, not evidence that another host's API/container proves delivery.

## Rollback

Do not downgrade to SDK9d or an earlier reader while tracked journals exist: it
ignores their ownership/ACK metadata and may replay them. Preserve stores and ship
a forward correction retaining journal and exact-ACK guards. A failed acceptance
keeps the release unaccepted; it does not authorize data deletion, crypto reset,
plaintext or implicit trust changes. No COP/Messaging server release is included.
