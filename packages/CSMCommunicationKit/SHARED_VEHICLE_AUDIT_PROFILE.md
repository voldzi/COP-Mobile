# Shared vehicle profile, audit and owner recovery

Additive v1 public contracts in CSMSharedVehicleAuditProfile.swift. Existing fields optional, initializers default nil. Require current account/vehicle scope, dataRevision, server readiness and corresponding capability. Never silently choose car when profile missing. Powertrain combustion/electric/plugInHybrid; dimensions and loaded mass describe whole combination; same mapped SIM profile and route assessments apply. No physical verification claim.

OwnerBindingInput(version1,localVehicleId) on Create/Update; server derives ownerAccountId and only returns binding to current owner on fresh list/get/create. verifiedOwnerVehicleId(for:) checks owner identity/role; no plate/name heuristic. Existing cars need explicit owner-confirmed mapping, new phone uses restored stable UUID. Binding immutable for current owner and unique,409requires refresh.

RecordWrite.correction(version1,recordId,recordRevision,reason), Receipt.recordRevision and SyncItem.audit identify exact reviewed correction. Normal edit same recordId/nextrev; odometer correction new recordId pointing to original via data.correctionOfRecordId plus matching reason/revision. Original event/payload remains; Delete is retained logical void with reason. Do not rebase same operationId on409 or recreate same trip under new IDs. Stats fold current nondeleted record revision.

Vehicle.activeCareReminders(version1,dataRevision,state complete/unavailable,items recordId/revision/title/dueAt?/dueOdometerKm?) includes current incomplete reminders, no cost history. currentItems(for:) returns nil for stale/incomplete/unsupported, not empty current. Use own notification permission/stable IDs, current scope and authoritative matching odo; preserve estimated label. No recurring rule synthesized. Server retains existing30day deleted-domain/receipt policies.

Capabilities arrays sharedRoutingProfileVersions/ownerBindingVersions/recordAuditVersions/activeCareReminderVersions and supportsSharedRoutingProfile/OwnerBinding/AuditedRecordChanges/ActiveCareReminders. Production readiness and actual phone acceptance are separate.
