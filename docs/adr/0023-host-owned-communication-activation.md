# ADR 0023: One account with explicit host communication activation

Status: implemented source; native host integration and real-device acceptance pending.
Date: 2026-10-13.

Jízda uses the existing native COP OIDC account and one login entry in Já.
Authentication for routing must not implicitly start optional communication,
push registration, sharing or measurement. The existing standalone COP Mobile
startup remains the default.

The signed bundle selects `CSMCommunicationActivationPolicy`:

- omitted or `automatic`: existing COP Mobile behavior;
- `explicit_host_consent`: verified authentication and routing remain available,
  optional producers require an account-bound local host activation;
- any other value: optional producers remain disabled.

The activation is local product intent, not server authorization, OAuth grant
revocation, account deletion, or a different login. COP still verifies every
request. A verified identity for the current authentication generation is required;
a retained actor from an earlier account cannot authorize producers during login.
The state is stored in the host container under a hash of bundle, issuer, client,
COP origin and subject. The process epoch fences delayed work and account changes.

Withdrawal fences producers before awaiting cleanup. Sync, outbox work and
live-location work stop. Only the installation's own known Messaging registrations
and exact bundle/push-key Matrix pushers are removed. A failed or unconfirmed
removal stays pending; an HTTP error, token expiry or restart cannot mean success.
No OIDC logout, Matrix account logout, history deletion or remote account-wide
revocation is performed.

The pusher's exact cleanup target and already-issued Matrix credential are retained
only in this host's `WhenUnlockedThisDeviceOnly` Keychain namespace. This is private
cleanup material; it never enters host API, defaults, logs or bridge messages.
The retry uses only one exact authenticated `kind:null` pusher request. It creates
no Matrix client, sync service, queue or new credential identity. Redirects are
refused, only an exact-origin HTTP 200 completes removal. At most 32 targets are
retained. Successful removal deletes the corresponding Keychain target. If the
existing token has expired, removal stays pending and needs server assistance;
the SDK never provisions a replacement or activates communication to clear it.

VoiceCallService belongs to a separate native module whose initialization is not
controlled by a messaging permission check. Jízda must create it lazily only after
activation and stop its own call/push lifecycle on withdrawal. The global/China
distribution policy remains unchanged. The host also owns Dispatch loops and its
measurement RAM queue and must fence and stop them before withdrawal.

This SDK change does not activate server features, add an OAuth client, implement
per-install OAuth revocation, or prove real-device push/call acceptance.
