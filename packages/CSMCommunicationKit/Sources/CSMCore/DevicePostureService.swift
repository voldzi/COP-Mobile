import Foundation

#if os(iOS)
import LocalAuthentication
import UIKit
#endif

@MainActor
protocol DevicePostureProviding: AnyObject {
    func currentPosture(policy: MobileNativePolicy?) -> MobileDevicePosture
    func currentManagedAppPolicy(policy: MobileNativePolicy?) -> MobileManagedAppPolicy
}

@MainActor
final class SystemDevicePostureProvider: DevicePostureProviding {
    static let shared = SystemDevicePostureProvider()

    private init() {}

    func currentPosture(policy: MobileNativePolicy?) -> MobileDevicePosture {
        #if os(iOS)
        let managedPolicy = currentManagedAppPolicy(policy: policy)
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        return MobileDevicePosture(
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            managedAppConfigurationPresent: managedPolicy.configurationPresent,
            managedDeviceRequired: managedPolicy.requiresManagedDevice(serverPolicy: policy),
            remoteWipeRequested: managedPolicy.remoteWipeRequested,
            biometryType: Self.biometryTypeName(context.biometryType),
            evaluatedAt: .now
        )
        #else
        return MobileDevicePosture(
            protectedDataAvailable: true,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            managedAppConfigurationPresent: false,
            managedDeviceRequired: policy?.requireManagedDevice ?? false,
            remoteWipeRequested: false,
            biometryType: "unavailable",
            evaluatedAt: .now
        )
        #endif
    }

    func currentManagedAppPolicy(policy: MobileNativePolicy?) -> MobileManagedAppPolicy {
        #if os(iOS)
        MobileManagedAppPolicy.fromManagedConfiguration(Self.managedConfiguration())
        #else
        .unmanaged
        #endif
    }

    #if os(iOS)
    private static func managedConfiguration() -> [String: Any]? {
        UserDefaults.standard.dictionary(forKey: "com.apple.configuration.managed")
    }

    private static func biometryTypeName(_ type: LABiometryType) -> String {
        switch type {
        case .none:
            return "none"
        case .touchID:
            return "touchID"
        case .faceID:
            return "faceID"
        case .opticID:
            return "opticID"
        @unknown default:
            return "unknown"
        }
    }
    #endif
}
