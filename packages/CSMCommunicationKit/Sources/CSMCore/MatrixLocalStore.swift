import CoreFoundation
import CryptoKit
import Foundation
import SQLite3

public enum CSMChatLocalStoreFailure: String, Codable, Equatable, Sendable {
    case missingKey, invalidKey, cipherMismatch, deviceLocked, keychainUnavailable, storeUnavailable
    case deviceIdentityMismatch, existingDeviceKeys, recoveryRequired, recoveryUnavailable
}

struct MatrixLocalStoreError: LocalizedError, Equatable, Sendable {
    let failure: CSMChatLocalStoreFailure
    var keychainStatus: Int32? = nil
    var errorDescription: String? {
        switch failure {
        case .missingKey, .invalidKey, .cipherMismatch:
            "Šifrované úložiště chatu nelze odemknout. Původní data a neodeslané zprávy zůstávají zachované. Použijte výslovnou obnovu chatu."
        case .deviceLocked:
            "Odemkněte telefon a zkuste chat znovu. Šifrovací klíč nebyl změněn."
        case .keychainUnavailable:
            "Bezpečné úložiště klíčů není dostupné. Chat nebyl resetován; zkuste to později."
        case .storeUnavailable:
            "Místní úložiště chatu nyní nelze bezpečně přečíst. Nebyla změněna data ani identita zařízení; zkuste to později."
        case .deviceIdentityMismatch, .existingDeviceKeys:
            "Identitu šifrovaného zařízení nelze bezpečně obnovit. Použijte výslovnou obnovu chatu; původní data zůstávají zachovaná."
        case .recoveryRequired:
            "Je potřeba potvrdit obnovu chatu s novým zařízením. Automatický reset šifrování není povolen."
        case .recoveryUnavailable:
            "Obnovu chatu nelze dokončit bez ověřené zálohy. Původní data a neodeslané zprávy zůstávají zachované."
        }
    }
    var permitsRecovery: Bool {
        [.missingKey, .invalidKey, .cipherMismatch, .deviceIdentityMismatch, .existingDeviceKeys, .recoveryRequired].contains(failure)
    }
    static func classifyBuilderFailure(_ error: any Error) -> (any Error) {
        let detail = String(describing: error).lowercased()
        if detail.contains("failed to initialize the store cipher") ||
            (detail.contains("aead") && detail.contains("encrypting or decrypting")) {
            return MatrixLocalStoreError(failure: .cipherMismatch)
        }
        return error
    }
}

protocol MatrixStoreKeyAccessing: Actor {
    func loadOrCreateMatrixStoreKey(account: String, allowCreation: Bool) throws -> Data
}

/// One process-wide queue per store, plus a separate queue per client instance.
/// A cancelled waiter still waits for its predecessor before releasing its slot.
actor MatrixInitializationGate {
    static let shared = MatrixInitializationGate()
    private struct Tail { let id: UUID; let completion: Task<Void, Never> }
    private var tails: [String: Tail] = [:]
    func withExclusive<T: Sendable>(
        key: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let predecessor = tails[key]?.completion
        let id = UUID()
        let work = Task {
            await predecessor?.value
            try Task.checkCancellation()
            return try await operation()
        }
        let completion = Task { _ = try? await work.value }
        tails[key] = Tail(id: id, completion: completion)
        defer { if tails[key]?.id == id { tails[key] = nil } }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: { work.cancel() }
    }
}

struct MatrixLocalStoreInspection: Sendable {
    let root: URL
    let hasStoredData: Bool
    let hasCryptoDatabase: Bool
}
struct MatrixLocalStorePreparation: Sendable {
    let dataPath: String
    let cachePath: String
    let passphrase: String
}

struct MatrixLocalStoreFiles: Sendable {
    let rootDirectory: URL
    func inspect(subject: String) throws -> MatrixLocalStoreInspection {
        let root = rootDirectory.appendingPathComponent(Self.hash(subject), isDirectory: true)
        for directory in [rootDirectory, root] where FileManager.default.fileExists(atPath: directory.path) {
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw MatrixLocalStoreError(failure: .recoveryRequired)
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return MatrixLocalStoreInspection(root: root, hasStoredData: false, hasCryptoDatabase: false)
        }
        guard isDirectory.boolValue else { throw MatrixLocalStoreError(failure: .recoveryRequired) }
        try Self.excludeFromBackup(root)
        // Any existing regular file is protected state, even a zero-length DB.
        // An unreadable directory is never interpreted as an empty/new store.
        func containsFile(_ directory: URL) throws -> Bool {
            var found = false
            for entry in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { throw MatrixLocalStoreError(failure: .recoveryRequired) }
                if values.isDirectory == true {
                    if try containsFile(entry) { found = true }
                } else { found = true }
            }
            return found
        }
        let hasStoredData = try containsFile(root)
        let database = root.appendingPathComponent("data/matrix-sdk-crypto.sqlite3")
        var hasCryptoDatabase = false
        if FileManager.default.fileExists(atPath: database.path) {
            let attributes = try database.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard attributes.isSymbolicLink != true else { throw MatrixLocalStoreError(failure: .recoveryRequired) }
            if attributes.isRegularFile == true, (attributes.fileSize ?? 0) >= 512 {
                let file = try FileHandle(forReadingFrom: database)
                defer { try? file.close() }
                hasCryptoDatabase = try file.read(upToCount: 16) == Data("SQLite format 3\0".utf8) && (try Self.containsPersistedCryptoAccount(database))
            }
        }
        return MatrixLocalStoreInspection(root: root, hasStoredData: hasStoredData, hasCryptoDatabase: hasCryptoDatabase)
    }
    func prepare(
        inspection: MatrixLocalStoreInspection,
        subject: String,
        keys: any MatrixStoreKeyAccessing,
        fixedPassphrase: String? = nil
    ) async throws -> MatrixLocalStorePreparation {
        let current = try inspect(subject: subject)
        guard current.root == inspection.root,
              current.hasStoredData == inspection.hasStoredData,
              current.hasCryptoDatabase == inspection.hasCryptoDatabase else {
            throw MatrixLocalStoreError(failure: .recoveryRequired)
        }
        let passphrase: String
        if let fixedPassphrase {
            guard !fixedPassphrase.isEmpty else { throw MatrixLocalStoreError(failure: .invalidKey) }
            passphrase = fixedPassphrase
        } else {
            let data = try await keys.loadOrCreateMatrixStoreKey(
                account: "matrix-rust-store.\(Self.hash(subject))",
                allowCreation: !inspection.hasStoredData
            )
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                throw MatrixLocalStoreError(failure: .invalidKey)
            }
            passphrase = text
        }
        let data = inspection.root.appendingPathComponent("data", isDirectory: true)
        let cache = inspection.root.appendingPathComponent("cache", isDirectory: true)
        for directory in [rootDirectory, inspection.root, data, cache] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.excludeFromBackup(directory)
        }
        return MatrixLocalStorePreparation(dataPath: data.path, cachePath: cache.path, passphrase: passphrase)
    }
    // MatrixRustSDK 26.9.17 SQLite store: the encrypted Olm account lives in
    // kv[account]. A SQLite header alone does not prove a persisted identity.
    // This is read-only and never decrypts or logs any account material.
    private static func containsPersistedCryptoAccount(_ url: URL) throws -> Bool {
        // Paused/checkpointed WAL databases may have no -wal/-shm files. In
        // that case immutable read-only mode avoids creating auxiliary files.
        // Never use immutable mode when a WAL is present: it would ignore it.
        let hasWAL = FileManager.default.fileExists(atPath: url.path + "-wal")
        let uri = url.absoluteString + (hasWAL ? "?mode=ro" : "?mode=ro&immutable=1")
        var connection: OpaquePointer?
        let opened = sqlite3_open_v2(uri, &connection, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_URI, nil)
        guard opened == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw MatrixLocalStoreError(failure: .storeUnavailable)
        }
        defer { sqlite3_close(connection) }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(connection, "SELECT EXISTS(SELECT 1 FROM kv WHERE key = 'account' AND length(value) > 0)", -1, &statement, nil)
        guard prepared == SQLITE_OK else {
            throw MatrixLocalStoreError(failure: prepared == SQLITE_CORRUPT || prepared == SQLITE_NOTADB ? .recoveryRequired : .storeUnavailable)
        }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            throw MatrixLocalStoreError(failure: step == SQLITE_CORRUPT || step == SQLITE_NOTADB ? .recoveryRequired : .storeUnavailable)
        }
        return sqlite3_column_int(statement, 0) == 1
    }
    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func excludeFromBackup(_ url: URL) throws {
        var copy = url
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try copy.setResourceValues(values)
    }
}

struct MatrixDeviceIdentityContext: Equatable, Sendable {
    let homeserver: URL
    let userID: String
    let deviceID: String
    let accessToken: String
}
protocol MatrixDeviceIdentityChecking: Sendable {
    func verify(_ context: MatrixDeviceIdentityContext, requireUnpublishedKeys: Bool) async throws
}
struct MatrixDeviceIdentityVerifier: MatrixDeviceIdentityChecking {
    let session: URLSession
    init(session: URLSession = .shared) { self.session = session }
    func verify(_ context: MatrixDeviceIdentityContext, requireUnpublishedKeys: Bool) async throws {
        let identity = try await request(context, path: "/_matrix/client/v3/account/whoami")
        guard identity["user_id"] as? String == context.userID,
              identity["device_id"] as? String == context.deviceID else {
            throw MatrixLocalStoreError(failure: .deviceIdentityMismatch)
        }
        if requireUnpublishedKeys {
            let response = try await request(context, path: "/_matrix/client/v3/keys/query", body: ["device_keys": [context.userID: [context.deviceID]]])
            guard let all = response["device_keys"] as? [String: Any],
                  response["failures"] == nil || (response["failures"] as? [String: Any])?.isEmpty == true else {
                throw MatrixLocalStoreError(failure: .deviceIdentityMismatch)
            }
            if let ownValue = all[context.userID], !(ownValue is [String: Any]) {
                throw MatrixLocalStoreError(failure: .deviceIdentityMismatch)
            }
            let own = all[context.userID] as? [String: Any] ?? [:]
            guard own[context.deviceID] == nil else {
                throw MatrixLocalStoreError(failure: .existingDeviceKeys)
            }
        }
    }
    private func request(_ context: MatrixDeviceIdentityContext, path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
        let base = context.homeserver.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw MatrixLocalStoreError(failure: .deviceIdentityMismatch) }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        request.setValue("Bearer " + context.accessToken, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CSMServiceError.unavailable("Matrix nevrátil platnou odpověď pro ověření relace.") }
        guard http.statusCode == 200 else {
            // Preserve auth/rate/outage classification; never turn these into crypto recovery.
            let code = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let safeCodes = ["M_UNKNOWN_TOKEN", "M_LIMIT_EXCEEDED", "M_FORBIDDEN", "M_UNAUTHORIZED"]
            let message = code?["errcode"] as? String
            throw MatrixAPIError.httpError(http.statusCode, safeCodes.contains(message ?? "") ? message! : "Matrix identity verification unavailable")
        }
        guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CSMServiceError.unavailable("Matrix nevrátil platnou odpověď pro ověření relace.")
        }
        return decoded
    }
}

public enum CSMChatStoreRecoveryAuthorization: Sendable {
    /// User-held key is never persisted or logged. Requires successful backup recovery.
    case restoreBackup(recoveryKey: String)
    /// Permitted only with the explicit Debug/test host policy and UI confirmation.
    case confirmedTestHistoryReset
}
protocol MatrixLocalStoreRecovering: Sendable {
    func recoverLocalStore(from previous: MessagingBootstrap, with bootstrap: MessagingBootstrap, authorization: CSMChatStoreRecoveryAuthorization) async throws
}

@MainActor
struct MatrixDeviceRecoveryRouting {
    struct Record: Codable, Equatable {
        var originalDeviceID: String
        var pendingDeviceID: String
        var selectedDeviceID: String?
        var matrixScope: String
    }
    let defaults: UserDefaults
    let scope: String
    private var key: String { "cz.voldzi.cop.matrix-store-recovery." + MatrixLocalStoreFiles.hash(scope) }
    func record() throws -> Record? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(Record.self, from: data)
    }
    func reserve(original: MessagingBootstrap) throws -> Record {
        guard let id = original.deviceId, let user = original.userId, let server = original.homeserverBaseUrl else {
            throw MatrixLocalStoreError(failure: .deviceIdentityMismatch)
        }
        let matrixScope = MatrixLocalStoreFiles.hash(server.absoluteString + "|" + user)
        if let existing = try record(), existing.selectedDeviceID == nil || existing.originalDeviceID == id {
            guard existing.originalDeviceID == id, existing.matrixScope == matrixScope else {
                throw MatrixLocalStoreError(failure: .deviceIdentityMismatch)
            }
            return existing
        }
        let new = Record(originalDeviceID: id, pendingDeviceID: "CSMIOS.R." + UUID().uuidString.replacingOccurrences(of: "-", with: ""), selectedDeviceID: nil, matrixScope: matrixScope)
        defaults.set(try JSONEncoder().encode(new), forKey: key)
        return new
    }
    func commit(_ pending: Record) throws {
        guard try record() == pending else { throw MatrixLocalStoreError(failure: .deviceIdentityMismatch) }
        var selected = pending; selected.selectedDeviceID = pending.pendingDeviceID
        defaults.set(try JSONEncoder().encode(selected), forKey: key)
    }
}


public enum CSMChatStoreRecoveryPolicy {
    public static var allowsWithoutBackup: Bool {
        #if DEBUG
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CSMAllowChatRecoveryWithoutBackup") as? NSNumber else { return false }
        return CFGetTypeID(value) == CFBooleanGetTypeID() && value.boolValue
        #else
        return false
        #endif
    }
}


protocol MessagingSessionAvailability: Sendable {
    func hasUsableMessagingSession(for bootstrap: MessagingBootstrap) async -> Bool
}
