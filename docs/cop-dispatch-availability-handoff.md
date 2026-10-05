# COP independent mobility availability (wire v1)

The approved additive contract keeps existing `CSMMobilityCapabilities` fields and initializer calls compatible. `serviceAvailability` is optional, with initializer default nil. A missing field from an older server is unknown, not verified readiness.

- `CSMMobilityServiceAvailability`: `sharedVehicles: CSMMobilitySharedVehiclesAvailability`, `dispatch: CSMMobilityDispatchAvailability`, `checkedAt: String` (UTC ISO8601).
- Shared vehicles enum: ready/unavailable/disabled.
- Dispatch enum: ready/recovering/unavailable/disabled.
- enabled fields continue to describe configuration. Availability never substitutes for account/ACL, current group audience/keys, explicit consent or successful server receipts.

Capabilities can return200 while Dispatch is unavailable, so retain a verified account and independently load vehicles/invitations. Invitation403 EMAIL_VERIFICATION_REQUIRED is not OIDC expiry. Do not renew login for503/429 or a pending encrypted stop/cancel acknowledgment.

Private requests remain fail-closed503 until the server verifies its exclusive primary lease and invalidates previous shares. Restored availability must never re-enable GPS or resume consent. Recreate the SDK encryption facade after actual account-session changes; clearing markers/retaining pending stop/cancel follows the existing handoff29.

Verification: full SDK simulator regression107 tests,106 passed and one private road replay skipped; new tests cover legacy response, all Dispatch states independent of vehicles and invalid enum rejection. Existing auth/isolation/encryption tests pass. Exact approved toolchain Xcode27.1/27A9269/SDK27.1. Mandatory COP Mobile check passed (app tests, SDK tests, two accessibility audits, skeleton/project validation and diff check); physical two-device acceptance remains required.
