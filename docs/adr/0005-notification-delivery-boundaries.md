# ADR 0005: Notification and ringing boundaries

## Status

Accepted

## Context

COP requires audible safety notifications and wake-up for real incoming calls.
Apple does not allow an ordinary application to guarantee indefinite ringing or
to use VoIP background modes as a generic alert workaround.

## Decision

- MVP supports ordinary and Time Sensitive APNs notifications, local
  notifications, badge state and deep links through CSM Messaging.
- The capability model reports alert, sound, badge, Time Sensitive and Critical
  authorization separately; `authorized` never implies guaranteed audibility.
- The project will request Apple's Critical Alerts entitlement during
  feasibility, but ships without critical behavior until both entitlement and
  user authorization are present.
- PushKit/CallKit may be introduced only in a separate ADR and only for an
  actual VoIP call whose signalling and lifecycle meet Apple requirements.
- Safety-critical delivery requiring a guarantee must use server-side
  acknowledgement and a redundant external channel; the app alone is not that
  guarantee.

## Consequences

- Product copy and monitoring must distinguish attempted, APNs-accepted,
  device-presented and user-acknowledged states.
- A denied permission, disabled sound, Focus mode or missing entitlement is a
  supported degraded state.
- CSM Messaging remains the owner of APNs credentials, device delivery state
  and deduplication.

## Security and Privacy Impact

Push payloads contain minimal identifiers and presentation metadata, never
plaintext E2EE chat content, protected media URLs, auth tokens or precise
location.

## Validation

Real-device tests cover foreground, background, locked, terminated, permission
denied, sound disabled, Time Sensitive disabled, duplicate payload, expiration
and deep-link routing. Critical and VoIP paths cannot pass without their real
entitlements and server configuration.
