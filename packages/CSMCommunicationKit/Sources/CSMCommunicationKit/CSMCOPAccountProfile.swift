import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Current verified COP identity and canonical COP avatar. Contains no credentials.
public struct CSMCOPAccountProfile: Codable, Equatable, Sendable {
    public let contractVersion: String
    public let subjectId: String
    public let issuer: String
    public let displayName: String
    public let email: String?
    public let emailVerified: Bool
    public let avatarDataUrl: String?
    public let revision: String
    public let updatedAt: String?
    public let serverTimestamp: String

    public var avatarData: Data? {
        guard let avatarDataUrl, let comma = avatarDataUrl.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(avatarDataUrl[avatarDataUrl.index(after: comma)...]))
    }
}

public extension CSMCommunicationRuntime {
    func copAccountProfile(expectedScope: String) async throws -> CSMCOPAccountProfile {
        let profile: CSMCOPAccountProfile = try await mobilityRequest(path: "/api/v1/me/profile", method: "GET", body: nil, query: [], expectedScope: expectedScope)
        try validateCurrentCOPProfile(profile)
        return profile
    }

    /// Only call after the person explicitly chooses to update their own COP avatar.
    func copAccountAvatarSave(imageData: Data, expectedRevision: String, expectedScope: String) async throws -> CSMCOPAccountProfile {
        guard mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        let generation = copSessionGeneration()
        try Task.checkCancellation()
        let data = try await Task.detached(priority: .userInitiated) { try COPAvatarImage.prepare(imageData) }.value
        try Task.checkCancellation()
        guard generation == copSessionGeneration(), mobilitySessionScope() == expectedScope else { throw CSMCOPSessionError(.accountChanged) }
        return try await updateCOPAvatar(dataUrl: "data:image/jpeg;base64," + data.base64EncodedString(), expectedRevision: expectedRevision, expectedScope: expectedScope)
    }

    func copAccountAvatarRemove(expectedRevision: String, expectedScope: String) async throws -> CSMCOPAccountProfile {
        try await updateCOPAvatar(dataUrl: nil, expectedRevision: expectedRevision, expectedScope: expectedScope)
    }

    private func updateCOPAvatar(dataUrl: String?, expectedRevision: String, expectedScope: String) async throws -> CSMCOPAccountProfile {
        guard COPProfileBoundary.validRevision(expectedRevision) else { throw CSMCOPSessionError(.invalidResponse) }
        let body = try JSONSerialization.data(withJSONObject: ["avatarDataUrl": dataUrl as Any? ?? NSNull()])
        let profile: CSMCOPAccountProfile = try await mobilityRequest(path: "/api/v1/me/profile/avatar", method: "PATCH", body: body, query: [], expectedScope: expectedScope, ifMatch: "\"" + expectedRevision + "\"")
        try validateCurrentCOPProfile(profile)
        return profile
    }

    private func validateCurrentCOPProfile(_ profile: CSMCOPAccountProfile) throws {
        guard let actor = model.actor, COPProfileBoundary.matches(profile, issuer: AppConfiguration.fromBundle().oidcIssuer.absoluteString, subject: actor.subjectId) else {
            throw CSMCOPSessionError(.invalidResponse)
        }
    }
}

enum COPProfileBoundary {
    static func validRevision(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func matches(_ profile: CSMCOPAccountProfile, issuer: String, subject: String) -> Bool {
        guard profile.contractVersion == "cop-account-profile-v1", profile.issuer == issuer, profile.subjectId == subject,
              validRevision(profile.revision), profile.displayName.utf8.count <= 4096,
              !profile.emailVerified || profile.email != nil else { return false }
        guard let avatar = profile.avatarDataUrl else { return true }
        guard avatar.utf8.count <= 250000, ["data:image/png;base64,", "data:image/jpeg;base64,", "data:image/webp;base64,"].contains(where: { avatar.hasPrefix($0) }),
              let data = profile.avatarData, !data.isEmpty, data.count <= 187500 else { return false }
        return true
    }
}

enum COPAvatarImage {
    static func prepare(_ data: Data) throws -> Data {
        let fail = CSMServiceError.invalidState("Vyberte platnou fotografii do 10 MB.")
        guard !data.isEmpty, data.count <= 10485760,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 50000000 / height,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: false] as CFDictionary) else { throw fail }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw fail }
        // A fresh raster is encoded, without copying any original metadata dictionaries.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 180000 else { throw fail }
        return output as Data
    }
}
