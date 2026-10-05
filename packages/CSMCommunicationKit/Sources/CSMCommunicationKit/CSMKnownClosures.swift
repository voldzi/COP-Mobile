import CryptoKit
import Foundation
import JavaScriptCore

/// Normalized request returned by COP. Kept losslessly as JSON, not guessed from route geometry.
public struct CSMRoutingQuery: Codable, Sendable {
    fileprivate let value: CSMJSONValue
    public init(from decoder: Decoder) throws { value = try CSMJSONValue(from: decoder) }
    public func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

public struct CSMKnownRoadClosures: Codable, Sendable {
    public struct Exclusion: Codable, Sendable {
        public let closureId: String
        public let sourceDirection: String
        public let enforcedDirection: String
        public let enforcementReason: String
        public let reviewedGeometryHash: String
    }
    public struct Engine: Codable, Sendable {
        public let provider: String
        public let version: String
        public let fallbackUsed: Bool
    }
    public let version: String
    public let state: String
    public let coverage: String
    public let revision: String
    public let observedAt: Date
    public let validUntil: Date
    public let appliedClosureCount: Int
    public let geometryHash: String
    public let requestHash: String
    public let exclusions: [Exclusion]
    public let routingDataset: CSMRoutingDataset
    public let engine: Engine
    public let limitations: [String]

    public func isCurrent(at now: Date = .now) -> Bool {
        observedAt <= now && validUntil > now && validUntil > observedAt &&
        validUntil.timeIntervalSince(observedAt) <= 600 && routingDataset.builtAt <= now &&
        now.timeIntervalSince(routingDataset.builtAt) < 864_000 &&
        validUntil <= routingDataset.builtAt.addingTimeInterval(864_000)
    }
    public var usesConservativeAvoidance: Bool {
        exclusions.contains { $0.sourceDirection == "unknown" }
    }
}

/// Exact ECMAScript number/string serialization used by SIM, including -0 and exponent boundaries.
/// Fixed local code only; response JSON is passed as data, never evaluated as JavaScript.
final class RoutingCanonicalJSON {
    private let context: JSContext
    init() throws {
        guard let context = JSContext() else { throw CSMDriverRoutingError.invalidKnownClosures }
        self.context = context
        context.evaluateScript("""
        function canonical(value) {
          if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
          if (value !== null && typeof value === 'object')
            return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
          return JSON.stringify(value);
        }
        function canonicalData(data) { return canonical(JSON.parse(data)); }
        """)
    }
    func string<T: Encodable>(_ value: T) throws -> String {
        let data = try CSMJSONCoding.encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8),
              let result = context.objectForKeyedSubscript("canonicalData")?.call(withArguments: [json]),
              context.exception == nil, let text = result.toString() else {
            throw CSMDriverRoutingError.invalidKnownClosures
        }
        return text
    }
    func hash<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: Data(try string(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension CSMDriverRouteResponse {
    /// Rechecks freshness only; the worker verification proof cannot be restored from decoded data.
    public func requireValidKnownClosures(at now: Date = .now) throws {
        try requireCurrentKnownClosures(at: now)
    }
    var hasKnownClosures: Bool { routes.contains { $0.knownClosures != nil } }

    /// Run once on a worker before any route filtering or outside-coverage fallback.
    func verifyingKnownClosures(for request: CSMDriverRouteRequest, at now: Date = .now) throws -> Self {
        guard hasKnownClosures else { return self }
        guard request.trip == nil, coverage?.state == "covered", !routes.isEmpty, routes.count <= 3, let query,
              let dataset = coverage?.routingDataset,
              case .object(var expected) = try CSMJSONValue.encodable(request) else {
            throw CSMDriverRoutingError.invalidKnownClosures
        }
        expected["via"] = expected["via"] ?? .array([])
        expected["avoid"] = expected["avoid"] ?? .array([])
        guard query.value == .object(expected) else { throw CSMDriverRoutingError.invalidKnownClosures }
        let canonical = try RoutingCanonicalJSON()
        let requestHash = try canonical.hash(query)
        var shared: String?
        var routeIDs = Set<String>()
        let hashPattern = "^[0-9a-f]{64}$"
        func validHash(_ value: String) -> Bool { value.range(of: hashPattern, options: .regularExpression) != nil }
        for route in routes {
            guard route.isNavigable, route.status == "ok", !route.routeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  routeIDs.insert(route.routeId).inserted, route.geometry.coordinates.allSatisfy({ $0.count == 2 }),
                  let evidence = route.knownClosures,
                  evidence.version == "sim-known-road-closures-v1", evidence.state == "applied", evidence.coverage == "incomplete",
                  evidence.isCurrent(at: now), validHash(evidence.revision), validHash(evidence.geometryHash), validHash(evidence.requestHash),
                  evidence.geometryHash == (try canonical.hash(route.geometry)), evidence.requestHash == requestHash,
                  evidence.routingDataset.version == dataset.version, evidence.routingDataset.builtAt == dataset.builtAt,
                  !dataset.version.isEmpty, evidence.engine.provider == "valhalla", !evidence.engine.fallbackUsed,
                  !evidence.engine.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  (0...128).contains(evidence.appliedClosureCount), evidence.exclusions.count == evidence.appliedClosureCount,
                  Set(evidence.exclusions.map(\.closureId)).count == evidence.exclusions.count,
                  (1...16).contains(evidence.limitations.count), evidence.limitations.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 1024 }),
                  evidence.exclusions.allSatisfy({ item in
                    !item.closureId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && item.closureId.count <= 256 &&
                    validHash(item.reviewedGeometryHash) && item.enforcedDirection == "both" &&
                    ((item.sourceDirection == "both" && item.enforcementReason == "source_both_direction") ||
                     (item.sourceDirection == "unknown" && item.enforcementReason == "conservative_whole_structure_avoidance"))
                  }), case .object(var common) = try CSMJSONValue.encodable(evidence) else {
                throw CSMDriverRoutingError.invalidKnownClosures
            }
            common.removeValue(forKey: "geometryHash")
            let identity = try canonical.string(CSMJSONValue.object(common))
            guard shared == nil || shared == identity else { throw CSMDriverRoutingError.invalidKnownClosures }
            shared = identity
        }
        var verified = self
        verified.knownClosuresVerified = true
        return verified
    }

    func requireCurrentKnownClosures(at now: Date = .now) throws {
        guard !hasKnownClosures || (knownClosuresVerified && routes.allSatisfy({ $0.knownClosures?.isCurrent(at: now) == true })) else {
            throw CSMDriverRoutingError.invalidKnownClosures
        }
    }
}
