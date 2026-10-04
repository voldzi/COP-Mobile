import Foundation

// Generated from COP shared-mobility-v1.openapi.json. No credentials or coordinates in server DTOs.

public enum CSMMobilityCapabilitiesContractVersion: String, Codable, Sendable {
    case cop_mobility_capabilities_v1 = "cop-mobility-capabilities-v1"
}

public enum CSMMobilityCapabilitiesRegistration: String, Codable, Sendable {
    case idp_login_page = "idp_login_page"
    case unavailable = "unavailable"
    case unverified = "unverified"
}

public enum CSMMobilityCapabilitiesDispatchTransport: String, Codable, Sendable {
    case recipient_encrypted_latest_only = "recipient_encrypted_latest_only"
}

public enum CSMMobilityCapabilitiesCurrenciesItem: String, Codable, Sendable {
    case CZK = "CZK"
    case EUR = "EUR"
    case USD = "USD"
}

public enum CSMMobilityCapabilitiesInvitationDelivery: String, Codable, Sendable {
    case verified_account_inbox = "verified_account_inbox"
}

public struct CSMMobilityCapabilities: Codable, Sendable {
    public let contractVersion: CSMMobilityCapabilitiesContractVersion
    public let sharedVehiclesEnabled: Bool
    public let dispatchEnabled: Bool
    public let maxVehicleMembers: Int
    public let maxGroupMembers: Int
    public let registration: CSMMobilityCapabilitiesRegistration
    public let dispatchTransport: CSMMobilityCapabilitiesDispatchTransport
    public let currencies: [CSMMobilityCapabilitiesCurrenciesItem]
    public let serverTimestamp: String
    public let invitationDelivery: CSMMobilityCapabilitiesInvitationDelivery
    public init(contractVersion: CSMMobilityCapabilitiesContractVersion, sharedVehiclesEnabled: Bool, dispatchEnabled: Bool, maxVehicleMembers: Int, maxGroupMembers: Int, registration: CSMMobilityCapabilitiesRegistration, dispatchTransport: CSMMobilityCapabilitiesDispatchTransport, currencies: [CSMMobilityCapabilitiesCurrenciesItem], serverTimestamp: String, invitationDelivery: CSMMobilityCapabilitiesInvitationDelivery) {
        self.contractVersion = contractVersion
        self.sharedVehiclesEnabled = sharedVehiclesEnabled
        self.dispatchEnabled = dispatchEnabled
        self.maxVehicleMembers = maxVehicleMembers
        self.maxGroupMembers = maxGroupMembers
        self.registration = registration
        self.dispatchTransport = dispatchTransport
        self.currencies = currencies
        self.serverTimestamp = serverTimestamp
        self.invitationDelivery = invitationDelivery
    }
}

public enum CSMMobilityAccountContractVersion: String, Codable, Sendable {
    case cop_mobility_account_v1 = "cop-mobility-account-v1"
}

public struct CSMMobilityAccount: Codable, Sendable {
    public let contractVersion: CSMMobilityAccountContractVersion
    public let accountId: UUID
    public let displayName: String
    public let email: String?
    public let emailVerified: Bool
    public let serverTimestamp: String
    public init(contractVersion: CSMMobilityAccountContractVersion, accountId: UUID, displayName: String, email: String? = nil, emailVerified: Bool, serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.accountId = accountId
        self.displayName = displayName
        self.email = email
        self.emailVerified = emailVerified
        self.serverTimestamp = serverTimestamp
    }
}

public enum CSMSharedVehicleMemberRole: String, Codable, Sendable {
    case owner = "owner"
    case driver = "driver"
}

public enum CSMSharedVehicleMemberCapabilitiesItem: String, Codable, Sendable {
    case readVehicle = "readVehicle"
    case readCosts = "readCosts"
    case recordRide = "recordRide"
    case recordExpense = "recordExpense"
    case recordService = "recordService"
    case editVehicle = "editVehicle"
    case manageReminders = "manageReminders"
    case manageMembers = "manageMembers"
}

public struct CSMSharedVehicleMember: Codable, Sendable {
    public let accountId: UUID
    public let displayName: String
    public let role: CSMSharedVehicleMemberRole
    public let capabilities: [CSMSharedVehicleMemberCapabilitiesItem]
    public let joinedAt: String
    public init(accountId: UUID, displayName: String, role: CSMSharedVehicleMemberRole, capabilities: [CSMSharedVehicleMemberCapabilitiesItem], joinedAt: String) {
        self.accountId = accountId
        self.displayName = displayName
        self.role = role
        self.capabilities = capabilities
        self.joinedAt = joinedAt
    }
}

public struct CSMSharedVehicleDetails: Codable, Sendable {
    public let name: String
    public let plate: String?
    public let vin: String?
    public init(name: String, plate: String? = nil, vin: String? = nil) {
        self.name = name
        self.plate = plate
        self.vin = vin
    }
}

public enum CSMSharedVehicleContractVersion: String, Codable, Sendable {
    case cop_shared_vehicles_v1 = "cop-shared-vehicles-v1"
}

public struct CSMSharedVehicle: Codable, Sendable {
    public let contractVersion: CSMSharedVehicleContractVersion
    public let vehicleId: UUID
    public let details: CSMSharedVehicleDetails
    public let dataRevision: Int
    public let membershipRevision: Int
    public let members: [CSMSharedVehicleMember]
    public let createdAt: String
    public let updatedAt: String
    public let deleted: Bool
    public init(contractVersion: CSMSharedVehicleContractVersion, vehicleId: UUID, details: CSMSharedVehicleDetails, dataRevision: Int, membershipRevision: Int, members: [CSMSharedVehicleMember], createdAt: String, updatedAt: String, deleted: Bool) {
        self.contractVersion = contractVersion
        self.vehicleId = vehicleId
        self.details = details
        self.dataRevision = dataRevision
        self.membershipRevision = membershipRevision
        self.members = members
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

public enum CSMSharedVehicleListContractVersion: String, Codable, Sendable {
    case cop_shared_vehicles_v1 = "cop-shared-vehicles-v1"
}

public struct CSMSharedVehicleList: Codable, Sendable {
    public let contractVersion: CSMSharedVehicleListContractVersion
    public let items: [CSMSharedVehicle]
    public let serverTimestamp: String
    public init(contractVersion: CSMSharedVehicleListContractVersion, items: [CSMSharedVehicle], serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.items = items
        self.serverTimestamp = serverTimestamp
    }
}

public struct CSMSharedVehicleCreate: Codable, Sendable {
    public let operationId: UUID
    public let details: CSMSharedVehicleDetails
    public init(operationId: UUID, details: CSMSharedVehicleDetails) {
        self.operationId = operationId
        self.details = details
    }
}

public struct CSMSharedVehicleUpdate: Codable, Sendable {
    public let operationId: UUID
    public let expectedDataRevision: Int
    public let expectedMembershipRevision: Int
    public let details: CSMSharedVehicleDetails
    public init(operationId: UUID, expectedDataRevision: Int, expectedMembershipRevision: Int, details: CSMSharedVehicleDetails) {
        self.operationId = operationId
        self.expectedDataRevision = expectedDataRevision
        self.expectedMembershipRevision = expectedMembershipRevision
        self.details = details
    }
}

public enum CSMSharedVehicleMembershipChangeAction: String, Codable, Sendable {
    case set_capabilities = "set_capabilities"
    case remove = "remove"
    case transfer_ownership = "transfer_ownership"
    case leave = "leave"
}

public enum CSMSharedVehicleMembershipChangeCapabilitiesItem: String, Codable, Sendable {
    case readVehicle = "readVehicle"
    case readCosts = "readCosts"
    case recordRide = "recordRide"
    case recordExpense = "recordExpense"
    case recordService = "recordService"
    case editVehicle = "editVehicle"
    case manageReminders = "manageReminders"
    case manageMembers = "manageMembers"
}

public struct CSMSharedVehicleMembershipChange: Codable, Sendable {
    public let operationId: UUID
    public let expectedMembershipRevision: Int
    public let accountId: UUID
    public let action: CSMSharedVehicleMembershipChangeAction
    public let capabilities: [CSMSharedVehicleMembershipChangeCapabilitiesItem]?
    public init(operationId: UUID, expectedMembershipRevision: Int, accountId: UUID, action: CSMSharedVehicleMembershipChangeAction, capabilities: [CSMSharedVehicleMembershipChangeCapabilitiesItem]? = nil) {
        self.operationId = operationId
        self.expectedMembershipRevision = expectedMembershipRevision
        self.accountId = accountId
        self.action = action
        self.capabilities = capabilities
    }
}

public enum CSMMobilityInvitationCreateCapabilitiesItem: String, Codable, Sendable {
    case readVehicle = "readVehicle"
    case readCosts = "readCosts"
    case recordRide = "recordRide"
    case recordExpense = "recordExpense"
    case recordService = "recordService"
    case editVehicle = "editVehicle"
    case manageReminders = "manageReminders"
    case manageMembers = "manageMembers"
}

public struct CSMMobilityInvitationCreate: Codable, Sendable {
    public let operationId: UUID
    public let expectedMembershipRevision: Int
    public let email: String
    public let capabilities: [CSMMobilityInvitationCreateCapabilitiesItem]?
    public init(operationId: UUID, expectedMembershipRevision: Int, email: String, capabilities: [CSMMobilityInvitationCreateCapabilitiesItem]? = nil) {
        self.operationId = operationId
        self.expectedMembershipRevision = expectedMembershipRevision
        self.email = email
        self.capabilities = capabilities
    }
}

public enum CSMMobilityInvitationReceiptContractVersion: String, Codable, Sendable {
    case cop_mobility_invitation_v1 = "cop-mobility-invitation-v1"
}

public enum CSMMobilityInvitationReceiptStatus: String, Codable, Sendable {
    case queued = "queued"
}

public struct CSMMobilityInvitationReceipt: Codable, Sendable {
    public let contractVersion: CSMMobilityInvitationReceiptContractVersion
    public let invitationId: UUID
    public let operationId: UUID
    public let status: CSMMobilityInvitationReceiptStatus
    public let expiresAt: String
    public init(contractVersion: CSMMobilityInvitationReceiptContractVersion, invitationId: UUID, operationId: UUID, status: CSMMobilityInvitationReceiptStatus, expiresAt: String) {
        self.contractVersion = contractVersion
        self.invitationId = invitationId
        self.operationId = operationId
        self.status = status
        self.expiresAt = expiresAt
    }
}

public struct CSMMobilityInvitationAccept: Codable, Sendable {
    public let operationId: UUID
    public let invitationId: UUID
    public init(operationId: UUID, invitationId: UUID) {
        self.operationId = operationId
        self.invitationId = invitationId
    }
}

public struct CSMMobilityInvitationRevoke: Codable, Sendable {
    public let operationId: UUID
    public let invitationId: UUID
    public init(operationId: UUID, invitationId: UUID) {
        self.operationId = operationId
        self.invitationId = invitationId
    }
}

public enum CSMSharedVehicleMoneyCurrency: String, Codable, Sendable {
    case CZK = "CZK"
    case EUR = "EUR"
    case USD = "USD"
}

public struct CSMSharedVehicleMoney: Codable, Sendable {
    public let currency: CSMSharedVehicleMoneyCurrency
    public let minorUnits: String
    public init(currency: CSMSharedVehicleMoneyCurrency, minorUnits: String) {
        self.currency = currency
        self.minorUnits = minorUnits
    }
}

public enum CSMSharedVehicleRecordDataOdometerKind: String, Codable, Sendable {
    case odometer = "odometer"
}

public struct CSMSharedVehicleRecordDataOdometer: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataOdometerKind
    public let odometerKm: String
    public let correctionOfRecordId: UUID?
    public let correctionReason: String?
    public init(kind: CSMSharedVehicleRecordDataOdometerKind, odometerKm: String, correctionOfRecordId: UUID? = nil, correctionReason: String? = nil) {
        self.kind = kind
        self.odometerKm = odometerKm
        self.correctionOfRecordId = correctionOfRecordId
        self.correctionReason = correctionReason
    }
}

public enum CSMSharedVehicleRecordDataRideSummaryKind: String, Codable, Sendable {
    case ride_summary = "ride_summary"
}

public enum CSMSharedVehicleRecordDataRideSummaryPurpose: String, Codable, Sendable {
    case work = "work"
}

public struct CSMSharedVehicleRecordDataRideSummary: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataRideSummaryKind
    public let distanceKm: String
    public let durationSeconds: Int
    public let purpose: CSMSharedVehicleRecordDataRideSummaryPurpose
    public init(kind: CSMSharedVehicleRecordDataRideSummaryKind, distanceKm: String, durationSeconds: Int, purpose: CSMSharedVehicleRecordDataRideSummaryPurpose) {
        self.kind = kind
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.purpose = purpose
    }
}

public enum CSMSharedVehicleRecordDataExpenseKind: String, Codable, Sendable {
    case expense = "expense"
}

public enum CSMSharedVehicleRecordDataExpenseCategory: String, Codable, Sendable {
    case fuel = "fuel"
    case charging = "charging"
    case parking = "parking"
    case toll = "toll"
    case other = "other"
}

public struct CSMSharedVehicleRecordDataExpense: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataExpenseKind
    public let category: CSMSharedVehicleRecordDataExpenseCategory
    public let amount: CSMSharedVehicleMoney
    public init(kind: CSMSharedVehicleRecordDataExpenseKind, category: CSMSharedVehicleRecordDataExpenseCategory, amount: CSMSharedVehicleMoney) {
        self.kind = kind
        self.category = category
        self.amount = amount
    }
}

public enum CSMSharedVehicleRecordDataEnergyKind: String, Codable, Sendable {
    case energy = "energy"
}

public enum CSMSharedVehicleRecordDataEnergyUnit: String, Codable, Sendable {
    case liters = "liters"
    case kWh = "kWh"
}

public struct CSMSharedVehicleRecordDataEnergy: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataEnergyKind
    public let unit: CSMSharedVehicleRecordDataEnergyUnit
    public let quantity: String
    public let amount: CSMSharedVehicleMoney?
    public init(kind: CSMSharedVehicleRecordDataEnergyKind, unit: CSMSharedVehicleRecordDataEnergyUnit, quantity: String, amount: CSMSharedVehicleMoney? = nil) {
        self.kind = kind
        self.unit = unit
        self.quantity = quantity
        self.amount = amount
    }
}

public enum CSMSharedVehicleRecordDataServiceKind: String, Codable, Sendable {
    case service = "service"
}

public struct CSMSharedVehicleRecordDataService: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataServiceKind
    public let title: String
    public let odometerKm: String?
    public let amount: CSMSharedVehicleMoney?
    public init(kind: CSMSharedVehicleRecordDataServiceKind, title: String, odometerKm: String? = nil, amount: CSMSharedVehicleMoney? = nil) {
        self.kind = kind
        self.title = title
        self.odometerKm = odometerKm
        self.amount = amount
    }
}

public enum CSMSharedVehicleRecordDataReminderKind: String, Codable, Sendable {
    case reminder = "reminder"
}

public struct CSMSharedVehicleRecordDataReminder: Codable, Sendable {
    public let kind: CSMSharedVehicleRecordDataReminderKind
    public let title: String
    public let dueAt: String?
    public let dueOdometerKm: String?
    public let completed: Bool
    public init(kind: CSMSharedVehicleRecordDataReminderKind, title: String, dueAt: String? = nil, dueOdometerKm: String? = nil, completed: Bool) {
        self.kind = kind
        self.title = title
        self.dueAt = dueAt
        self.dueOdometerKm = dueOdometerKm
        self.completed = completed
    }
}

public enum CSMSharedVehicleRecordData: Codable, Sendable {
    case odometer(CSMSharedVehicleRecordDataOdometer)
    case ride_summary(CSMSharedVehicleRecordDataRideSummary)
    case expense(CSMSharedVehicleRecordDataExpense)
    case energy(CSMSharedVehicleRecordDataEnergy)
    case service(CSMSharedVehicleRecordDataService)
    case reminder(CSMSharedVehicleRecordDataReminder)
    private enum Keys: String, CodingKey { case kind }
    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .kind)
        switch kind {
        case "odometer": self = .odometer(try CSMSharedVehicleRecordDataOdometer(from: decoder))
        case "ride_summary": self = .ride_summary(try CSMSharedVehicleRecordDataRideSummary(from: decoder))
        case "expense": self = .expense(try CSMSharedVehicleRecordDataExpense(from: decoder))
        case "energy": self = .energy(try CSMSharedVehicleRecordDataEnergy(from: decoder))
        case "service": self = .service(try CSMSharedVehicleRecordDataService(from: decoder))
        case "reminder": self = .reminder(try CSMSharedVehicleRecordDataReminder(from: decoder))
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown shared record kind"))
        }
    }
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .odometer(let value): try value.encode(to: encoder)
        case .ride_summary(let value): try value.encode(to: encoder)
        case .expense(let value): try value.encode(to: encoder)
        case .energy(let value): try value.encode(to: encoder)
        case .service(let value): try value.encode(to: encoder)
        case .reminder(let value): try value.encode(to: encoder)
        }
    }
}

public struct CSMSharedVehicleRecord: Codable, Sendable {
    public let recordId: UUID
    public let vehicleId: UUID
    public let authorAccountId: UUID
    public let createdAt: String
    public let occurredAt: String
    public let timeZone: String
    public let revision: Int
    public let data: CSMSharedVehicleRecordData
    public let deleted: Bool
    public init(recordId: UUID, vehicleId: UUID, authorAccountId: UUID, createdAt: String, occurredAt: String, timeZone: String, revision: Int, data: CSMSharedVehicleRecordData, deleted: Bool) {
        self.recordId = recordId
        self.vehicleId = vehicleId
        self.authorAccountId = authorAccountId
        self.createdAt = createdAt
        self.occurredAt = occurredAt
        self.timeZone = timeZone
        self.revision = revision
        self.data = data
        self.deleted = deleted
    }
}

public struct CSMSharedVehicleRecordWrite: Codable, Sendable {
    public let operationId: UUID
    public let expectedDataRevision: Int
    public let expectedMembershipRevision: Int
    public let recordId: UUID
    public let expectedRecordRevision: Int
    public let occurredAt: String
    public let timeZone: String
    public let data: CSMSharedVehicleRecordData
    public init(operationId: UUID, expectedDataRevision: Int, expectedMembershipRevision: Int, recordId: UUID, expectedRecordRevision: Int, occurredAt: String, timeZone: String, data: CSMSharedVehicleRecordData) {
        self.operationId = operationId
        self.expectedDataRevision = expectedDataRevision
        self.expectedMembershipRevision = expectedMembershipRevision
        self.recordId = recordId
        self.expectedRecordRevision = expectedRecordRevision
        self.occurredAt = occurredAt
        self.timeZone = timeZone
        self.data = data
    }
}

public enum CSMSharedVehicleReceiptContractVersion: String, Codable, Sendable {
    case cop_shared_vehicles_v1 = "cop-shared-vehicles-v1"
}

public struct CSMSharedVehicleReceipt: Codable, Sendable {
    public let contractVersion: CSMSharedVehicleReceiptContractVersion
    public let operationId: UUID
    public let vehicleId: UUID
    public let dataRevision: Int
    public let membershipRevision: Int
    public let eventSequence: Int
    public let recordId: UUID?
    public let confirmed: Bool
    public init(contractVersion: CSMSharedVehicleReceiptContractVersion, operationId: UUID, vehicleId: UUID, dataRevision: Int, membershipRevision: Int, eventSequence: Int, recordId: UUID? = nil, confirmed: Bool) {
        self.contractVersion = contractVersion
        self.operationId = operationId
        self.vehicleId = vehicleId
        self.dataRevision = dataRevision
        self.membershipRevision = membershipRevision
        self.eventSequence = eventSequence
        self.recordId = recordId
        self.confirmed = confirmed
    }
}

public enum CSMSharedVehicleSyncItemType: String, Codable, Sendable {
    case vehicle = "vehicle"
    case record = "record"
    case membership = "membership"
    case deleted = "deleted"
}

public struct CSMSharedVehicleSyncItem: Codable, Sendable {
    public let sequence: Int
    public let type: CSMSharedVehicleSyncItemType
    public let vehicle: CSMSharedVehicle?
    public let record: CSMSharedVehicleRecord?
    public let recordId: UUID?
    public let authorAccountId: UUID
    public let createdAt: String
    public init(sequence: Int, type: CSMSharedVehicleSyncItemType, vehicle: CSMSharedVehicle? = nil, record: CSMSharedVehicleRecord? = nil, recordId: UUID? = nil, authorAccountId: UUID, createdAt: String) {
        self.sequence = sequence
        self.type = type
        self.vehicle = vehicle
        self.record = record
        self.recordId = recordId
        self.authorAccountId = authorAccountId
        self.createdAt = createdAt
    }
}

public enum CSMSharedVehicleSyncContractVersion: String, Codable, Sendable {
    case cop_shared_vehicles_v1 = "cop-shared-vehicles-v1"
}

public struct CSMSharedVehicleSync: Codable, Sendable {
    public let contractVersion: CSMSharedVehicleSyncContractVersion
    public let vehicleId: UUID
    public let items: [CSMSharedVehicleSyncItem]
    public let nextCursor: String
    public let hasMore: Bool
    public let dataRevision: Int
    public let membershipRevision: Int
    public let serverTimestamp: String
    public init(contractVersion: CSMSharedVehicleSyncContractVersion, vehicleId: UUID, items: [CSMSharedVehicleSyncItem], nextCursor: String, hasMore: Bool, dataRevision: Int, membershipRevision: Int, serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.vehicleId = vehicleId
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.dataRevision = dataRevision
        self.membershipRevision = membershipRevision
        self.serverTimestamp = serverTimestamp
    }
}

public enum CSMDispatchMemberRole: String, Codable, Sendable {
    case owner = "owner"
    case admin = "admin"
    case member = "member"
}

public struct CSMDispatchMember: Codable, Sendable {
    public let accountId: UUID
    public let displayName: String
    public let role: CSMDispatchMemberRole
    public init(accountId: UUID, displayName: String, role: CSMDispatchMemberRole) {
        self.accountId = accountId
        self.displayName = displayName
        self.role = role
    }
}

public enum CSMDispatchGroupContractVersion: String, Codable, Sendable {
    case cop_private_dispatch_v1 = "cop-private-dispatch-v1"
}

public struct CSMDispatchGroup: Codable, Sendable {
    public let contractVersion: CSMDispatchGroupContractVersion
    public let groupId: UUID
    public let name: String
    public let membershipRevision: Int
    public let sequence: Int
    public let members: [CSMDispatchMember]
    public let conversationId: String?
    public let createdAt: String
    public let deleted: Bool
    public init(contractVersion: CSMDispatchGroupContractVersion, groupId: UUID, name: String, membershipRevision: Int, sequence: Int, members: [CSMDispatchMember], conversationId: String? = nil, createdAt: String, deleted: Bool) {
        self.contractVersion = contractVersion
        self.groupId = groupId
        self.name = name
        self.membershipRevision = membershipRevision
        self.sequence = sequence
        self.members = members
        self.conversationId = conversationId
        self.createdAt = createdAt
        self.deleted = deleted
    }
}

public enum CSMDispatchGroupListContractVersion: String, Codable, Sendable {
    case cop_private_dispatch_v1 = "cop-private-dispatch-v1"
}

public struct CSMDispatchGroupList: Codable, Sendable {
    public let contractVersion: CSMDispatchGroupListContractVersion
    public let items: [CSMDispatchGroup]
    public let serverTimestamp: String
    public init(contractVersion: CSMDispatchGroupListContractVersion, items: [CSMDispatchGroup], serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.items = items
        self.serverTimestamp = serverTimestamp
    }
}

public struct CSMDispatchGroupCreate: Codable, Sendable {
    public let operationId: UUID
    public let name: String
    public init(operationId: UUID, name: String) {
        self.operationId = operationId
        self.name = name
    }
}

public enum CSMDispatchMembershipChangeAction: String, Codable, Sendable {
    case remove = "remove"
    case set_role = "set_role"
    case leave = "leave"
}

public enum CSMDispatchMembershipChangeRole: String, Codable, Sendable {
    case admin = "admin"
    case member = "member"
}

public struct CSMDispatchMembershipChange: Codable, Sendable {
    public let operationId: UUID
    public let expectedMembershipRevision: Int
    public let accountId: UUID
    public let action: CSMDispatchMembershipChangeAction
    public let role: CSMDispatchMembershipChangeRole?
    public init(operationId: UUID, expectedMembershipRevision: Int, accountId: UUID, action: CSMDispatchMembershipChangeAction, role: CSMDispatchMembershipChangeRole? = nil) {
        self.operationId = operationId
        self.expectedMembershipRevision = expectedMembershipRevision
        self.accountId = accountId
        self.action = action
        self.role = role
    }
}

public struct CSMDispatchDeviceRegister: Codable, Sendable {
    public let operationId: UUID
    public let publicKeyX25519: String
    public let deviceName: String
    public init(operationId: UUID, publicKeyX25519: String, deviceName: String) {
        self.operationId = operationId
        self.publicKeyX25519 = publicKeyX25519
        self.deviceName = deviceName
    }
}

public struct CSMDispatchDevice: Codable, Sendable {
    public let deviceId: UUID
    public let accountId: UUID
    public let publicKeyX25519: String
    public let keyRevision: Int
    public let createdAt: String
    public init(deviceId: UUID, accountId: UUID, publicKeyX25519: String, keyRevision: Int, createdAt: String) {
        self.deviceId = deviceId
        self.accountId = accountId
        self.publicKeyX25519 = publicKeyX25519
        self.keyRevision = keyRevision
        self.createdAt = createdAt
    }
}

public enum CSMDispatchReadinessContractVersion: String, Codable, Sendable {
    case cop_private_dispatch_v1 = "cop-private-dispatch-v1"
}

public enum CSMDispatchReadinessState: String, Codable, Sendable {
    case ready = "ready"
    case missing_device_keys = "missing_device_keys"
    case unavailable = "unavailable"
}

public struct CSMDispatchReadiness: Codable, Sendable {
    public let contractVersion: CSMDispatchReadinessContractVersion
    public let groupId: UUID
    public let membershipRevision: Int
    public let state: CSMDispatchReadinessState
    public let audienceHash: String
    public let devices: [CSMDispatchDevice]
    public let serverTimestamp: String
    public init(contractVersion: CSMDispatchReadinessContractVersion, groupId: UUID, membershipRevision: Int, state: CSMDispatchReadinessState, audienceHash: String, devices: [CSMDispatchDevice], serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.groupId = groupId
        self.membershipRevision = membershipRevision
        self.state = state
        self.audienceHash = audienceHash
        self.devices = devices
        self.serverTimestamp = serverTimestamp
    }
}

public enum CSMDispatchShareStartDurationSeconds: Int, Codable, Sendable {
    case value900 = 900
    case value3600 = 3600
    case value28800 = 28800
}

public enum CSMDispatchShareStartEndPolicy: String, Codable, Sendable {
    case duration = "duration"
    case ride_end = "ride_end"
}

public struct CSMDispatchShareStart: Codable, Sendable {
    public let operationId: UUID
    public let deviceId: UUID
    public let expectedMembershipRevision: Int
    public let audienceHash: String
    public let durationSeconds: CSMDispatchShareStartDurationSeconds
    public let endPolicy: CSMDispatchShareStartEndPolicy
    public let consent: Bool
    public init(operationId: UUID, deviceId: UUID, expectedMembershipRevision: Int, audienceHash: String, durationSeconds: CSMDispatchShareStartDurationSeconds, endPolicy: CSMDispatchShareStartEndPolicy, consent: Bool) {
        self.operationId = operationId
        self.deviceId = deviceId
        self.expectedMembershipRevision = expectedMembershipRevision
        self.audienceHash = audienceHash
        self.durationSeconds = durationSeconds
        self.endPolicy = endPolicy
        self.consent = consent
    }
}

public enum CSMDispatchShareEndPolicy: String, Codable, Sendable {
    case duration = "duration"
    case ride_end = "ride_end"
}

public enum CSMDispatchShareState: String, Codable, Sendable {
    case active = "active"
    case stopped = "stopped"
    case expired = "expired"
}

public struct CSMDispatchShare: Codable, Sendable {
    public let shareId: UUID
    public let groupId: UUID
    public let accountId: UUID
    public let deviceId: UUID
    public let membershipRevision: Int
    public let audienceHash: String
    public let startedAt: String
    public let expiresAt: String
    public let endPolicy: CSMDispatchShareEndPolicy
    public let state: CSMDispatchShareState
    public let sequence: Int
    public init(shareId: UUID, groupId: UUID, accountId: UUID, deviceId: UUID, membershipRevision: Int, audienceHash: String, startedAt: String, expiresAt: String, endPolicy: CSMDispatchShareEndPolicy, state: CSMDispatchShareState, sequence: Int) {
        self.shareId = shareId
        self.groupId = groupId
        self.accountId = accountId
        self.deviceId = deviceId
        self.membershipRevision = membershipRevision
        self.audienceHash = audienceHash
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.endPolicy = endPolicy
        self.state = state
        self.sequence = sequence
    }
}

public enum CSMDispatchShareReceiptContractVersion: String, Codable, Sendable {
    case cop_private_dispatch_v1 = "cop-private-dispatch-v1"
}

public struct CSMDispatchShareReceipt: Codable, Sendable {
    public let contractVersion: CSMDispatchShareReceiptContractVersion
    public let operationId: UUID
    public let share: CSMDispatchShare
    public let confirmed: Bool
    public let serverTimestamp: String
    public init(contractVersion: CSMDispatchShareReceiptContractVersion, operationId: UUID, share: CSMDispatchShare, confirmed: Bool, serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.operationId = operationId
        self.share = share
        self.confirmed = confirmed
        self.serverTimestamp = serverTimestamp
    }
}

public struct CSMDispatchEncryptedBox: Codable, Sendable {
    public let recipientDeviceId: UUID
    public let ephemeralPublicKeyX25519: String
    public let combinedCiphertext: String
    public init(recipientDeviceId: UUID, ephemeralPublicKeyX25519: String, combinedCiphertext: String) {
        self.recipientDeviceId = recipientDeviceId
        self.ephemeralPublicKeyX25519 = ephemeralPublicKeyX25519
        self.combinedCiphertext = combinedCiphertext
    }
}

public enum CSMDispatchPointPublishSource: String, Codable, Sendable {
    case gps = "gps"
}

public struct CSMDispatchPointPublish: Codable, Sendable {
    public let deviceId: UUID
    public let sequence: Int
    public let observedAt: String
    public let source: CSMDispatchPointPublishSource
    public let membershipRevision: Int
    public let audienceHash: String
    public let boxes: [CSMDispatchEncryptedBox]
    public init(deviceId: UUID, sequence: Int, observedAt: String, source: CSMDispatchPointPublishSource, membershipRevision: Int, audienceHash: String, boxes: [CSMDispatchEncryptedBox]) {
        self.deviceId = deviceId
        self.sequence = sequence
        self.observedAt = observedAt
        self.source = source
        self.membershipRevision = membershipRevision
        self.audienceHash = audienceHash
        self.boxes = boxes
    }
}

public enum CSMDispatchPointSource: String, Codable, Sendable {
    case gps = "gps"
}

public struct CSMDispatchPoint: Codable, Sendable {
    public let shareId: UUID
    public let accountId: UUID
    public let deviceId: UUID
    public let sequence: Int
    public let observedAt: String
    public let expiresAt: String
    public let source: CSMDispatchPointSource
    public let box: CSMDispatchEncryptedBox
    public init(shareId: UUID, accountId: UUID, deviceId: UUID, sequence: Int, observedAt: String, expiresAt: String, source: CSMDispatchPointSource, box: CSMDispatchEncryptedBox) {
        self.shareId = shareId
        self.accountId = accountId
        self.deviceId = deviceId
        self.sequence = sequence
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.source = source
        self.box = box
    }
}

public enum CSMDispatchSnapshotContractVersion: String, Codable, Sendable {
    case cop_private_dispatch_v1 = "cop-private-dispatch-v1"
}

public struct CSMDispatchSnapshot: Codable, Sendable {
    public let contractVersion: CSMDispatchSnapshotContractVersion
    public let group: CSMDispatchGroup
    public let readiness: CSMDispatchReadiness
    public let activeShares: [CSMDispatchShare]
    public let points: [CSMDispatchPoint]
    public let serverTimestamp: String
    public init(contractVersion: CSMDispatchSnapshotContractVersion, group: CSMDispatchGroup, readiness: CSMDispatchReadiness, activeShares: [CSMDispatchShare], points: [CSMDispatchPoint], serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.group = group
        self.readiness = readiness
        self.activeShares = activeShares
        self.points = points
        self.serverTimestamp = serverTimestamp
    }
}

public enum CSMDispatchStopReason: String, Codable, Sendable {
    case user = "user"
    case privacy_zone = "privacy_zone"
    case ride_end = "ride_end"
    case logout = "logout"
    case account_change = "account_change"
    case membership_change = "membership_change"
    case keys_unavailable = "keys_unavailable"
    case background_unavailable = "background_unavailable"
}

public struct CSMDispatchStop: Codable, Sendable {
    public let operationId: UUID
    public let deviceId: UUID
    public let reason: CSMDispatchStopReason
    public init(operationId: UUID, deviceId: UUID, reason: CSMDispatchStopReason) {
        self.operationId = operationId
        self.deviceId = deviceId
        self.reason = reason
    }
}

public struct CSMDispatchPointPayload: Codable, Sendable {
    public let lat: Double
    public let lon: Double
    public let horizontalAccuracyM: Double
    public init(lat: Double, lon: Double, horizontalAccuracyM: Double) {
        self.lat = lat
        self.lon = lon
        self.horizontalAccuracyM = horizontalAccuracyM
    }
}

public struct CSMMobilityErrorErrorDetailsItem: Codable, Sendable {
    public let path: String
    public let issue: String
    public init(path: String, issue: String) {
        self.path = path
        self.issue = issue
    }
}

public struct CSMMobilityErrorError: Codable, Sendable {
    public let code: String
    public let message: String
    public let correlationId: String
    public let details: [CSMMobilityErrorErrorDetailsItem]?
    public init(code: String, message: String, correlationId: String, details: [CSMMobilityErrorErrorDetailsItem]? = nil) {
        self.code = code
        self.message = message
        self.correlationId = correlationId
        self.details = details
    }
}

public struct CSMMobilityError: Codable, Sendable {
    public let error: CSMMobilityErrorError
    public init(error: CSMMobilityErrorError) {
        self.error = error
    }
}

public struct CSMSharedVehicleDelete: Codable, Sendable {
    public let operationId: UUID
    public let expectedDataRevision: Int
    public let expectedMembershipRevision: Int
    public let reason: String
    public init(operationId: UUID, expectedDataRevision: Int, expectedMembershipRevision: Int, reason: String) {
        self.operationId = operationId
        self.expectedDataRevision = expectedDataRevision
        self.expectedMembershipRevision = expectedMembershipRevision
        self.reason = reason
    }
}

public struct CSMSharedVehicleRecordDelete: Codable, Sendable {
    public let operationId: UUID
    public let expectedDataRevision: Int
    public let expectedMembershipRevision: Int
    public let recordId: UUID
    public let expectedRecordRevision: Int
    public let reason: String
    public init(operationId: UUID, expectedDataRevision: Int, expectedMembershipRevision: Int, recordId: UUID, expectedRecordRevision: Int, reason: String) {
        self.operationId = operationId
        self.expectedDataRevision = expectedDataRevision
        self.expectedMembershipRevision = expectedMembershipRevision
        self.recordId = recordId
        self.expectedRecordRevision = expectedRecordRevision
        self.reason = reason
    }
}

public struct CSMDispatchGroupDelete: Codable, Sendable {
    public let operationId: UUID
    public let expectedMembershipRevision: Int
    public init(operationId: UUID, expectedMembershipRevision: Int) {
        self.operationId = operationId
        self.expectedMembershipRevision = expectedMembershipRevision
    }
}

public struct CSMDispatchDeviceRevoke: Codable, Sendable {
    public let operationId: UUID
    public let deviceId: UUID
    public init(operationId: UUID, deviceId: UUID) {
        self.operationId = operationId
        self.deviceId = deviceId
    }
}

public struct CSMDispatchInvitationCreate: Codable, Sendable {
    public let operationId: UUID
    public let expectedMembershipRevision: Int
    public let email: String
    public init(operationId: UUID, expectedMembershipRevision: Int, email: String) {
        self.operationId = operationId
        self.expectedMembershipRevision = expectedMembershipRevision
        self.email = email
    }
}

public enum CSMMobilityPendingInvitationEntityType: String, Codable, Sendable {
    case vehicle = "vehicle"
    case group = "group"
}

public enum CSMMobilityPendingInvitationCapabilitiesItem: String, Codable, Sendable {
    case readVehicle = "readVehicle"
    case readCosts = "readCosts"
    case recordRide = "recordRide"
    case recordExpense = "recordExpense"
    case recordService = "recordService"
    case editVehicle = "editVehicle"
    case manageReminders = "manageReminders"
    case manageMembers = "manageMembers"
}

public struct CSMMobilityPendingInvitation: Codable, Sendable {
    public let invitationId: UUID
    public let entityType: CSMMobilityPendingInvitationEntityType
    public let entityId: UUID
    public let entityName: String
    public let inviterName: String
    public let expiresAt: String
    public let capabilities: [CSMMobilityPendingInvitationCapabilitiesItem]
    public init(invitationId: UUID, entityType: CSMMobilityPendingInvitationEntityType, entityId: UUID, entityName: String, inviterName: String, expiresAt: String, capabilities: [CSMMobilityPendingInvitationCapabilitiesItem]) {
        self.invitationId = invitationId
        self.entityType = entityType
        self.entityId = entityId
        self.entityName = entityName
        self.inviterName = inviterName
        self.expiresAt = expiresAt
        self.capabilities = capabilities
    }
}

public enum CSMMobilityPendingInvitationsContractVersion: String, Codable, Sendable {
    case cop_mobility_invitation_v1 = "cop-mobility-invitation-v1"
}

public struct CSMMobilityPendingInvitations: Codable, Sendable {
    public let contractVersion: CSMMobilityPendingInvitationsContractVersion
    public let items: [CSMMobilityPendingInvitation]
    public let serverTimestamp: String
    public init(contractVersion: CSMMobilityPendingInvitationsContractVersion, items: [CSMMobilityPendingInvitation], serverTimestamp: String) {
        self.contractVersion = contractVersion
        self.items = items
        self.serverTimestamp = serverTimestamp
    }
}

public struct CSMSharedVehicleCreationReceipt: Codable, Sendable {
    public let operationId: UUID
    public let confirmed: Bool
    public let vehicle: CSMSharedVehicle
    public init(operationId: UUID, confirmed: Bool, vehicle: CSMSharedVehicle) {
        self.operationId = operationId
        self.confirmed = confirmed
        self.vehicle = vehicle
    }
}

public struct CSMDispatchGroupCreationReceipt: Codable, Sendable {
    public let operationId: UUID
    public let confirmed: Bool
    public let group: CSMDispatchGroup
    public init(operationId: UUID, confirmed: Bool, group: CSMDispatchGroup) {
        self.operationId = operationId
        self.confirmed = confirmed
        self.group = group
    }
}

public struct CSMDispatchOwnedShares: Codable, Sendable {
    public let items: [CSMDispatchShare]
    public let serverTimestamp: String
    public init(items: [CSMDispatchShare], serverTimestamp: String) {
        self.items = items
        self.serverTimestamp = serverTimestamp
    }
}

public struct CSMDispatchStartCancel: Codable, Sendable {
    public let operationId: UUID
    public let startOperationId: UUID
    public init(operationId: UUID, startOperationId: UUID) { self.operationId = operationId; self.startOperationId = startOperationId }
}
public struct CSMDispatchStartCancelReceipt: Codable, Sendable {
    public let operationId: UUID
    public let startOperationId: UUID
    public let confirmed: Bool
    public let serverTimestamp: String
    public init(operationId: UUID, startOperationId: UUID, confirmed: Bool, serverTimestamp: String) { self.operationId = operationId; self.startOperationId = startOperationId; self.confirmed = confirmed; self.serverTimestamp = serverTimestamp }
}

public struct CSMDispatchParticipantOpen: Codable, Sendable {
    public let operationId: UUID
    public init(operationId: UUID) { self.operationId = operationId }
}
public struct CSMDispatchParticipantReceipt: Codable, Sendable {
    public let operationId: UUID
    public let confirmed: Bool
    public let groupId: UUID
    public let accountId: UUID
    public let conversationId: String
    public let roomId: String
    public init(operationId: UUID, confirmed: Bool, groupId: UUID, accountId: UUID, conversationId: String, roomId: String) { self.operationId = operationId; self.confirmed = confirmed; self.groupId = groupId; self.accountId = accountId; self.conversationId = conversationId; self.roomId = roomId }
}
