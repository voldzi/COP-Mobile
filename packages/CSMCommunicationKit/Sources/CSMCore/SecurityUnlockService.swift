import Foundation

#if os(iOS)
import LocalAuthentication
#endif

@MainActor
struct PreviewSecurityUnlock: SecurityUnlockManaging {
    func requireUnlock(reason: String) async throws {
    }
}

@MainActor
struct SystemSecurityUnlock: SecurityUnlockManaging {
    func requireUnlock(reason: String) async throws {
        #if os(iOS)
        let context = LAContext()
        context.localizedCancelTitle = "Zrusit"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            throw CSMServiceError.disabled("Biometricke odemknuti vyzadovane policy neni na zarizeni dostupne.")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(
                        throwing: error ?? CSMServiceError.disabled("Biometricke odemknuti nebylo potvrzeno.")
                    )
                }
            }
        }
        #else
        throw CSMServiceError.disabled("Biometricke odemknuti je dostupne pouze na iOS.")
        #endif
    }
}
