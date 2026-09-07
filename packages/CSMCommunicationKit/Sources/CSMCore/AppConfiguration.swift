import Foundation

/// Runtime configuration for live services.
///
/// Secrets do not belong here. This type contains only public endpoints and
/// app metadata that can safely ship inside the app bundle or MDM config.
struct AppConfiguration: Sendable, Equatable {
    var copBaseURL: URL
    var messagingBaseURL: URL
    var appVersion: String
    var buildNumber: String
    var buildConfiguration: String
    var defaultHistorySeconds: Int
    var usePreviewServices: Bool
    var previewStartsSignedOut: Bool
    var oidcIssuer: URL
    var oidcClientId: String
    var oidcRedirectScheme: String
    var oidcScope: String
    var resetStateForUITesting: Bool

    static let preview = AppConfiguration(
        copBaseURL: URL(string: "https://cop.zeleznalady.cz")!,
        messagingBaseURL: URL(string: "https://msg.zeleznalady.cz")!,
        appVersion: "0.1.44",
        buildNumber: "45",
        buildConfiguration: "Debug",
        defaultHistorySeconds: 180,
        usePreviewServices: true,
        previewStartsSignedOut: false,
        oidcIssuer: URL(string: "https://auth.zeleznalady.cz/realms/cop")!,
        oidcClientId: "csm-mobile",
        oidcRedirectScheme: "csm",
        oidcScope: "openid profile offline_access",
        resetStateForUITesting: false
    )

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        fromInfoDictionary(bundle.infoDictionary ?? [:])
    }

    static func fromInfoDictionary(
        _ info: [String: Any],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppConfiguration {
        let baseURLString = info["CSMCopBaseURL"] as? String
        let messagingBaseURLString = info["CSMessagingBaseURL"] as? String
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        let buildConfiguration = (info["CSMBuildConfiguration"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let issuerString = info["CSMOIDCIssuer"] as? String
        let clientId = info["CSMOIDCClientId"] as? String
        let redirectScheme = info["CSMOIDCRedirectScheme"] as? String
        let scope = info["CSMOIDCScope"] as? String
        let resolvedBuildConfiguration: String
        if let buildConfiguration, !buildConfiguration.isEmpty {
            resolvedBuildConfiguration = buildConfiguration
        } else {
            resolvedBuildConfiguration = preview.buildConfiguration
        }
        let parsedPreview = boolValue(environment["CSM_FORCE_PREVIEW_SERVICES"]) ?? boolValue(info["CSMUsePreviewServices"])
        let usePreviewServices = resolvedBuildConfiguration.caseInsensitiveCompare("Release") == .orderedSame
            ? false
            : parsedPreview ?? true
        let previewStartsSignedOut = usePreviewServices &&
            (boolValue(environment["CSM_PREVIEW_SIGNED_OUT"]) ?? false)
        let resetStateForUITesting = usePreviewServices &&
            (boolValue(environment["CSM_RESET_UI_TEST_STATE"]) ?? false)

        return AppConfiguration(
            copBaseURL: URL(string: baseURLString ?? "https://cop.zeleznalady.cz") ?? preview.copBaseURL,
            messagingBaseURL: URL(string: messagingBaseURLString ?? preview.messagingBaseURL.absoluteString) ?? preview.messagingBaseURL,
            appVersion: version ?? preview.appVersion,
            buildNumber: build ?? preview.buildNumber,
            buildConfiguration: resolvedBuildConfiguration,
            defaultHistorySeconds: 180,
            usePreviewServices: usePreviewServices,
            previewStartsSignedOut: previewStartsSignedOut,
            oidcIssuer: URL(string: issuerString ?? preview.oidcIssuer.absoluteString) ?? preview.oidcIssuer,
            oidcClientId: clientId ?? preview.oidcClientId,
            oidcRedirectScheme: redirectScheme ?? preview.oidcRedirectScheme,
            oidcScope: scope ?? preview.oidcScope,
            resetStateForUITesting: resetStateForUITesting
        )
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        guard let value = value as? String else { return nil }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            return true
        case "0", "false", "no", "n", "off":
            return false
        default:
            return nil
        }
    }
}

enum CSMJSONCoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = makeFractionalISO8601Formatter().date(from: value) {
                return date
            }
            if let date = makeISO8601Formatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(value)")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(makeFractionalISO8601Formatter().string(from: date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeFractionalISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
