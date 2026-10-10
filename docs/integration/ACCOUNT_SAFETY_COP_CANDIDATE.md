# Account safety candidate on pinned SDK 09493a0

Prepared for Jízda's coordinated COP acceptance, not production activation.

The source-only SDK delta is `CSMAccountSafety.swift`, the appended optional
`idempotencyKey` parameter/header in `CSMMobility.swift`, and four XCTest cases
in `AccountSafetyContractsTests.swift`. Existing calls retain their nil default
and the original session/actor-generation guards. Do not overwrite Jízda's
host callback, notification, voice or send-ack patches.

COP contract: `cop-account-safety-v1`, binding
`delta_acr_cop/openapi/openapi.json` on `codex/account-deletion-moderation`.
Detailed endpoints, server enforcement, retention, privacy candidate, exact
unexecuted deployment plan and outstanding erasure are in COP
`docs/integration/40_ACCOUNT_SAFETY_APP_REVIEW.md`.

Public methods: capabilities; report with stable operation UUID; own report
status; read block state; block/unblock. Targets are user/message/call references
verified server-side. Evidence is optional, explicitly selected and confirmed,
at most 4096 UTF-8 bytes. No automatic timeline, transcript or decrypted history.
Render selected evidence as plain text and obtain confirmation before sending.
Do not follow links or render HTML from it. New APIs neither select an actor nor
choose an external AI key/model. No fallback to another actor/local-only block.

After a successful canonical block, hide the peer's older cached history and
explicitly discard their pending drafts; keep other group members and state
consistent. Report/block failures and unavailable capability are not successful
operations. The host must not expose an account-deletion action based on this
candidate: `accountDeletion=false`, and the actual erasure workflow/SDK are not
yet implemented. App Store release still requires those actual features and the
accepted moderation/filter/contact/retention process.

## Verification

Foundation model harness: PASS for metadata-only encoding, positive explicit
excerpt, refusal of missing confirmation/empty text and 4096-byte UTF-8 bound.
Four full SDK XCTest cases were added but not run as a native suite here.
Device-contract validation: PASS 19 fixtures. iOS-project validation: PASS.

Actual toolchain readback: `xcodebuild -version` gives Xcode 27.1,
Build version 27A9275; `xcrun --sdk iphoneos --show-sdk-version` gives 27.1.
This pinned baseline's `scripts/verify-apple-toolchain.sh:5` defaults to 27A9269,
aligned with AGENTS/CLAUDE and ADR0007. The verifier therefore fails on the
build identity, not on version 27.0 or on a missing toolchain. The pin has not
been changed or bypassed and no Xcode download was attempted. Jízda's existing
approval of its installed 27.1 and host tests must be handled by its owner:
apply this small delta to its accepted frozen snapshot and run the suite there.
Earlier host 230/571/scenario results do not cover this new delta.

Physical iPhone, real Matrix/APNs/LiveKit and account erasure were not tested.
No production restart, secret creation, account reset or app install occurred.
