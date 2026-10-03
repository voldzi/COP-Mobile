# Road-trip SDK handoff to Jízda

This revision also publishes the existing local route-bound tunnel DTO/test additions, preserving Jízda tunnel decoding when its dependency is pinned.

Contract marker `CSMCommunicationRuntime.roadTripContractVersion=sim-road-trip-v1`.
COP authoritative JSON OpenAPI contains RoadTrip* schemas; COP handoff 23 defines
units, validation limits, hashing, errors and joint acceptance. Publishing this
revision does not activate new vehicle profiles or real measurement collection.

- `drivingCapabilities()` GETs existing authenticated COP routing profiles.
  Missing capabilities/disabled flag/unsupported fields block activation.
  requires_runtime_validation does not attest current source availability.
- `CSMRoadTrip` freezes request UUID, intent, complete dimensions, loadedWeightKg
  (whole loaded combination), optional axles, trailer, departure, preferences,
  mandatory requirements, ordered via/stop waypoints and destination. Software
  bounds are m 8/5/30, kg100000, axle kg40000, waypoint12 and alternative3.
  Trailer part is never implicitly added to the whole-combination weight/length.
- `drivingRoutes(from:to:trip:alternatives:)` sends profileId=car, road_closure,
  includeSteps/roadAttributes and complete trip. No legacy fields mix with trip.
  COP rejects request/applied/geometry mismatch and unverified alternatives.
- `navigationRoutes(for:trip,at:)` rechecks every route and expiry. Use it after
  selection and during navigation. Strict errors must propagate; do not consult
  legacy requiresMapKitFallback to authorize a replacement for a strict trip.
  Fresh request UUID per calculation; preserve frozen vehicle/preferences/stops.
- car uses auto, commercial_truck uses truck; no emergency substitution. Trailer,
  axle, planned departure and approved entrance remain unsupported until SIM
  validates their actual behavior. A schema is not runtime capability evidence.
- Optional steps.roundabout carries enter/exit, countState/provider count and
  names. Retain legacy roundaboutExitCount. No invented bearing or exit count.
- Legacy facade now also accepts optional avoid:[CSMRouteAvoid], via points and
  departureTime:Date. These do not confer the guarantees of the strict contract.

Jízda uses a local package dependency; update or pin that checkout explicitly to
the published revision and preserve unrelated voice work. Production activation,
authoritative III/44520 closure, actual roundabout count, both stop legs,
reroutes/alternatives, GPS/tunnel recovery, speech and Dynamic Type need joint
acceptance. Synthetic test fixtures are not real closure or driving evidence.

Verification results and published revisions are in COP's routing acceptance report.
