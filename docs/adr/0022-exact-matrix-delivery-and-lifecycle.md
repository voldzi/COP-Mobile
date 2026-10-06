# ADR 0022 — Exact Matrix acknowledgements and fenced communication lifecycle

Status: accepted implementation; physical-device acceptance pending.
Date: 2026-10-06.

## Decision

The production Matrix transport stores an encrypted per-draft submission journal
before entering the native SDK send queue. Each part binds the original account,
Matrix device and room, the complete SDK transaction ID, and a server event ID.
Only an exact acknowledgement of every part yields `sent`. A timeout, upload
completion, own message with matching text/time, or generic encrypted placeholder
cannot establish delivery. `sent` is a homeserver acknowledgement, not proof of
recipient receipt or decryption.

Unknown submissions remain pending without a new send. Confirmed parts are never
repeated. Legacy unscoped outbox records are retained without automatic production
replay. Journal writes are monotonic and serialized per encrypted-store root.
No queue error authorizes implicit trust bypass, plaintext or account reset.

Timeline invalidation finishes old streams. Configuration revisions and timeline
generations fence completion, cache insertion and snapshots. A late configuration
or outbox operation from account A cannot suspend or publish into account B.
Sign-out stops the live-location producer and invalidates the transport without
removing crypto stores, recovery keys, history or queued contributions. Normal
explicit OIDC sign-out remains unchanged.

Voice ringing follows server invitation expiry. Room/media setup and waiting for
server media acknowledgement remain bounded by one absolute 45-second budget across bounded setup stages.
CallKit reports connected only after native room, peer, audio and microphone
readiness AND the authoritative server connected phase.

## Consequences

No host API or COP REST contract change is required. Consumers must pin the complete
successor package union; independently cherry-picking identity or voice sources is
unsupported. Pending ambiguous sends can require investigation; they are not
silently discarded or retried as a new message.

A downgrade to a reader that ignores the new journal can blindly replay pending
messages. Do not downgrade installations with submission journals to the former
SDK. Preserve the stores and use a successor correction retaining these guards.
No destructive cleanup is a release or rollback procedure.

See [delivery acceptance handoff](../matrix-delivery-acceptance-handoff.md) for
implementation evidence, diagnostics, actual phone failures and release gates.
