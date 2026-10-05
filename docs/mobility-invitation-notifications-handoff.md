# Mobility invitation notifications v1 —2026-10-05

## Contract and behavior

The binding OpenAPI extension `x-cop-mobility-invitation-notifications` specifies
`cop-mobility-invitation-notification-v1`. Existing invitation receipts remain
queued and non-enumerating; queued means durable invitation, never confirmed
Apple/device delivery. Existing verified-account inbox remains authoritative.

COP atomically creates a per-recipient outbox record with the invitation and
operation receipt. Only already-known, verified accounts matching the normalized
invited email at creation are bound (maximum20). Unknown/unverified emails get the
same receipt and no push job. A later registration can read the verified inbox,
but does not retroactively receive an automatic push. Idempotent invite retries
create no duplicate jobs. Outbox stores only opaque invitation/account IDs,
expiry, state, attempts and retry/claim metadata; no added email, names, raw GPS,
keys or APNs tokens. Domain30-day-after-expiry cleanup also removes outbox jobs.

A worker serializes durable claims, performs network calls outside SQL and uses
an invitation+recipient idempotency key at Messaging. Claims expire after60s;
retry backoff is bounded2s–5min until expiry, with a single flight per worker.
Before emission it rechecks verified recipient/email, pending invitation,
expiry and current inviter management permissions. Revoke during the network
call may still leave a generic alert; the alert cannot grant membership.
Provider intake acceptance finishes a job; subsequent Apple delivery is best
effort. Device registration, notification permission/preferences and valid APNs
credentials remain prerequisites. Zero devices or Apple failure is not success
on the phone; the authoritative inbox is the recovery path.

## Wire

Use existing Messaging `system.account`, severity info, priority normal,
userIds resolved only on the server. Send fixed generic text, no entity/inviter
names or email. This uses ordinary APNs alert, never VoIP. Example synthetic link:

`csm://mobility/invitations/v1/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/vehicle/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb`

The first UUID is recipient COP account ID; the second is invitation ID. Entity
type is vehicle or group. Source provider is cop.mobility/layer mobility-invitations.
APNs carries the supported deepLink/type/source envelope; metadata contractVersion
is only Messaging intake metadata, not an assumed APNs field. No free context.

Only a user tap may navigate. SDK restores the existing session, loads current
COP account and verified pending inbox, checks exact recipient/ID/type/expiry,
and rechecks session scope after every await. Revoked/missing/wrong-account links
produce no navigation. Explicit acceptance and separate GPS consent remain
mandatory. Passive/background notification delivery does not navigate.

## Public SDK / host integration

Host remains UNUserNotificationCenterDelegate and forwards existing callbacks to
CSMCommunicationNotifications, then awaits processPendingNotifications. Observe:

- .csmMobilityInvitationRequested: userInfo["navigation"] is
  CSMMobilityInvitationNavigation(invitation:CSMMobilityPendingInvitation,
  sessionScope:String), containing only the freshly verified inbox item.
- .csmMobilityInvitationVerificationFailed: the same neutral result for nil and errors;
  offer manual inbox retry, reveal no missing/revoked/wrong-account reason.

Clear UI navigation on account switch; verify the supplied sessionScope before
presentation. URL target parser CSMMobilityInvitationNotificationTarget is public;
its parse success is not authorization. Runtime method
mobilityInvitationForNotification(url:expectedScope:) performs the server checks.
Initial signed-out notifications stay in the existing bounded16-item volatile
queue until session readiness. No persistent decrypted content or new tokens.


Full server release evidence is COP docs/integration/35_MOBILITY_INVITATION_NOTIFICATIONS.md.
No phone delivery or shared consent is claimed from simulator tests.

## Verification on 2026-10-05

Required `bash scripts/check.sh` passed with the approved Xcode27.1/27A9269:
30 app unit tests,5 app UI tests,111 package XCTest cases (110 passed,1 private
replay skipped),2 SwiftTesting cases and2 complete accessibility audits passed.
The previous signed-in audit failed because its locator limited NavigationStack
`chat.workspace` to element type Other; the active Duo display showed the actual
signed-in synthetic chat. The exact identity locator now accepts any element
type; all audit categories remain enabled and failed fixtures attach their
hierarchy. Preview authentication remains Debug only, never Release.

SDK category registration merges the center's existing categories, replacing
only SDK-owned identifiers. RIDE_START_CATEGORY and other host categories and
actions survive; the host delegate is unchanged. The package test exercises real
UNNotificationCategory values and the merge helper; it does not instantiate
UNUserNotificationCenter.current in a headless bundle runner. Actual device
registration/category coexistence and Apple sandbox/production delivery remain
physical-device acceptance, not a package-test claim. No physical phone or real
account, invitation, GPS or APNs delivery was used in this verification.
