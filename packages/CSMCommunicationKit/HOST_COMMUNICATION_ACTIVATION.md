# One account: authentication, routing and optional communication

SDK implementation based on immutable public COP-Mobile commit
`73dcb1dfd1bc42775057ce5ddd17edb85ad574db`. Publication and host acceptance are
separate gates. No host source files or production systems were changed here.

## Jízda integration

1. Compare the eventual exact SDK revision against Jízda's recorded vendor
   provenance first. Its newer host deltas (`expectedNotificationScope`, send
   acknowledgement, `onAccountProfileRequested` and call/account fences) must be
   preserved and intentionally reapplied/reviewed into the integration revision.
   Do not overwrite the vendor wholesale or keep an unrecorded partial merge.
   Record the complete resulting source/pin and run Jízda's native regression.
   Keep the existing `csm-mobile` client and callback; this creates no new account.
2. In every signed Jízda bundle set
   `CSMCommunicationActivationPolicy=explicit_host_consent` before runtime access.
   COP Mobile can omit the field and keeps its existing automatic behavior.
3. Restore routing/authentication with `prepareAuthentication()`. Start interactive
   login only from Já with `authenticationSignIn(loginHint:switchAccount:)`.
   Existing `mobilitySignIn` and routing APIs also respect the bundle policy.
4. The single approved Já login/connection flow can call
   `setHostCommunicationEnabled(true, expectedScope: mobilitySessionScope())` using
   the current nonnil opaque scope after verified login. This local producer policy
   requires no second login or compulsory second connection prompt. Do not infer permission from `.signedIn` or
   `copJizdaLifecycleSnapshot.readiness == .notRequired`.
5. Show communication and CarPlay chat only when
   `hostCommunicationSnapshot.enabled` is true. Observe
   `.csmHostCommunicationConsentChanged` and reread the current snapshot and scope.
   Use its generation before and after each asynchronous host operation.
6. Only after that gate create `VoiceCallService`, attach APNs/VoIP callbacks, start
   Dispatch producers, or allow optional measurement collection. Never access a
   voice singleton before activation. Voice distribution still uses its separate
   mandatory `CSMVoiceDistribution` policy.
7. On local disable, immediately stop/fence the host's Dispatch and measurement
   queue and voice service, then call
   `setHostCommunicationEnabled(false, expectedScope:)`. The SDK fences its own
   producers immediately, preserves routing authentication and encrypted history,
   and removes only this installation's known registration/pusher targets.
8. `registrationRemovalPending=true` means a removal is not confirmed. Keep the
   optional features off and expose a retry using
   `retryHostCommunicationRegistrationRemoval(expectedScope:)`. After restart or
   APNs rotation it uses the original protected target without starting Matrix.
   Expired cleanup credentials remain pending and require server assistance.
   A registration that may have committed without returning its device ID also
   remains pending until server assistance confirms the exact installation target.
9. Full COP account management/deletion and per-install server grant revocation are
   separate contracts. Do not label this local switch as account deletion or a
   completed server unlink. COP Mobile's separate host/container is unchanged.

## SDK enforcement

For each asynchronous host operation, capture `hostCommunicationSnapshot` only
after activation. Immediately after the await reread it and require all three:
`fresh.enabled && fresh.scope == captured.scope && fresh.generation == captured.generation`.
The captured scope must be nonnil. Same-account off then on keeps the scope but
changes the generation twice; the old capture therefore cannot resume a producer.

- Authentication-only startup verifies the existing COP identity/policy and local
  unlock requirements; it starts no Matrix, APNs, device registration or outbox.
- The current identity must be verified before restoring account-specific intent.
  Old-account consent never authorizes a new token during delayed bootstrap.
- In explicit mode route/catalog APIs use authentication-only startup. Automatic
  COP Mobile retains the old full-start behavior.
- Shared vehicles/Dispatch and measurement writes are checked before token
  retrieval and after awaits. Existing stop/cancel/revoke/read-consent cleanup
  remains available while features are off.
- CarPlay list/read/send, conversation selection/load and remote reaction/pin
  operations consult the same producer epoch. Cached transport cannot restart
  itself through a stale CarPlay or phone callback.
- Pusher cleanup is one exact no-redirect, no-cookie, no-store request to its
  previously verified HTTPS homeserver. Only status 200 confirms it. Raw APNs or
  Matrix credentials are not stored in UserDefaults or exposed to the host.

## Acceptance evidence

The exact Xcode 27.1 (27A9275) / iOS SDK 27.1 verifier passed. Matrix 26.09.17 and
LiveKit 2.17.0 remain pinned. Deterministic SDK tests cover before-consent startup,
single login, routing, automatic COP Mobile regression, scoped persistence,
delayed account changes, withdrawal during bootstrap/configuration/registration,
restart and APNs rotation, outage/pending retry, and exact owned HTTP cleanup.
The mandatory `scripts/check.sh` passed on the exact final code: 30 app unit tests,
5 UI tests, 257 package XCTest tests (2 expected skips), 2 Swift Testing tests and
2 accessibility tests, plus skeleton, toolchain, Device contract and iOS project
validation. The final code also passed 37 targeted tests (17 host boundary,
2 embedded surface, 18 lifecycle), including retained-wrapper CarPlay, pending
cleanup, same-account off/on epochs and immediate withdrawal while an older
account teardown is paused. The final full check followed the last code correction;
only these documentation result numbers changed afterwards.

Chroma reindex was attempted but refused because this isolated SDK checkout is
not an app-selected retrieval project; the initial Chroma search was unavailable.

Not verified here: host Jízda Debug/Release/App Store archive against the eventual
published SDK, real Keychain reboot/locked-device behavior, real APNs/VoIP push,
CarPlay hardware, real device account change, or production deletion/cleanup.
Synthetic simulator success is not an App Store or physical acceptance result.
