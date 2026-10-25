# Shared chat-status and exact-echo SDK successor

## Source and scope

This selective successor starts at the published ACK-safety revision
`7bf711ea881fe563a25e5aaad5fb4729cb0d619e` on
`codex/communication62-published-ack`. The input is the reviewed Jízda 1.2 (62)
candidate; its source manifest SHA-256 is
`01b0432911feb63e309c0f0567d89a8b42913c0c3198739c8d66aabeb445a283`.
The manifest identifies source material, not a wholesale patch.

Included: exact draft/SDK/server echo presentation; preservation of proved
transaction links; typed unreadable-content causes; bounded SDK decryption
retry; actual own-device verification; a non-repeating status sheet with
separate history controls; human call-failure presentation and regressions.
Canonical refresh uses canonical account/store/recovery witnesses.

An additional upstream-only correction replaces the public arbitrary error
log in `VoiceCallService.failVisibleCall` with a fixed message. This does not
modify the frozen Jízda candidate or its manifest.

A second upstream review correction requires a typed SDK failure when a live
snapshot preserves older readable cache content. A legitimate new/edit text
exactly equal to a legacy placeholder, including `unable to decrypt`, replaces
the older text normally. Legacy body matching remains a compatibility hint for
old cached rows/UI, not live-snapshot provenance. A dedicated regression covers
the exact English and Czech strings, retained ACK identity and no extra send.

Unrelated older Jízda vendor changes to host lifecycle, push, consent, voice
engine, package pins and platform targets are excluded. Existing canonical
local-store recovery and advanced diagnostics are retained. The primary COP
Mobile checkout and Jízda source remain untouched by this port.

## Validation and delivery boundary

The approved installed Xcode 27.1 build `27A9275` is verified using the
previously human-approved `COP_REQUIRED_XCODE_BUILD=27A9275` override; repository
defaults are unchanged. Direct approval is the human reply in Jízda chat
`01a0c94c-bb48-77b3-b86f-5f226f43ccc2`, question
`call_d94bcec4190048ba9493cf6f5af02253`, item 0: “Ano, použít nainstalovanou
27.1 (27A9275) a zopakovat testy”. The question explicitly named both Jízda and
COP Mobile and no SDK/iOS-version change. Device-contract, iOS-project and skeleton checks pass.
Canonical SDK and host test results belong to this worktree, not to the
earlier Jízda candidate.
The frozen vendor's 378-test suite includes earlier host changes excluded from
this selective port; its count is not the canonical suite count or evidence
that all of those older deltas have been accepted upstream.

Final canonical `scripts/check.sh` completed with exit 0 on 2026-10-25:
30 host unit tests, 5 host UI smoke tests, 217 SDK tests (2 explicit skips,
0 failures), and 2 accessibility audits. The SDK run includes the later exact
legacy-text edit regression. Skeleton, toolchain, 19 Device-contract fixtures,
iOS project validation and `git diff --check` passed. Both localization string
files also pass `plutil -lint`. The unmodified accessibility tests emit existing
actor-isolation warnings; these are not represented as a warning-free build.
The final local log is `/private/tmp/communication62-canonical-check.log`.
The skips concern a private live routing replay absent from source and a
package runner without the Keychain entitlement; neither is phone acceptance.

This branch is an upstream client correction, not a physical-phone delivery
or production-backend deployment. No real message/call, crypto-store change,
TestFlight upload or App Review submission is performed. Two-phone readability,
one-bubble-per-send and bidirectional call audio remain acceptance gates.
