import Foundation

/// Resolves the APNs host that issued the token used by the currently installed app.
///
/// A locally installed Release build is commonly signed with an Apple Development
/// provisioning profile. Its tokens belong to the APNs sandbox even when the build
/// configuration is named Release. App Store builds do not contain an embedded
/// provisioning profile, so they intentionally fall back to the configured value.
public enum CSMAPNSEnvironmentResolver {
    public static var current: String {
        if let signedEnvironment = embeddedProvisioningEnvironment() {
            return normalized(signedEnvironment)
        }

        let configured =
            Bundle.main.object(forInfoDictionaryKey: "CSMAPNSEnvironment") as? String
        return normalized(configured)
    }

    static func environment(inProvisioningProfile data: Data) -> String? {
        guard
            let profile = String(data: data, encoding: .isoLatin1),
            let keyRange = profile.range(of: "<key>aps-environment</key>")
        else {
            return nil
        }

        let suffix = profile[keyRange.upperBound...]
        guard
            let valueStart = suffix.range(of: "<string>"),
            let valueEnd = suffix.range(
                of: "</string>",
                range: valueStart.upperBound..<suffix.endIndex
            )
        else {
            return nil
        }

        return String(suffix[valueStart.upperBound..<valueEnd.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func embeddedProvisioningEnvironment() -> String? {
        guard
            let profileURL = Bundle.main.url(
                forResource: "embedded",
                withExtension: "mobileprovision"
            ),
            let data = try? Data(contentsOf: profileURL)
        else {
            return nil
        }
        return environment(inProvisioningProfile: data)
    }

    private static func normalized(_ value: String?) -> String {
        switch value?.lowercased() {
        case "development", "sandbox":
            return "sandbox"
        default:
            return "production"
        }
    }
}
