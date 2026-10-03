# ADR 0020: Immutable strict road-trip transport

Status: accepted for optional integration, not new profile activation.

Consume COP JSON OpenAPI RoadTrip* schemas through the existing authenticated
CSMCommunicationKit transport. Add immutable CSMRoadTrip, capability discovery in
GET profiles, strict drivingRoutes(from:to:trip:alternatives:) and per-variant
assessment. COP independently verifies canonical request/applied/geometry hashes;
the SDK trusts that authenticated boundary and checks exact trip/request identity,
engine, graph, expiry, mandatory field application and every navigable variant.

Strict trips never authorize MapKit/unconstrained fallback. Old responses and the
old facade remain readable. Legacy avoid/via/departureTime are additive optional
parameters. Complete known vehicle dimensions/loaded total kg must be explicit;
unknowns are not defaults. Ordinary auto and commercial truck remain distinct.
Unsupported trailer/axles/departure/entrance are server errors, never omissions.

New activation requires reviewed closure coverage, actual engine acceptance and
physical Jízda iPhone tests. The SDK does not start measurement collection, mutate
vehicle records or add a SIM client. Integration details: docs/routing-handoff.md.
