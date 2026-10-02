# ADR 0019: Purpose-specific authenticated driver measurements

Status: accepted for disabled integration, not pilot activation.

The COP contract at 8c4abb5 / handoff 22 defines `cop-driver-measurements-v1`.
Expose only four typed operation kinds in CSMCommunicationRuntime: GET/POST/
DELETE consent and POST batch. The API accepts no URL, bearer, service token,
identity or client attestation. Batch bodies have whitelisted top-level/point/
ETA keys; COP owns final schema validation and authorization.

Reuse configured COP base URL, csm-mobile OIDC lifecycle and credential store
inside the package. Reject preview mode/unsafe bases and stale/mismatched
account scope. Check scope before token acquisition and after the response;
session-change notifications carry no identity/payload. An ephemeral session
has no cache/cookies and refuses all redirects before forwarding credentials.
No automatic request is triggered by this extension; Jizda's gate is false.
Responses retain status and Retry-After without exporting authorization.

The host owns GPS, consent UI, bounded volatile outbox and default-off gate.
COP owns durable consent and deletion; DELETE 202 is not completed deletion.
SDK tests are synthetic; authenticated COP/SIM production and physical iPhone
acceptance remain separate gates. No device install or pilot collection here.
