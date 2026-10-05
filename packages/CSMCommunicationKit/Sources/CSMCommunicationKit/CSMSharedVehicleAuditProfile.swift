import Foundation

public struct CSMSharedVehicleMappedTrailer: Codable, Sendable {
    public let attached: Bool
    public let heightM, widthM, lengthM, loadedWeightKg: Double
    public init(heightM: Double, widthM: Double, lengthM: Double, loadedWeightKg: Double) {
        attached = true; self.heightM = heightM; self.widthM = widthM; self.lengthM = lengthM; self.loadedWeightKg = loadedWeightKg
    }
}
public struct CSMSharedVehicleMappedDimensions: Codable, Sendable {
    public let heightM, widthM, lengthM, loadedWeightKg: Double
    public let axleLoadKg: Double?
    public let axleCount: Int?
    public let trailer: CSMSharedVehicleMappedTrailer?
    public init(heightM: Double, widthM: Double, lengthM: Double, loadedWeightKg: Double, axleLoadKg: Double? = nil, axleCount: Int? = nil, trailer: CSMSharedVehicleMappedTrailer? = nil) {
        self.heightM = heightM; self.widthM = widthM; self.lengthM = lengthM; self.loadedWeightKg = loadedWeightKg
        self.axleLoadKg = axleLoadKg; self.axleCount = axleCount; self.trailer = trailer
    }
}
/// Exactly the mapped SIM request, not a route assessment or a claim of physical measurement.
public struct CSMSharedVehicleMappedProfile: Codable, Sendable {
    public let version: String
    public let intent: String
    public let coverageAcknowledged: String
    public let vehicle: CSMSharedVehicleMappedDimensions?
    public let driverDeclaredAuthorization: Bool?
    public init(intent: String, vehicle: CSMSharedVehicleMappedDimensions? = nil, driverDeclaredAuthorization: Bool? = nil) {
        version = "sim-mapped-road-profile-v1"; coverageAcknowledged = "mapped_restrictions_incomplete"
        self.intent = intent; self.vehicle = vehicle; self.driverDeclaredAuthorization = driverDeclaredAuthorization
    }
    public var isValid: Bool {
        guard version == "sim-mapped-road-profile-v1", coverageAcknowledged == "mapped_restrictions_incomplete", driverDeclaredAuthorization != true,
              ["car", "commercial_truck", "car_with_trailer", "road_legal_4x4"].contains(intent) else { return false }
        guard let vehicle else { return intent == "car" || intent == "road_legal_4x4" }
        func valid(_ h: Double, _ w: Double, _ l: Double, _ kg: Double) -> Bool {
            [(h, 5.0), (w, 3.0), (l, 25.0), (kg, 60_000.0)].allSatisfy { $0.0.isFinite && $0.0 > 0 && $0.0 <= $0.1 }
        }
        guard valid(vehicle.heightM, vehicle.widthM, vehicle.lengthM, vehicle.loadedWeightKg) else { return false }
        if intent != "commercial_truck" && (vehicle.axleLoadKg != nil || vehicle.axleCount != nil) { return false }
        if let axle = vehicle.axleLoadKg, !axle.isFinite || axle <= 0 || axle > min(40_000, vehicle.loadedWeightKg) { return false }
        if let count = vehicle.axleCount, !(2...20).contains(count) { return false }
        guard (intent == "car_with_trailer") == (vehicle.trailer != nil) else { return false }
        if let trailer = vehicle.trailer {
            guard trailer.attached, valid(trailer.heightM, trailer.widthM, trailer.lengthM, trailer.loadedWeightKg),
                  trailer.heightM <= vehicle.heightM, trailer.widthM <= vehicle.widthM, trailer.lengthM <= vehicle.lengthM, trailer.loadedWeightKg <= vehicle.loadedWeightKg else { return false }
        }
        return true
    }
}
public enum CSMSharedVehiclePowertrain: String, Codable, Sendable { case combustion, electric, plugInHybrid }
public struct CSMSharedVehicleRoutingProfile: Codable, Sendable {
    public let version: Int
    public let mappedProfile: CSMSharedVehicleMappedProfile
    public let powertrain: CSMSharedVehiclePowertrain
    public init(version: Int = 1, mappedProfile: CSMSharedVehicleMappedProfile, powertrain: CSMSharedVehiclePowertrain) {
        self.version = version; self.mappedProfile = mappedProfile; self.powertrain = powertrain
    }
    public var isValid: Bool { version == 1 && mappedProfile.isValid }
}
public struct CSMSharedVehicleOwnerBindingInput: Codable, Sendable {
    public let version: Int
    public let localVehicleId: UUID
    public init(version: Int = 1, localVehicleId: UUID) { self.version = version; self.localVehicleId = localVehicleId }
}
public struct CSMSharedVehicleOwnerBinding: Codable, Sendable {
    public let version: Int
    public let localVehicleId, ownerAccountId: UUID
    public init(version: Int = 1, localVehicleId: UUID, ownerAccountId: UUID) { self.version = version; self.localVehicleId = localVehicleId; self.ownerAccountId = ownerAccountId }
}
public struct CSMSharedVehicleRecordCorrection: Codable, Sendable {
    public let version: Int
    public let recordId: UUID
    public let recordRevision: Int
    public let reason: String
    public init(version: Int = 1, recordId: UUID, recordRevision: Int, reason: String) {
        self.version = version; self.recordId = recordId; self.recordRevision = recordRevision; self.reason = reason
    }
}
public struct CSMSharedVehicleRecordAudit: Codable, Sendable {
    public let version: Int
    public let action: String
    public let operationId: UUID
    public let previousRecordId: UUID?
    public let previousRecordRevision: Int?
    public let reason: String?
    public init(version: Int = 1, action: String, operationId: UUID, previousRecordId: UUID? = nil, previousRecordRevision: Int? = nil, reason: String? = nil) {
        self.version = version; self.action = action; self.operationId = operationId; self.previousRecordId = previousRecordId; self.previousRecordRevision = previousRecordRevision; self.reason = reason
    }
}
public struct CSMSharedVehicleActiveCareItem: Codable, Sendable {
    public let recordId: UUID
    public let recordRevision: Int
    public let title: String
    public let dueAt: String?
    public let dueOdometerKm: String?
    public init(recordId: UUID, recordRevision: Int, title: String, dueAt: String? = nil, dueOdometerKm: String? = nil) {
        self.recordId = recordId; self.recordRevision = recordRevision; self.title = title; self.dueAt = dueAt; self.dueOdometerKm = dueOdometerKm
    }
}
public struct CSMSharedVehicleActiveCareReminders: Codable, Sendable {
    public let version: Int
    public let dataRevision: Int
    public let state: String
    public let items: [CSMSharedVehicleActiveCareItem]
    public init(version: Int = 1, dataRevision: Int, state: String, items: [CSMSharedVehicleActiveCareItem]) {
        self.version = version; self.dataRevision = dataRevision; self.state = state; self.items = items
    }
    public func currentItems(for revision: Int) -> [CSMSharedVehicleActiveCareItem]? {
        guard version == 1, dataRevision == revision, state == "complete", items.count <= 500, Set(items.map(\.recordId)).count == items.count,
              items.allSatisfy({ $0.recordRevision > 0 && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        for item in items {
            if let number = item.dueOdometerKm, number.range(of: #"^(0|[1-9][0-9]{0,8})(\.[0-9]{1,3})?$"#, options: .regularExpression) == nil { return nil }
            if let date = item.dueAt {
                let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
                guard formatter.date(from: date) != nil || ISO8601DateFormatter().date(from: date) != nil else { return nil }
            }
        }
        return items
    }
}
public extension CSMSharedVehicle {
    func currentRoutingProfile(for revision: Int) -> CSMSharedVehicleRoutingProfile? {
        guard dataRevision == revision, !deleted, let profile = details.routingProfile, profile.isValid else { return nil }
        return profile
    }
    /// Use an authenticated fresh list/get result in the current account scope, never a plate/name match.
    func verifiedOwnerVehicleId(for accountId: UUID) -> UUID? {
        guard !deleted, let binding = ownerBinding, binding.version == 1, binding.ownerAccountId == accountId,
              members.contains(where: { $0.accountId == accountId && $0.role == .owner }) else { return nil }
        return binding.localVehicleId
    }
}
public extension CSMMobilityCapabilities {
    var supportsSharedRoutingProfile: Bool { sharedRoutingProfileVersions?.contains(1) == true }
    var supportsOwnerBinding: Bool { ownerBindingVersions?.contains(1) == true }
    var supportsAuditedRecordChanges: Bool { recordAuditVersions?.contains(1) == true }
    var supportsActiveCareReminders: Bool { activeCareReminderVersions?.contains(1) == true }
}
