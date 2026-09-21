import Foundation

/// A successful snapshot of available observations, never an assertion that a road is safe.
public struct CSMDriverReportFeed: Sendable {
    public var reports: [CSMNearbyDriverReport]
    public var fetchedAt: Date
    public var mayBeIncomplete: Bool
}

struct DriverReportQuery: Sendable {
    static let limit = 500
    var west: Double
    var south: Double
    var east: Double
    var north: Double

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "bbox", value: "\(west),\(south),\(east),\(north)"),
            URLQueryItem(name: "categories", value: CSMDriverReportCategory.allCases.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "statuses", value: "submitted,published"),
            URLQueryItem(name: "includeExpired", value: "false"),
            URLQueryItem(name: "limit", value: String(Self.limit))
        ]
    }

    static func nearby(latitude: Double, longitude: Double, radiusMeters: Double) throws -> [Self] {
        guard latitude.isFinite, longitude.isFinite, radiusMeters.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude),
              (1...50_000).contains(radiusMeters) else { throw CSMDriverReportError.invalidLocation }
        let angular = radiusMeters / 6_371_000
        let latRadians = latitude * .pi / 180
        let south = max(-90, latitude - angular * 180 / .pi)
        let north = min(90, latitude + angular * 180 / .pi)
        if south == -90 || north == 90 {
            return [Self(west: -180, south: south, east: 180, north: north)]
        }
        let delta = asin(min(1, sin(angular) / cos(latRadians))) * 180 / .pi
        let west = longitude - delta
        let east = longitude + delta
        if west < -180 {
            return [Self(west: west + 360, south: south, east: 180, north: north),
                    Self(west: -180, south: south, east: east, north: north)]
        }
        if east > 180 {
            return [Self(west: west, south: south, east: 180, north: north),
                    Self(west: -180, south: south, east: east - 360, north: north)]
        }
        return [Self(west: west, south: south, east: east, north: north)]
    }
}

enum DriverReportFeedProjector {
    static func project(
        _ items: [CommunityReport], latitude: Double, longitude: Double,
        radiusMeters: Double, now: Date, mayBeIncomplete: Bool
    ) -> CSMDriverReportFeed {
        var seen = Set<String>()
        var grouped: [String: CSMNearbyDriverReport] = [:]
        for report in items.sorted(by: { $0.observedAt > $1.observedAt }) {
            guard let category = CSMDriverReportCategory(rawValue: report.category.rawValue),
                  ["submitted", "published"].contains(report.status),
                  report.validUntil.map({ $0 > now }) ?? true,
                  report.observedAt <= now.addingTimeInterval(300),
                  (-90...90).contains(report.location.lat), (-180...180).contains(report.location.lon)
            else { continue }
            let distance = distance(latitude, longitude, report.location.lat, report.location.lon)
            guard distance <= radiusMeters, seen.insert(report.reportId).inserted else { continue }
            let clusterKey = report.roadEnrichment?.state == "matched" ? report.roadEnrichment?.clusterId : nil
            let key = clusterKey.map { "cluster:\($0)" } ?? "report:\(report.reportId)"
            if var existing = grouped[key] {
                existing.relatedReportCount += 1
                grouped[key] = existing
                continue
            }
            grouped[key] = CSMNearbyDriverReport(
                id: report.reportId, category: category, title: report.title, detail: report.description,
                latitude: report.location.lat, longitude: report.location.lon, distanceMeters: distance,
                observedAt: report.observedAt, validUntil: report.validUntil,
                confidence: CSMDriverReportConfidence(rawValue: report.confidenceSummary?.level ?? "low") ?? .low,
                confidencePercent: min(100, max(0, report.confidenceSummary?.scorePercent ?? 0)),
                stillThereCount: report.confirmations.stillThereCount,
                notThereCount: report.confirmations.notThereCount,
                currentConfirmation: report.confirmations.currentActorValue.flatMap { CSMDriverReportConfirmation(rawValue: $0.rawValue) }
            )
        }
        let reports = grouped.values.sorted { $0.distanceMeters == $1.distanceMeters ? $0.id < $1.id : $0.distanceMeters < $1.distanceMeters }
        return CSMDriverReportFeed(reports: reports, fetchedAt: now, mayBeIncomplete: mayBeIncomplete)
    }

    private static func distance(_ lat: Double, _ lon: Double, _ otherLat: Double, _ otherLon: Double) -> Double {
        let dLat = (otherLat - lat) * .pi / 180
        let dLon = (otherLon - lon) * .pi / 180
        let a = min(1, max(0, pow(sin(dLat / 2), 2) + cos(lat * .pi / 180) * cos(otherLat * .pi / 180) * pow(sin(dLon / 2), 2)))
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
