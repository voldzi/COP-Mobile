# ADR 0014: App Store identity owned by the VCode personal team

- Status: accepted
- Date: 2026-09-22

## Context

COP Mobile was prepared with the legacy organizational team `LM6W548X36` and
bundle ID `cz.zeleznalady.csm.messenger`. The current product has not been
released through that App Store Connect account, and the VCode maintainer has no
App Store Connect access to the legacy team. Apple only permits a normal app
transfer after at least one version has been released.

Keeping the legacy identity would prevent TestFlight and App Store distribution.
Changing identity affects APNs topics, associated domains, device registration
contracts and server allowlists, so it must be coordinated across COP Mobile,
COP and CSM Messaging.

## Decision

COP Mobile will be distributed by Apple team `MC3RPR926P` with the explicit
bundle ID `cz.voldzi.copmobile`. The notification service uses
`cz.voldzi.copmobile.notification-service`; standard and VoIP APNs topics are
`cz.voldzi.copmobile` and `cz.voldzi.copmobile.voip`.

The public OIDC client and callback scheme remain `csm-mobile` and `csm` to avoid
an unrelated authentication migration. COP's Device API contract, AASA document
and CSM Messaging registration/APNs configuration are updated in the same
release train. Production server support must be deployed before external
TestFlight testing.

This decision supersedes only the Apple team and bundle-identity portions of ADR
0008 and ADR 0011. Their communication architecture and security decisions
remain binding.

## Consequences

- Existing development installs under the legacy bundle ID are a separate app
  and must be removed manually during pilot testing.
- Keychain state does not migrate; testers sign in again.
- A new APNs key owned by team `MC3RPR926P` is required before push and VoIP
  acceptance tests.
- Server rollout and rollback must treat the bundle ID, team ID, AASA app ID and
  APNs topics as one atomic configuration set.
- The first public release starts with a new App Store record and has no ratings,
  reviews or installed-user continuity to preserve.
