# ADR 0006: Relay remains an experimental production gate

## Status

Accepted

## Context

The product direction includes device-to-device store-and-forward when Internet
connectivity is unavailable. iOS cannot provide a permanently running mesh, a
transport-encrypted link is not end-to-end security across relay hops, and the
legacy native prototype has not demonstrated iOS/Android interoperability.

## Decision

- Relay is excluded from the initial iOS MVP and disabled by build/release flag
  and server policy in production.
- The first implementation is a deterministic relay core plus mock transport;
  radio work begins only in a laboratory feature build.
- The preferred cross-platform POC is Nearby Connections in foreground on iOS
  and Android, subject to an explicit privacy/procurement decision about the
  Google SDK.
- Wi-Fi Aware is a later capability-gated adapter and requires entitlement,
  supported hardware and a physical iOS/Android interoperability spike.
- Multi-hop behavior belongs to the relay core: durable queue, TTL, hop limit,
  deduplication, bounded inventory, per-peer custody/ACK and backend delivery
  acknowledgement are distinct states.
- Sensitive production payloads remain blocked until device identity, key
  provisioning, rotation/revocation, E2E encryption, replay protection and
  threat-model review are approved.

## Consequences

- No roadmap or UI may describe the POC as an always-on or production mesh.
- iOS relay is foreground/opportunistic; Android background relay may later use
  an explicitly user-enabled foreground service.
- Physical two-device and three-device tests are required before a transport
  can be called interoperable.

## Security and Privacy Impact

Peer identifiers are pseudonymous and rotating. Discovery does not advertise
names, email addresses, phone numbers, exact location or message content.
Queues have byte quotas, retention, user clear controls and fail-closed payload
admission.

## Validation

The release pipeline must prove production flags are off. Laboratory tests cover
malformed and oversized frames, replay, duplicate paths, clock skew, queue
exhaustion, peer loss, A-to-B-to-C carry/forward and distinction between peer ACK
and backend delivery.
