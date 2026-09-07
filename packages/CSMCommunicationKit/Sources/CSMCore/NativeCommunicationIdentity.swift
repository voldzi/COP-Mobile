import Foundation

enum NativeCommunicationAccessState: Equatable, Sendable {
    case checking
    case ready
    case deviceUnlockRequired
    case signInRequired
    case accountMismatch
    case unavailable
}

enum NativeCommunicationIdentityPolicy {
    static func resolve(
        authState: AuthState,
        actorSubjectID: String?,
        expectedSubjectID: String?,
        isLoading: Bool
    ) -> NativeCommunicationAccessState {
        if isLoading || authState == .checking || authState == .signingIn {
            return .checking
        }
        if authState == .locked {
            return .deviceUnlockRequired
        }
        guard authState == .signedIn else {
            return .signInRequired
        }
        guard let actorSubjectID = normalized(actorSubjectID) else {
            return .unavailable
        }
        guard let expectedSubjectID = normalized(expectedSubjectID) else {
            return .ready
        }
        return actorSubjectID == expectedSubjectID
            ? .ready
            : .accountMismatch
    }

    static func normalized(_ subjectID: String?) -> String? {
        let value = subjectID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}
