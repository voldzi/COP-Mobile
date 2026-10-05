# ADR 0020: Shared COP OIDC lifecycle independent of Matrix chat

Date: 2026-10-05
Status: Accepted for SDK implementation; physical-device acceptance pending.

## Context

A working Matrix chat does not imply a valid COP API OIDC credential. Mobility created a new refresh owner per request, while API/chat and routing owned other instances over the same Keychain credential. Concurrent requests could refresh a rotating token independently. The runtime sign-in shortcut treated logical signed-in chat state as proof of OIDC availability.

## Decision

Use one process registry of OIDC lifecycles by configured issuer/client for published production consumers. Injectable isolated lifecycles remain available for tests. Complete and persist a refresh once before joined callers receive the result. Do not let obsolete refresh rejection delete a newer credential.

Expose credential-free OIDC status and purpose-specific failure classification. Keep Matrix state independent. Explicit same-account browser PKCE restoration verifies token issuer/subject and the session revision before credential replacement. Account switching remains an explicit separate operation. Network/provider failure is neither logout nor proof of expiration.

## Consequences

Consumers must separate account authentication from capabilities/service failures. They must retain existing chat on API outages and report HTTP status/code/correlation without credentials or content. There is no COP REST change or server deployment. Real device acceptance of browser renewal, cancellation and interrupted connectivity is required.
