import Foundation

public enum CSMSharedVehicleOdometerStatus: String, Codable, Sendable {
    case unknown, known, reviewRequired
}
public enum CSMSharedVehicleOdometerRecordKind: String, Codable, Sendable {
    case odometer, energy, service
}
public enum CSMSharedVehicleOdometerReason: String, Codable, Sendable {
    case no_observations, conflicting_observations, decreasing_observation
    case invalid_observation, invalid_correction, future_observation
}
public struct CSMSharedVehicleOdometerSource: Codable, Sendable {
    public let recordId: UUID
    public let recordRevision: Int
    public let recordKind: CSMSharedVehicleOdometerRecordKind
    public init(recordId: UUID, recordRevision: Int, recordKind: CSMSharedVehicleOdometerRecordKind) {
        self.recordId = recordId; self.recordRevision = recordRevision; self.recordKind = recordKind
    }
}
public struct CSMSharedVehicleOdometerSnapshot: Codable, Sendable {
    public let version: Int
    public let status: CSMSharedVehicleOdometerStatus
    public let dataRevision: Int
    public let valueKm: String?
    public let observedAt: String?
    public let source: CSMSharedVehicleOdometerSource?
    public let reason: CSMSharedVehicleOdometerReason?
    public init(version: Int = 1, status: CSMSharedVehicleOdometerStatus, dataRevision: Int, valueKm: String? = nil, observedAt: String? = nil, source: CSMSharedVehicleOdometerSource? = nil, reason: CSMSharedVehicleOdometerReason? = nil) {
        self.version = version; self.status = status; self.dataRevision = dataRevision
        self.valueKm = valueKm; self.observedAt = observedAt; self.source = source; self.reason = reason
    }
    private static func validDate(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value) != nil
    }
    /// Never use a missing, stale, unsupported or uncertain snapshot as zero/current mileage.
    public func knownValueKm(for expectedDataRevision: Int) -> String? {
        guard version == 1, status == .known, dataRevision == expectedDataRevision,
              reason == nil, source?.recordRevision ?? 0 > 0, let observedAt,
              Self.validDate(observedAt),
              let valueKm, valueKm.range(of: #"^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$"#, options: .regularExpression) != nil else { return nil }
        return valueKm
    }
}
public extension CSMMobilityCapabilities {
    var supportsOdometerSnapshotV1: Bool { odometerSnapshotVersions?.contains(1) == true }
}
