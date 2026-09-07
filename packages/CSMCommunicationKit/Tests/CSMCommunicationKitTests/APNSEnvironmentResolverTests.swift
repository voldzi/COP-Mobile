import Foundation
import Testing
@testable import CSMCommunicationKit

@Suite("APNs environment resolver")
struct APNSEnvironmentResolverTests {
    @Test("reads development entitlement from an embedded provisioning profile")
    func readsDevelopmentEnvironment() {
        let profile = """
        binary-prefix
        <plist><dict>
        <key>Entitlements</key><dict>
        <key>aps-environment</key>
        <string>development</string>
        </dict></dict></plist>
        binary-suffix
        """

        #expect(
            CSMAPNSEnvironmentResolver.environment(
                inProvisioningProfile: Data(profile.utf8)
            ) == "development"
        )
    }

    @Test("returns nil when the profile has no APNs entitlement")
    func rejectsMissingEnvironment() {
        let profile = Data("<plist><dict></dict></plist>".utf8)

        #expect(
            CSMAPNSEnvironmentResolver.environment(
                inProvisioningProfile: profile
            ) == nil
        )
    }
}
