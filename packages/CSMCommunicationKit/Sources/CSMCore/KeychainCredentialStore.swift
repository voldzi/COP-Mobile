import Foundation
import Security

struct TokenPair: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var subjectId: String?

    var isAccessTokenFresh: Bool {
        expiresAt.timeIntervalSinceNow > 60
    }
}

protocol TokenCredentialStoring: Actor {
    func saveTokens(_ tokens: TokenPair, account: String) throws
    func loadTokens(account: String) throws -> TokenPair?
    func delete(account: String) throws
}

extension TokenCredentialStoring {
    func saveTokens(_ tokens: TokenPair) throws {
        try saveTokens(tokens, account: "oidc")
    }

    func loadTokens() throws -> TokenPair? {
        try loadTokens(account: "oidc")
    }
}

actor KeychainCredentialStore: TokenCredentialStoring {
    private let service: String
    private let accessGroup: String?

    init(service: String = "cz.zeleznalady.csm.messenger.credentials", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func saveTokens(_ tokens: TokenPair, account: String = "oidc") throws {
        let data = try CSMJSONCoding.encoder.encode(tokens)
        try save(data, account: account)
    }

    func loadTokens(account: String = "oidc") throws -> TokenPair? {
        guard let data = try load(account: account) else { return nil }
        return try CSMJSONCoding.decoder.decode(TokenPair.self, from: data)
    }

    func saveSymmetricKey(_ key: Data, account: String) throws {
        try save(key, account: "symmetric-key.\(account)")
    }

    func loadSymmetricKey(account: String) throws -> Data? {
        try load(account: "symmetric-key.\(account)")
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CSMServiceError.unavailable("Keychain delete failed with status \(status).")
        }
    }

    private func save(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data

        // Tokens and encryption keys are available only while the device is
        // unlocked and do not migrate to a different physical device backup.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                baseQuery(account: account) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw CSMServiceError.unavailable("Keychain update failed with status \(updateStatus).")
            }
            return
        }

        guard addStatus == errSecSuccess else {
            throw CSMServiceError.unavailable("Keychain save failed with status \(addStatus).")
        }
    }

    private func load(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CSMServiceError.unavailable("Keychain read failed with status \(status).")
        }
        return data
    }

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
