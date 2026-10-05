import Foundation

/// Minimize the allowed payload surface; COP remains the authoritative validator.
enum CSMDriverMeasurementBatchPolicy {
    static func matchesSession(current: String?, expected: String) -> Bool {
        !expected.isEmpty && current == expected
    }
    static func accepts(_ data: Data) -> Bool {
        guard data.count <= 1_048_576,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(json.keys).isSubset(of: ["contractVersion", "batchId", "contributorDay", "vehicleClass", "points", "eta"]),
              json["contractVersion"] as? String == "cop-driver-measurements-v1",
              json["vehicleClass"] as? String == "passenger_car",
              let id = json["batchId"] as? String, UUID(uuidString: id) != nil,
              let day = json["contributorDay"] as? String,
              day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let points = json["points"] as? [[String: Any]], (3...120).contains(points.count) else { return false }
        let keys: Set<String> = ["sampleId", "observedAt", "lat", "lon", "horizontalAccuracyM", "speedMps",
            "speedAccuracyMps", "headingDeg", "headingAccuracyDeg", "positionSource", "motion", "reducedAccuracy"]
        guard points.allSatisfy({ Set($0.keys) == keys && $0["positionSource"] as? String == "gps" }) else { return false }
        if let eta = json["eta"] {
            guard let eta = eta as? [String: Any], Set(eta.keys) == ["observationId", "routingDataset",
                "predictedDurationSeconds", "actualDurationSeconds", "plannedDistanceM", "actualDistanceM",
                "personalStopSeconds", "estimatedSeconds", "offRoute", "completedAt"] else { return false }
        }
        return true
    }
}
