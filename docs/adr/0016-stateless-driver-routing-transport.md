# ADR 0016 — Stateless driver routing transport

Status: accepted, 2026-09-21.

The shared kit exposes an authenticated car-route request for Jizda over the
existing COP API. It returns validated DTOs, traffic provenance and indexed
maneuvers. It owns no MapKit state, progress, destination search or navigation
session. COP Mobile keeps map/business workflows in the web application.

Validation rejects invalid coordinates, nonpositive metrics, direct-line
fallbacks and incomplete geometry-index coverage before turn guidance. Live
traffic states remain separate from route availability. Missing/degraded live
speeds do not invalidate a valid engine route. Time is returned without adding
any local traffic penalty. Browser transport and the Device bridge are unchanged.

The feed can project server-verified clusters inside its already authorized,
active, in-radius result set. It retains the newest representative and reports
the number of observations without merging votes or changing support levels.
