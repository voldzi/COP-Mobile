# ADR 0015: Shared driver-report transport

## Status

Accepted on 2026-09-20.

## Decision

`CSMCommunicationKit` exposes a narrow driver-report facade for Jizda. It
accepts a fixed traffic category, one observation point and bounded road
context, then uses the existing authenticated COP community-report lifecycle.
The client UUID is sent as `X-Idempotency-Key`. Pending reports are stored in a
separate encrypted outbox and retried when the authenticated runtime starts or
returns to the foreground.

COP remains the report authority. The facade contains no moderation, incident
fusion, map matching or routing policy. COP Mobile continues to present its
authoritative web report workflow and does not add a second native report UI.

## Consequences

- Jizda shares COP identity and retry semantics without handling bearer tokens.
- A retry cannot create duplicate reports after an ambiguous network failure.
- SIM and Valhalla remain server-side and are never exposed to the app.
- The outbox contains only explicit observations, not continuous ride history.
