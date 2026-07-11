# ADR 0004: Native-owned background tracking

## Status

Accepted

## Context

WebView JavaScript is suspended in background and its subscriptions disappear
on reload. Foreground location updates therefore cannot represent a durable
navigation/tracking session. COP zároveň potřebuje pravdivě rozlišit location,
course, heading a 3D attitude.

## Decision

- Foreground `location` and `heading` subscriptions remain bridge-session
  scoped.
- User-facing tracking uses a separate native-owned session with explicit
  start, status/read-samples cursor, and stop operations.
- The native service durably records bounded technical samples and exposes a
  snapshot after WebView resume or reload.
- Background tracking starts only from an explicit user action, remains visibly
  indicated, and can be stopped in one step.
- Full 3D attitude is foreground-only. Background attitude is reported as
  unsupported instead of being simulated.
- No background server upload is added until a scoped authentication delegation
  contract is approved.

## Consequences

- Tracking can survive a WebView reload without treating JavaScript as a
  background runtime.
- Native storage, retention, battery limits and lifecycle tests are required.
- A user force-quit and OS restrictions remain honest terminal/degraded states;
  the application cannot guarantee continuous execution.

## Security and Privacy Impact

Samples are encrypted/protected at rest, excluded from normal logs, bounded by
retention and deleted on user request, logout policy or expiry. Precise and
background location permissions remain separate, purpose-specific decisions.

## Validation

Physical-device tests cover screen lock, background/foreground, WebView reload,
process termination supported by the OS, denied/revoked permissions, reduced
accuracy, stale samples and battery consumption.
