# ADR 0023 — Separate chat content, delivery, device verification and history

Status: accepted implementation; physical-device acceptance pending.
Date: 2026-10-25.

## Decision

Preserve ADR 0022's exact send journal. Collapse app/SDK/server aliases only
with the full transaction, room and sender identity. Conflicting server event
IDs remain visible; a repeated body or timestamp is never delivery evidence.
Retain a previously proven transaction when a later snapshot of that same event
omits it. Never enqueue a new send to repair an ambiguous acknowledgement.

Store an optional bounded decryption-failure category independently of outgoing
delivery. Read actual own-device verification from the pinned Matrix SDK;
backup availability cannot prove device verification, message readability or
call readiness. Old snapshots decode without granting verification.

The status sheet prioritizes unreadable content and delivery problems, then
shows device verification and history recovery separately. Explicit refresh
reuses existing account/store/recovery witnesses and publishes no result into
another account or conversation. Local decryption retries are bounded to 50
sessions per room per 30 seconds and do not alter trust, keys or stores.

User-visible call failures use an allowlisted presentation. The call-start
failure log contains a fixed message; arbitrary transport errors remain out
of public logs. Existing bounded diagnostic categories remain available.

## Consequences

No REST, signing, permission, toolchain-default or dependency-pin change.
Existing explicit local-store recovery and advanced diagnostic controls remain
owned by COP Mobile. This selective successor does not replace unrelated host
lifecycle, notification or voice changes from the Jízda vendor snapshot.

No key reset, history deletion, outbox deletion or trust bypass is a repair
step. Backend policy readiness, local regressions and real two-phone message/
audio acceptance remain separate evidence.
