import Foundation

public enum CSMDriverReportCategory: String, CaseIterable, Identifiable, Sendable {
    case dangerousWeather = "dangerous_weather"
    case stoppedVehicle = "stopped_vehicle"
    case trafficAccident = "traffic_accident"
    case trafficCongestion = "traffic_congestion"
    case roadBlockage = "road_blockage"
    case hazard

    public var id: String { rawValue }
}

public struct CSMDriverReportDraft: Sendable {
    public var id: UUID
    public var category: CSMDriverReportCategory
    public var latitude: Double
    public var longitude: Double
    public var horizontalAccuracyMeters: Double?
    public var observedAt: Date
    public var travelDirectionDegrees: Double?
    public var speedMetersPerSecond: Double?
    public var roadName: String?
    public var roadReference: String?
    public var title: String?
    public var detail: String
    public var appVersion: String?

    public init(
        id: UUID = UUID(),
        category: CSMDriverReportCategory,
        latitude: Double,
        longitude: Double,
        horizontalAccuracyMeters: Double? = nil,
        observedAt: Date = .now,
        travelDirectionDegrees: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        roadName: String? = nil,
        roadReference: String? = nil,
        title: String? = nil,
        detail: String = "",
        appVersion: String? = nil
    ) {
        self.id = id
        self.category = category
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.observedAt = observedAt
        self.travelDirectionDegrees = travelDirectionDegrees
        self.speedMetersPerSecond = speedMetersPerSecond
        self.roadName = roadName
        self.roadReference = roadReference
        self.title = title
        self.detail = detail
        self.appVersion = appVersion
    }
}

public enum CSMDriverReportConfirmation: String, Sendable {
    case stillThere = "still_there"
    case notThere = "not_there"
}

public enum CSMDriverReportConfidence: String, Sendable {
    case low
    case medium
    case high
}

public struct CSMNearbyDriverReport: Identifiable, Sendable {
    public var id: String
    public var category: CSMDriverReportCategory
    public var title: String
    public var detail: String?
    public var latitude: Double
    public var longitude: Double
    public var distanceMeters: Double
    public var observedAt: Date
    public var validUntil: Date?
    public var confidence: CSMDriverReportConfidence
    public var confidencePercent: Int
    public var stillThereCount: Int
    public var notThereCount: Int
    public var currentConfirmation: CSMDriverReportConfirmation?

    public init(
        id: String,
        category: CSMDriverReportCategory,
        title: String,
        detail: String?,
        latitude: Double,
        longitude: Double,
        distanceMeters: Double,
        observedAt: Date,
        validUntil: Date?,
        confidence: CSMDriverReportConfidence,
        confidencePercent: Int,
        stillThereCount: Int,
        notThereCount: Int,
        currentConfirmation: CSMDriverReportConfirmation?
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.latitude = latitude
        self.longitude = longitude
        self.distanceMeters = distanceMeters
        self.observedAt = observedAt
        self.validUntil = validUntil
        self.confidence = confidence
        self.confidencePercent = confidencePercent
        self.stillThereCount = stillThereCount
        self.notThereCount = notThereCount
        self.currentConfirmation = currentConfirmation
    }
}

public enum CSMDriverReportDeliveryState: String, Sendable {
    case queued
    case submitted
}

public struct CSMDriverReportReceipt: Sendable {
    public var reportID: String
    public var state: CSMDriverReportDeliveryState
    public var recordedAt: Date

    public init(reportID: String, state: CSMDriverReportDeliveryState, recordedAt: Date) {
        self.reportID = reportID
        self.state = state
        self.recordedAt = recordedAt
    }
}

public enum CSMDriverReportError: LocalizedError, Sendable {
    case invalidLocation
    case invalidRoadContext

    public var errorDescription: String? {
        switch self {
        case .invalidLocation:
            "Hlášení nemá platnou polohu."
        case .invalidRoadContext:
            "Směr nebo rychlost hlášení nejsou platné."
        }
    }
}

public extension CSMCommunicationRuntime {
    func nearbyDriverReports(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 10_000
    ) async throws -> [CSMNearbyDriverReport] {
        try await nearbyDriverReportFeed(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters).reports
    }

    func nearbyDriverReportFeed(
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 10_000
    ) async throws -> CSMDriverReportFeed {
        let queries = try DriverReportQuery.nearby(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
        await startIfNeeded()
        var items: [CommunityReport] = []
        var mayBeIncomplete = false
        for query in queries {
            try Task.checkCancellation()
            let batch = try await driverReportService.reports(query: query)
            mayBeIncomplete = mayBeIncomplete || batch.count >= DriverReportQuery.limit
            items.append(contentsOf: batch)
        }
        try Task.checkCancellation()
        return DriverReportFeedProjector.project(
            items, latitude: latitude, longitude: longitude, radiusMeters: radiusMeters,
            now: .now, mayBeIncomplete: mayBeIncomplete
        )
    }

    @discardableResult
    func confirmDriverReport(
        id: String,
        confirmation: CSMDriverReportConfirmation
    ) async throws -> CSMNearbyDriverReport? {
        await startIfNeeded()
        let value = CommunityReportConfirmationValue(rawValue: confirmation.rawValue) ?? .stillThere
        let report = try await driverReportService.confirm(reportId: id, value: value)
        guard let category = CSMDriverReportCategory(rawValue: report.category.rawValue) else { return nil }
        let confidence = CSMDriverReportConfidence(rawValue: report.confidenceSummary?.level ?? "low") ?? .low
        return CSMNearbyDriverReport(
            id: report.reportId,
            category: category,
            title: report.title,
            detail: report.description,
            latitude: report.location.lat,
            longitude: report.location.lon,
            distanceMeters: 0,
            observedAt: report.observedAt,
            validUntil: report.validUntil,
            confidence: confidence,
            confidencePercent: report.confidenceSummary?.scorePercent ?? 0,
            stillThereCount: report.confirmations.stillThereCount,
            notThereCount: report.confirmations.notThereCount,
            currentConfirmation: report.confirmations.currentActorValue.flatMap {
                CSMDriverReportConfirmation(rawValue: $0.rawValue)
            }
        )
    }

    func submitDriverReport(_ draft: CSMDriverReportDraft) async throws -> CSMDriverReportReceipt {
        guard (-90 ... 90).contains(draft.latitude), (-180 ... 180).contains(draft.longitude) else {
            throw CSMDriverReportError.invalidLocation
        }
        if let heading = draft.travelDirectionDegrees, !(0 ..< 360).contains(heading) {
            throw CSMDriverReportError.invalidRoadContext
        }
        if let speed = draft.speedMetersPerSecond, !(0 ... 100).contains(speed) {
            throw CSMDriverReportError.invalidRoadContext
        }

        await startIfNeeded()
        let report = CommunityReportDraft(
            id: draft.id.uuidString.lowercased(),
            category: ReportCategory(rawValue: draft.category.rawValue) ?? .hazard,
            title: draft.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? Self.defaultDriverReportTitle(draft.category),
            description: draft.detail.trimmingCharacters(in: .whitespacesAndNewlines),
            location: GeoPoint(
                lat: draft.latitude,
                lon: draft.longitude,
                accuracyM: draft.horizontalAccuracyMeters,
                source: "device"
            ),
            severity: Self.defaultDriverReportSeverity(draft.category),
            groupId: nil,
            groupName: "",
            createdAt: draft.observedAt,
            captureContext: CommunityReportCaptureContext(
                client: "jizda",
                platform: "ios",
                appVersion: draft.appVersion,
                offlineQueuedAt: .now
            ),
            roadContext: CommunityReportRoadContext(
                travelDirectionDeg: draft.travelDirectionDegrees,
                speedMps: draft.speedMetersPerSecond,
                roadName: draft.roadName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                roadRef: draft.roadReference?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                capturedAt: draft.observedAt
            )
        )
        let submission = try await model.submitCommunityReport(report)
        return CSMDriverReportReceipt(
            reportID: submission?.reportId ?? report.id,
            state: submission == nil ? .queued : .submitted,
            recordedAt: submission?.submittedAt ?? .now
        )
    }

    private static func defaultDriverReportTitle(_ category: CSMDriverReportCategory) -> String {
        switch category {
        case .dangerousWeather: "Nebezpečné počasí"
        case .stoppedVehicle: "Stojící vozidlo"
        case .trafficAccident: "Dopravní nehoda"
        case .trafficCongestion: "Dopravní kolona"
        case .roadBlockage: "Neprůjezdná komunikace"
        case .hazard: "Nebezpečí na trase"
        }
    }

    private static func defaultDriverReportSeverity(_ category: CSMDriverReportCategory) -> AlertSeverity {
        switch category {
        case .trafficCongestion:
            .info
        case .dangerousWeather, .stoppedVehicle, .trafficAccident, .roadBlockage, .hazard:
            .warning
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
