import Foundation

public struct CSMSharedVehicleRideDetails: Codable, Sendable {
    public let version: Int
    public let tripId: UUID
    public let startedAt: String
    public let endedAt: String
    public let endOdometerKm: String?
    public init(version: Int = 1, tripId: UUID, startedAt: String, endedAt: String, endOdometerKm: String? = nil) {
        self.version = version; self.tripId = tripId; self.startedAt = startedAt; self.endedAt = endedAt; self.endOdometerKm = endOdometerKm
    }
}
public enum CSMSharedVehicleMileageStatus: String, Codable, Sendable { case unknown, known, estimated, reviewRequired }
public enum CSMSharedVehicleMileageRecordKind: String, Codable, Sendable { case odometer, energy, service, ride_summary }
public enum CSMSharedVehicleMileageReason: String, Codable, Sendable {
    case no_observations, conflicting_observations, decreasing_observation, invalid_observation, invalid_correction, future_observation
    case overlapping_rides, anchor_overlap, legacy_ride_interval_unknown, duplicate_trip, distance_overflow, invalid_ride_interval
}
public struct CSMSharedVehicleMileageSource: Codable, Sendable {
    public let recordId: UUID
    public let recordRevision: Int
    public let recordKind: CSMSharedVehicleMileageRecordKind
    public init(recordId: UUID, recordRevision: Int, recordKind: CSMSharedVehicleMileageRecordKind) {
        self.recordId = recordId; self.recordRevision = recordRevision; self.recordKind = recordKind
    }
}
public struct CSMSharedVehicleOdometerSnapshotV2: Codable, Sendable {
    public let version: Int
    public let status: CSMSharedVehicleMileageStatus
    public let dataRevision: Int
    public let valueKm: String?
    public let observedAt: String?
    public let source: CSMSharedVehicleMileageSource?
    public let basisKm: String?
    public let basisObservedAt: String?
    public let basisSource: CSMSharedVehicleMileageSource?
    public let includedRideCount: Int?
    public let unconfirmedDistanceKm: String?
    public let reason: CSMSharedVehicleMileageReason?
    public init(version: Int = 2, status: CSMSharedVehicleMileageStatus, dataRevision: Int, valueKm: String? = nil, observedAt: String? = nil, source: CSMSharedVehicleMileageSource? = nil, basisKm: String? = nil, basisObservedAt: String? = nil, basisSource: CSMSharedVehicleMileageSource? = nil, includedRideCount: Int? = nil, unconfirmedDistanceKm: String? = nil, reason: CSMSharedVehicleMileageReason? = nil) {
        self.version = version; self.status = status; self.dataRevision = dataRevision; self.valueKm = valueKm; self.observedAt = observedAt; self.source = source
        self.basisKm = basisKm; self.basisObservedAt = basisObservedAt; self.basisSource = basisSource; self.includedRideCount = includedRideCount; self.unconfirmedDistanceKm = unconfirmedDistanceKm; self.reason = reason
    }
    private static func validNumber(_ value: String) -> Bool { value.range(of: #"^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$"#, options: .regularExpression) != nil }
    private static func validDate(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter(); if formatter.date(from: value) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds); return formatter.date(from: value) != nil
    }
    private func validValue(for revision: Int) -> String? {
        guard version == 2, dataRevision == revision, reason == nil, let valueKm, Self.validNumber(valueKm), let observedAt, Self.validDate(observedAt) else { return nil }
        return valueKm
    }
    public func knownValueKm(for revision: Int) -> String? {
        guard status == .known, source?.recordRevision ?? 0 > 0 else { return nil }
        return validValue(for: revision)
    }
    /// Display only as calculated mileage, never a confirmed instrument reading.
    public func estimatedValueKm(for revision: Int) -> String? {
        guard status == .estimated, basisSource?.recordRevision ?? 0 > 0, includedRideCount ?? 0 > 0,
              let basisKm, Self.validNumber(basisKm), let basisObservedAt, Self.validDate(basisObservedAt),
              let unconfirmedDistanceKm, Self.validNumber(unconfirmedDistanceKm), let value = validValue(for: revision),
              NSDecimalNumber(string: basisKm, locale: Locale(identifier: "en_US_POSIX")).adding(NSDecimalNumber(string: unconfirmedDistanceKm, locale: Locale(identifier: "en_US_POSIX"))).compare(NSDecimalNumber(string: value, locale: Locale(identifier: "en_US_POSIX"))) == .orderedSame else { return nil }
        return value
    }
}
public extension CSMMobilityCapabilities {
    var supportsOdometerSnapshotV2: Bool { odometerSnapshotVersions?.contains(2) == true }
    var supportsRideDetailsV1: Bool { rideDetailsVersions?.contains(1) == true }
    var supportsCommutativeRideInsert: Bool { supportsRideDetailsV1 && rideInsertPolicy == "append_only_membership_cas" }
    var supportsInitialOdometer: Bool { initialOdometerSupported == true }
}
