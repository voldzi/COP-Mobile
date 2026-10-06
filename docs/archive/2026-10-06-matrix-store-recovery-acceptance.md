# Matrix store repair: evidence 2026-10-06

Owner: COP Mobile-owned shared SDK, branch codex/matrix-store-recovery.
Immutable parent: 108f4c2b125bc75b312dcdc57240cd7842f60182. Parent checkout remained clean.
No phone reset, app reinstall/wipe, production restart, server account or network change.

## Final gate

Command: COP_IOS_SIMULATOR_ID=101C6F6D-5BD8-41EC-8183-9EBED780FDD7 bash scripts/check.sh.
Exit 0 confirmed by execution session 20812.
Xcode 27.1 build 27A9269 / SDK 27.1. iPhone Duo iOS 27.1 simulator.
Local diagnostic log: /private/tmp/cop-matrix-store-recovery-check-final.log.
Results: skeleton/toolchain/device contract/iOS config/diff-check PASS;
app unit 30/0 failures; UI 5/0; package XCTest 161/0, two skips;
Swift Testing 2/0; accessibility 2/0. Gate finished 2026-10-06 13:26:22 CEST.
Package skips: optional private roadtrip fixture, System Keychain OSStatus -34018.

## Targeted safety gate

Local diagnostic log: /private/tmp/cop-matrix-store-recovery-tests.log.
Session 93412 exit 0; 25 tests / 1 Keychain skip / 0 failures.
Actual pinned Rust builder/store cipher mismatch and original-key reopen are
real Rust tests, not fabricated Swift errors. SQLite existing account detection
was verified against actual Rust-created and restored stores. HTTP whoami/key
publication and the OIDC/bootstrap recovery loop use synthetic fixtures;
Keychain concurrency and duplicate winner use atomic backend fixtures.
Tests cover old zero-length/truncated data preservation, symlink exclusion,
backup exclusion, per-store serialization/cancellation, no stale true/false
readiness, no 401-driven device rotation, two account routing/cache isolation,
explicit confirmation, encrypted outbox preservation, cache-save failure and
selected-ID restart, account switch during recovery.

## Repairs and non-final runs

Initial compile found an invalid enum case in a newly written verifier; corrected.
The first real package Keychain test failed; adding exact internal OSStatus
identified missing runner entitlement (-34018). It remains explicitly skipped,
with physical signed-app acceptance outstanding. No production key was read.
An actual Rust restored-account detection test initially failed: read-only WAL
inspection needed immutable mode only when no WAL exists. Corrected, real test
then passed; unreadable/busy DB now throws retry-only storeUnavailable instead
of being treated as a fresh identity.
First complete gate log: /private/tmp/cop-matrix-store-recovery-check.log.
App unit 30 passed; one UI test runner terminated with TERM, next smoke launch
failed after runner restart. Cause is unconfirmed. Final full serial rerun passed.
Earlier sessions 9322,15053,25599,59402,93412,5205 were individually confirmed
terminated before the final gate was accepted. No simulator reset was used.

## Remaining acceptance

No actual phone/keychain, two-phone E2EE, real recovery-backup, locked-phone,
notification/voice/battery or physical navigation acceptance is claimed.
Jízda owns signed Debug integration/over-install and physical verification.
The provided test policy does not guarantee past-history decryption or remote
device trust. Old Matrix device was retained and is not automatically revoked.
COP REST/bootstrap stayed compatible; there was no production configuration change.
Retrieval and Chroma reindex on the new worktree returned tool errors; no fresh
index claim. Complete publishing revision is the commit containing this record.
