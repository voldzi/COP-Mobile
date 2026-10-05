import Foundation

public enum CSMSharedVehicleEnergyDetailsKind: String, Codable, Sendable {
    case refueling, charging
}

public enum CSMSharedVehicleChargingSource: String, Codable, Sendable {
    case home, publicAC, publicDC, workplace, other
}

public struct CSMSharedVehicleStationSnapshot: Codable, Sendable {
    public let name: String?
    public let provider: String?
    public let address: String?
    public init(name: String? = nil, provider: String? = nil, address: String? = nil) {
        self.name = name
        self.provider = provider
        self.address = address
    }
}

public struct CSMSharedVehicleRefuelingDetails: Codable, Sendable {
    public let fuelType: String?
    public let fullTank: Bool?
    public let quantityBeforeRefueling: String?
    public let station: CSMSharedVehicleStationSnapshot?
    public init(fuelType: String? = nil, fullTank: Bool? = nil, quantityBeforeRefueling: String? = nil, station: CSMSharedVehicleStationSnapshot? = nil) {
        self.fuelType = fuelType
        self.fullTank = fullTank
        self.quantityBeforeRefueling = quantityBeforeRefueling
        self.station = station
    }
}

public struct CSMSharedVehicleChargingDetails: Codable, Sendable {
    public let source: CSMSharedVehicleChargingSource?
    public let provider: String?
    public let locationName: String?
    public let location: CSMSharedVehicleStationSnapshot?
    public let batteryPercentBefore: String?
    public let batteryPercentAfter: String?
    public init(source: CSMSharedVehicleChargingSource? = nil, provider: String? = nil, locationName: String? = nil, location: CSMSharedVehicleStationSnapshot? = nil, batteryPercentBefore: String? = nil, batteryPercentAfter: String? = nil) {
        self.source = source
        self.provider = provider
        self.locationName = locationName
        self.location = location
        self.batteryPercentBefore = batteryPercentBefore
        self.batteryPercentAfter = batteryPercentAfter
    }
}

public struct CSMSharedVehicleEnergyDetails: Codable, Sendable {
    public let version: Int
    public let kind: CSMSharedVehicleEnergyDetailsKind
    public let odometerKm: String?
    public let note: String?
    public let refueling: CSMSharedVehicleRefuelingDetails?
    public let charging: CSMSharedVehicleChargingDetails?
    public init(version: Int = 1, kind: CSMSharedVehicleEnergyDetailsKind, odometerKm: String? = nil, note: String? = nil, refueling: CSMSharedVehicleRefuelingDetails? = nil, charging: CSMSharedVehicleChargingDetails? = nil) {
        self.version = version
        self.kind = kind
        self.odometerKm = odometerKm
        self.note = note
        self.refueling = refueling
        self.charging = charging
    }
}

public struct CSMSharedVehicleServiceItem: Codable, Sendable {
    public let itemId: UUID
    public let title: String
    public let categoryId: String?
    public let subcategoryId: String?
    public let amount: CSMSharedVehicleMoney
    public init(itemId: UUID, title: String, categoryId: String? = nil, subcategoryId: String? = nil, amount: CSMSharedVehicleMoney) {
        self.itemId = itemId
        self.title = title
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
        self.amount = amount
    }
}

public struct CSMSharedVehicleServiceDetails: Codable, Sendable {
    public let version: Int
    public let note: String?
    public let categoryId: String?
    public let subcategoryId: String?
    public let items: [CSMSharedVehicleServiceItem]?
    public init(version: Int = 1, note: String? = nil, categoryId: String? = nil, subcategoryId: String? = nil, items: [CSMSharedVehicleServiceItem]? = nil) {
        self.version = version
        self.note = note
        self.categoryId = categoryId
        self.subcategoryId = subcategoryId
        self.items = items
    }
}

public extension CSMMobilityCapabilities {
    /// A missing advertisement from an older server is unknown/unsupported, never enabled.
    var supportsRecordDetailsV1: Bool { recordDetailsVersions?.contains(1) == true && recordEnergyUnits != nil && supportedRefuelingFuelTypes != nil }
}

public extension CSMSharedVehicleRecordData {
    var recordDetailsVersion: Int? {
        switch self {
        case .energy(let value): value.details?.version
        case .service(let value): value.details?.version
        default: nil
        }
    }
    var canEditRecordDetailsV1: Bool { recordDetailsVersion == nil || recordDetailsVersion == 1 }
}
