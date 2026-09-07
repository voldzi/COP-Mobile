import Foundation

#if os(iOS)
import UIKit
#endif

enum DeviceRegistrationFactory {
    @MainActor
    static func make(configuration: AppConfiguration) -> MobileDeviceRegistration {
        #if os(iOS)
        let device = UIDevice.current
        let platform = device.userInterfaceIdiom == .pad ? "ipados" : "ios"
        let deviceId = device.identifierForVendor?.uuidString ?? UUID().uuidString
        return MobileDeviceRegistration(
            deviceId: "ios-\(deviceId)",
            platform: platform,
            appVersion: configuration.appVersion,
            buildNumber: configuration.buildNumber,
            osVersion: device.systemVersion,
            deviceModel: device.model,
            capabilities: [
                "offlineSnapshot",
                "sseStream",
                "communityOutbox",
                "matrixBootstrap",
                "apns",
                "devicePosture",
                "watchConnectivity",
                "localAI",
                "crisisRelay",
                "crisisRelayGateway"
            ]
        )
        #else
        return MobileDeviceRegistration(
            deviceId: "watch-\(UUID().uuidString)",
            platform: "watchos",
            appVersion: configuration.appVersion,
            buildNumber: configuration.buildNumber,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: "watchOS",
            capabilities: ["watchAlerts", "watchConnectivity"]
        )
        #endif
    }
}
