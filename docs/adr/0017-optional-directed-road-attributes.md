# ADR 0017 — Optional directed road attributes for Jízda

Status: accepted, 2026-09-23.

The shared communication kit extends its existing COP-only driver routing
facade with optional road attributes and actual vehicle dimensions. Existing
callers send the original request shape. The kit decodes typed coverage,
per-variant speed-limit intervals, advisory restrictions and the provider's
vehicle assessment, but does not convert them into turn guidance or legal
passability claims. Jízda owns presentation and navigation behavior.

The kit returns an explicit `outside_coverage` or empty-route response to the
host, so Jízda can request a genuine MapKit route. A nonempty route with invalid
geometry or maneuver indexes still fails closed. Missing enrichment never
invalidates an otherwise navigable COP route. No SIM/Valhalla address, token,
or traffic-delay calculation enters the kit.

Consequences: Jízda must opt in, bind intervals to the selected alternative's
geometry, show only `explicit` values as posted limits, and avoid claiming that
provider truck costing certifies passage. An iOS release is needed to expose
the new information to users; server deployment alone does not change the app.
