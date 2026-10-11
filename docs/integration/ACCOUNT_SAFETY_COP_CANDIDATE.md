# Account safety SDK candidate on pinned 09493a0

Source-only transfer for coordinated Jízda/COP acceptance. Publication does not
activate production capabilities or prove a native build. Use the exact release
manifest, complete patch and base revision; the older three-file transfer is
superseded.

The first-phase nine-file scope below remains the exact historical transfer.
The new lifecycle completion uses a separate immutable v2manifest; do not modify
the original archive or replace Jízda's newer host code wholesale.

## Complete transfer scope

Against Jízda's pinned `09493a0`, include all nine paths:

- `docs/README.md`
- this integration document
- `packages/CSMCommunicationKit/Apps/CSMMobile/ConversationWorkspace.swift`
- `packages/CSMCommunicationKit/Sources/CSMCommunicationKit/CSMAccountSafety.swift`
- `packages/CSMCommunicationKit/Sources/CSMCommunicationKit/CSMMobility.swift`
- `packages/CSMCommunicationKit/Sources/CSMCommunicationKit/CSMCommunicationSafetySheet.swift`
- `packages/CSMCommunicationKit/Sources/CSMCommunicationKit/CSMJizdaAppLink.swift`
- `packages/CSMCommunicationKit/Sources/CSMCore/CommunicationModel.swift`
- `packages/CSMCommunicationKit/Tests/CSMCommunicationKitTests/AccountSafetyContractsTests.swift`

The two new safety-sheet/link source files must be included explicitly. An
unstaged `git diff` would omit them. Preserve Jízda's host callback,
notification, voice, measurement, routing and send-ack changes; apply the delta
to a new frozen snapshot and resolve only genuine overlapping edits.

## Contract and methods

COP authority is binding JSON OpenAPI in `delta_acr_cop` and its integration
plans 40–42. Reporting/blocking: `cop-account-safety-v1`. Jízda-only unlink:
`cop-jizda-link-v1`. Account and local SwiftData deletion are not part of unlink.

Public methods:

- `copAccountSafetyCapabilities(expectedScope:)`
- `copCommunicationReport(_:operationId:expectedScope:)`
- `copCommunicationReportStatus(reportId:expectedScope:)`
- `copCommunicationBlockState(peerSubjectId:expectedScope:)`
- `copCommunicationSetBlocked(_:peerSubjectId:expectedScope:)`
- `copJizdaLinkCapabilities(expectedScope:)`
- `copJizdaLinkStatus(expectedScope:)`
- `copDisconnectJizda(operationId:expectedScope:)`

Existing `mobilityRequest` callers retain nil defaults. New optional
`idempotencyKey` is validated as UUID. Optional responseValidator observes HTTP
status and decoded receipt, without changing actor/scope/session-generation,
HTTPS, no-redirect or ephemeral no-cookie guards.

Targets are user/message/call references verified server-side. Both encoder and
decoder validate the exact target shape and explicit evidence. Standalone
capabilities/receipt coding validates the current version, truthful state,
no account/local-data erasure, and absent/null account-deletion URL. Every submission
is validated again before HTTP and self-report targets are rejected. Default
reports contain no evidence. Optional evidence is selected text, explicitly
confirmed, at most 4096 UTF-8 bytes. Render it as plain text, never HTML/links;
never automatically attach decrypted history, transcript or location. Reporting
and blocking UI gates are independent.

Keep operation UUID across retries; discard it when account/scope changes.
POST unlink 202 is pending with nonempty remaining; POST 200 is complete only
with disconnected/empty remaining. Mismatched HTTP/body results fail. GET 200
may recover pending work. isComplete alone is not proof of a successful POST.

Before unlink, pause the host's Dispatch/location/measurement producers. On
accepted fence the SDK pauses local communication and emits the content-free
`.csmJizdaLinkFenceAccepted` event. The host must stop its own producers. Check
status on cold start before push/voice producers. On 503 recover status before
resuming. Preserve SwiftData; do not invoke global COP/Matrix logout/deletion.

A separate attested Jízda OIDC client and exact PKCE redirect must be provisioned
before unlink can activate. Shared csm-mobile is not app identity. Do not copy a
refresh token into the new namespace. Messaging source now selectively revokes and reads back attested Matrix devices.
Live permission revocation and unknown legacy migration remain incomplete, so
current production cleanup cannot complete. Whole COP account erasure has a
separate source-only orchestration contract and a real local sessions/profile
adapter, but lacks all required provider proofs. SDK safety capability remains
false/URL null; do not expose a delete action based on source alone.

Canonical block hides direct cached history/discards unsent drafts. Group-cache
filtering, cold-start block synchronization and already-handed-off Matrix/media
revocation remain acceptance gates. Existing LiveKit JWTs and ongoing call
audio are not claimed revoked by this candidate.

## Toolchain and evidence matrix

| Check | Accepted scope |
| --- | --- |
| Xcode 27.1(27A9275), iPhoneOS SDK 27.1, iOS minimum26 | Exact installed pin explicitly approved by human; verifier passed |
| First-phase frozen SDK native tests on exact27A9275 | Jízda owner reports248tests, twoexplicit skips, zero failures; predates lifecycle delta |
| Isolated Foundation models, Swift 6 language mode | Focused model/encoder/decoder/receipt/preflight evidence only |
| Skeleton, device 19 fixtures, iOS project validator | Static configuration evidence only |
| New lifecycle SDK/host native tests | Serialized owner execution pending; do not reuse first-phase results |
| Physical iPhone/Matrix/APNs/LiveKit/unlink/deletion | Not performed by this source transfer |

The exact pin was changed only after explicit human approval (published6e4b028),
never bypassed; no Xcode download was attempted.
Earlier Jízda host-test results predate this delta. An isolated XCTest attempt
returned `no such module XCTest`; do not count checked-in cases as executed.
Fresh verification: 128 isolated Foundation checks passed; all seven Swift
files parse; 15 native XCTest cases are checked in but not executed. Static
skeleton/device 19 fixtures/project validation passed. Hashes and complete scope
are recorded in the transfer manifest.

No production restart, secret creation, account reset, real message/push or app
installation occurred. App Review needs actual deletion and the accepted
moderation/filter/contact/retention process before those features are claimed.
