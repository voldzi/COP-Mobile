# Shared vehicle receipt details v1

Optional typed energy/service details preserve the existing shared receipt identity, revisions and authenticated transport. New public DTOs are in `CSMSharedVehicleRecordDetails.swift`; existing initializers retain default `details:nil`. Capability fields are optional: older servers are unknown, not supported.

Before shared detail editing require `capabilities.supportsRecordDetailsV1`, enabled/ready service, correct role, advertised unit/fuel type and `data.canEditRecordDetailsV1`. Reuse the host vehicle forms with an explicit private/shared storage target. Never create a duplicate private vehicle or silently transfer private receipts.

One service record is one expense receipt; sum item minor units exactly in the same currency. Notes max1000 Unicode code points, station/provider/locationName max160, address500, category IDs80, item title160 and max100 items. Show validation without truncation. Liters refueling and kWh charging are the only supported new detail forms; CNG/hydrogen cannot be represented as liters.

Shared station/location snapshots contain explicitly selected name/provider/address, no local database ID or coordinates. Explain unavailable precise-location controls and never silently discard GPS. Do not include receipts in AI or public-map context.

Unknown detail versions are read-only. The server rejects an update that would remove an entire existing details object (409 DETAILS_VERSION_REQUIRED). For a confirmed complete v1 replacement, omitted optional fields are removed; empty note is supported. Keep existing idempotence/CAS/retry semantics, and never split the item breakdown into additional expenses.

Verification: mandatory scripts/check.sh PASS on explicit COP iPhoneDuo: 30 app unit, 5 app UI, 118 package XCTest (1 skip), 2 Swift Testing and 2 accessibility audits. Four added package checks cover typed roundtrip, one receipt/items, legacy payload/capability and unsupported-version handling, selected charging text and battery fields. Server database/image/production evidence belongs to COP integration handoff 38. No signed-in users, real receipts or GPS were used in these tests; host real-phone acceptance remains separate.
