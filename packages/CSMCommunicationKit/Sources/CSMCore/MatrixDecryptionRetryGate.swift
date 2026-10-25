import Foundation

#if canImport(MatrixRustSDK) && !os(watchOS)
import MatrixRustSDK

/// A read/refresh may retry locally available keys. There is no timer, network
/// polling, trust change or store reset. Verification failures need user action.
struct MatrixDecryptionRetryGate {
    private var lastAttemptByRoom: [String: Date] = [:]

    mutating func sessionsToRetry(_ messages: [EncryptedMessage], in roomID: String, now: Date) -> [String] {
        guard !roomID.isEmpty,
              lastAttemptByRoom[roomID].map({ now.timeIntervalSince($0) >= 30 }) ?? true else { return [] }
        let sessions = Set(messages.compactMap { message -> String? in
            guard case .megolmV1AesSha2(let sessionID, let cause) = message,
                  !sessionID.isEmpty else { return nil }
            switch cause {
            case .unknown, .unknownDevice, .withheldBySender: return sessionID
            default: return nil
            }
        }).sorted()
        guard !sessions.isEmpty else { return [] }
        if lastAttemptByRoom.count >= 64,
           let oldest = lastAttemptByRoom.min(by: { $0.value < $1.value })?.key {
            lastAttemptByRoom.removeValue(forKey: oldest)
        }
        lastAttemptByRoom[roomID] = now
        return Array(sessions.prefix(50))
    }
}
#endif
