# Jízda community reports: public SDK handoff

Server source1514e4ee9ea1bb5e5d37ee0338b143d80e39f3ce is deployed in COP API/web.
Use `CSMDriverReportCategory.policePatrol` (`police_patrol`) through
`submitDriverReport`; mapping to internal ReportCategory is exhaustive and the
conversion helper is internal. No API key/token/private transport is exposed.
The nearby category query includes police patrols. Default title is Policejní
hlídka and severity advisory/info; expiry is30minutes from the original observation.
Persist offline observation UUID/time rather than generating a new observation
on retry. Existing consent to manual reporting is independent of speed intake
and private Dispatch position sharing.

COP owns active-feed decisions. Three independent negative votes with a negative
balance of two suppress transient observations; author votes do not count.
Corrections reset eligible votes, vote replacement may recover within original
expiry, and no vote changes a route. Confirm through existing
`confirmDriverReport`; do not independently count votes in Jízda.

`CSMNearbyDriverReport.roadBinding` is optional, projected by the nearby feed only
from complete matched server enrichment. Dataset, directedEdgeID and enrichedAt
identify the observation's server match; compare graph version and actual route
edges before a future route-specific warning. Missing data is not confirmation
of road/direction. Police never becomes a closure or a route penalty.

Final exact isolated package tests:71passed on approved Xcode27.1/27A9269 and the
installed iOS27.1 simulator. The first compile exposed access scope/import errors;
these were repaired before the successful run. A temporary destination lookup
failure required retry after the existing simulator became available; no runtime
was installed. No real user report was created for testing. Physical iPhone,
actual login/confirmation/offline/account change remain joint acceptance.

Binding COP JSON contract and release evidence:
`docs/integration/31_JIZDA_COMMUNITY_REPORTS.md` on branch
`codex/driver-report-community` in delta_acr_cop.
