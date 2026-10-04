import Foundation
import CryptoKit
import CoreLocation
import Security

public enum CSMDispatchProtectionError: Error, Sendable {
    case accountChanged, keyUnavailable, invalidAudience, inactiveShare, invalidGPS, stalePoint, replay, invalidCiphertext
}

/// Keys stay in SDK-owned ThisDeviceOnly Keychain storage. No coordinates are persisted.
/// Network endpoints see metadata plus recipient-authenticated ciphertext only.
@MainActor public final class CSMDispatchEncryption {
    private let accountScope: String
    private let privateKey: Curve25519.KeyAgreement.PrivateKey
    private let registrationOperation: UUID
    private var device: CSMDispatchDevice?
    private var outgoing: [UUID: (sequence: Int, observed: Date)] = [:]
    private var incoming: [UUID: Int] = [:]
    private var invalidated = false
    private var observer: DispatchObservation?

    public init(expectedScope: String) throws {
        guard CSMCommunicationRuntime.shared.mobilitySessionScope() == expectedScope else { throw CSMDispatchProtectionError.accountChanged }
        accountScope = expectedScope
        let keyAccount = expectedScope + ":x25519-v1"
        if let data = try DispatchKeychain.read(keyAccount) {
            guard data.count == 48 else { throw CSMDispatchProtectionError.keyUnavailable }
            privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data.prefix(32))
            guard let operation = UUID(uuidString: data.suffix(16).map { String(format: "%02x", $0) }.joined().uuidHyphenated) else { throw CSMDispatchProtectionError.keyUnavailable }
            registrationOperation = operation
        } else {
            let key = Curve25519.KeyAgreement.PrivateKey(); let operation = UUID()
            var raw = operation.uuid
            let data = key.rawRepresentation + withUnsafeBytes(of: &raw) { Data($0) }
            try DispatchKeychain.save(data, account: keyAccount)
            privateKey = key; registrationOperation = operation
        }
        observer = DispatchObservation(NotificationCenter.default.addObserver(forName: .csmMobilitySessionChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidated = true; self?.outgoing.removeAll(); self?.incoming.removeAll() }
        })
    }


    private func checkAccount() throws {
        guard !invalidated, CSMCommunicationRuntime.shared.mobilitySessionScope() == accountScope else { throw CSMDispatchProtectionError.accountChanged }
    }
    /// Repeating registration uses the persisted operation ID and public key; never creates a share.
    public func registerDevice(name: String) async throws -> CSMDispatchDevice {
        try checkAccount()
        let labelAccount = accountScope + ":registration-name"
        let storedName = try DispatchKeychain.read(labelAccount)
        let label: String
        if let storedName, let saved = String(data: storedName, encoding: .utf8) { label = saved }
        else {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 80 else { throw CSMDispatchProtectionError.keyUnavailable }
            label = trimmed; try DispatchKeychain.save(Data(label.utf8), account: labelAccount)
        }
        let response = try await CSMCommunicationRuntime.shared.dispatchDeviceRegister(request: .init(operationId: registrationOperation, publicKeyX25519: privateKey.publicKey.rawRepresentation.base64EncodedString(), deviceName: label), expectedScope: accountScope)
        try checkAccount()
        guard response.publicKeyX25519 == privateKey.publicKey.rawRepresentation.base64EncodedString(), response.keyRevision == 1 else { throw CSMDispatchProtectionError.invalidAudience }
        device = response; return response
    }
    /// Explicit revoke removes local key only after server acknowledgement; retries retain the key.
    public func revokeDevice(operationId: UUID) async throws {
        try checkAccount(); guard let device else { throw CSMDispatchProtectionError.keyUnavailable }
        _ = try await CSMCommunicationRuntime.shared.dispatchDeviceRevoke(request: .init(operationId: operationId, deviceId: device.deviceId), expectedScope: accountScope)
        try checkAccount(); try DispatchKeychain.remove(accountScope + ":x25519-v1"); try DispatchKeychain.remove(accountScope + ":registration-name")
        invalidated = true; self.device = nil; outgoing.removeAll(); incoming.removeAll()
    }
    /// Caller must have fresh explicit consent and apply its local private zones first.
    /// No estimated/simulated CLLocation is accepted and this facade never queues GPS.
    public func sealGPS(_ location: CLLocation, share: CSMDispatchShare, readiness: CSMDispatchReadiness, sequence: Int, now: Date = Date()) throws -> CSMDispatchPointPublish {
        try checkAccount(); guard let device else { throw CSMDispatchProtectionError.keyUnavailable }
        try validate(share: share, readiness: readiness, now: now)
        guard share.accountId == device.accountId, share.deviceId == device.deviceId,
              sequence > max(share.sequence, outgoing[share.shareId]?.sequence ?? 0),
              CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy.isFinite,
              (0...100).contains(location.horizontalAccuracy),
              now.timeIntervalSince(location.timestamp) <= 15, location.timestamp.timeIntervalSince(now) <= 5,
              location.timestamp >= DispatchDate.parse(share.startedAt)!,
              location.sourceInformation?.isSimulatedBySoftware != true else { throw CSMDispatchProtectionError.invalidGPS }
        if let previous = outgoing[share.shareId] {
            guard sequence > previous.sequence, location.timestamp.timeIntervalSince(previous.observed) >= 5 else { throw CSMDispatchProtectionError.replay }
        }
        let observedAt = DispatchDate.string(location.timestamp)
        let payload = CSMDispatchPointPayload(lat: location.coordinate.latitude, lon: location.coordinate.longitude, horizontalAccuracyM: location.horizontalAccuracy)
        let plaintext = try JSONEncoder().encode(payload)
        let boxes = try readiness.devices.map { recipient in
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            guard let bytes = Data(base64Encoded: recipient.publicKeyX25519), bytes.count == 32 else { throw CSMDispatchProtectionError.invalidAudience }
            let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bytes)
            let key = try DispatchCipher.key(ephemeral: ephemeral.sharedSecretFromKeyAgreement(with: recipientKey), authenticated: privateKey.sharedSecretFromKeyAgreement(with: recipientKey), shareId: share.shareId)
            let aad = try DispatchCipher.aad(share: share, recipient: recipient.deviceId, sequence: sequence, observedAt: observedAt)
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
            guard let combined = sealed.combined else { throw CSMDispatchProtectionError.invalidCiphertext }
            return CSMDispatchEncryptedBox(recipientDeviceId: recipient.deviceId, ephemeralPublicKeyX25519: ephemeral.publicKey.rawRepresentation.base64EncodedString(), combinedCiphertext: combined.base64EncodedString())
        }
        outgoing[share.shareId] = (sequence, location.timestamp)
        return .init(deviceId: device.deviceId, sequence: sequence, observedAt: observedAt, source: .gps, membershipRevision: share.membershipRevision, audienceHash: share.audienceHash, boxes: boxes)
    }
    /// Only decrypt a point inside a fresh authoritative snapshot. Returned coordinates are RAM-only.
    /// UI must discard its whole previous map snapshot when activeShares changes/stop is confirmed.
    public func openPoint(_ point: CSMDispatchPoint, in snapshot: CSMDispatchSnapshot, now: Date = Date()) throws -> CSMDispatchPointPayload {
        try checkAccount(); guard let device else { throw CSMDispatchProtectionError.keyUnavailable }
        guard let serverAt = DispatchDate.parse(snapshot.serverTimestamp), abs(now.timeIntervalSince(serverAt)) <= 15,
              snapshot.group.members.contains(where: { $0.accountId == device.accountId }), !snapshot.group.deleted,
              snapshot.group.groupId == snapshot.readiness.groupId,
              let share = snapshot.activeShares.first(where: { $0.shareId == point.shareId }),
              share.accountId == point.accountId, share.deviceId == point.deviceId, share.sequence == point.sequence,
              point.box.recipientDeviceId == device.deviceId,
              let observed = DispatchDate.parse(point.observedAt), let expiry = DispatchDate.parse(point.expiresAt),
              now < expiry, now.timeIntervalSince(observed) <= 180, observed.timeIntervalSince(now) <= 5,
              let shareExpiry = DispatchDate.parse(share.expiresAt), expiry <= shareExpiry, expiry <= observed.addingTimeInterval(180),
              point.sequence >= (incoming[point.shareId] ?? 0) else { throw CSMDispatchProtectionError.stalePoint }
        try validate(share: share, readiness: snapshot.readiness, now: now)
        guard let sender = snapshot.readiness.devices.first(where: { $0.deviceId == point.deviceId && $0.accountId == point.accountId }),
              let senderBytes = Data(base64Encoded: sender.publicKeyX25519), senderBytes.count == 32,
              let ephemeralBytes = Data(base64Encoded: point.box.ephemeralPublicKeyX25519), ephemeralBytes.count == 32,
              let combined = Data(base64Encoded: point.box.combinedCiphertext), (29...4096).contains(combined.count) else { throw CSMDispatchProtectionError.invalidCiphertext }
        do {
            let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralBytes)
            let senderKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: senderBytes)
            let key = try DispatchCipher.key(ephemeral: privateKey.sharedSecretFromKeyAgreement(with: ephemeral), authenticated: privateKey.sharedSecretFromKeyAgreement(with: senderKey), shareId: share.shareId)
            let aad = try DispatchCipher.aad(share: share, recipient: device.deviceId, sequence: point.sequence, observedAt: point.observedAt)
            let clear = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: aad)
            let value = try JSONDecoder().decode(CSMDispatchPointPayload.self, from: clear)
            guard value.lat.isFinite, value.lon.isFinite, value.horizontalAccuracyM.isFinite,
                  (-90...90).contains(value.lat), (-180...180).contains(value.lon), (0...100).contains(value.horizontalAccuracyM) else { throw CSMDispatchProtectionError.invalidGPS }
            incoming[share.shareId] = point.sequence
            return value
        } catch { throw CSMDispatchProtectionError.invalidCiphertext }
    }
    private func validate(share: CSMDispatchShare, readiness: CSMDispatchReadiness, now: Date) throws {
        guard share.state == .active, let start = DispatchDate.parse(share.startedAt), let end = DispatchDate.parse(share.expiresAt), start <= now.addingTimeInterval(5), now < end, end.timeIntervalSince(start) <= 28800,
              readiness.state == .ready, readiness.groupId == share.groupId, readiness.membershipRevision == share.membershipRevision, readiness.audienceHash == share.audienceHash,
              !readiness.devices.isEmpty, Set(readiness.devices.map(\.deviceId)).count == readiness.devices.count,
              let device, readiness.devices.contains(where: {$0.deviceId == device.deviceId && $0.accountId == device.accountId && $0.publicKeyX25519 == privateKey.publicKey.rawRepresentation.base64EncodedString()}) else { throw CSMDispatchProtectionError.invalidAudience }
    }
}

enum DispatchCipher {
    // Sender-static + per-recipient ephemeral DH authenticates the sender as well as protecting content.
    static func key(ephemeral: SharedSecret, authenticated: SharedSecret, shareId: UUID) throws -> SymmetricKey {
        let input = ephemeral.withUnsafeBytes { Data($0) } + authenticated.withUnsafeBytes { Data($0) }
        guard input.count == 64 else { throw CSMDispatchProtectionError.invalidCiphertext }
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input), salt: Data(SHA256.hash(data: Data(shareId.uuidString.lowercased().utf8))), info: Data("cop-dispatch-point-v1-authenticated".utf8), outputByteCount: 32)
    }
    static func aad(share: CSMDispatchShare, recipient: UUID, sequence: Int, observedAt: String) throws -> Data {
        let object: [String: Any] = ["protocol": "cop-dispatch-point-v1-authenticated", "groupId": share.groupId.uuidString.lowercased(), "shareId": share.shareId.uuidString.lowercased(), "senderDeviceId": share.deviceId.uuidString.lowercased(), "recipientDeviceId": recipient.uuidString.lowercased(), "audienceHash": share.audienceHash, "membershipRevision": share.membershipRevision, "sequence": sequence, "observedAt": observedAt]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
private enum DispatchDate {
    static func string(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) }
    static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}
private extension String {
    var uuidHyphenated: String {
        guard count == 32 else { return self }
        let chars = Array(self); return String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
    }
}
private enum DispatchKeychain {
    static let service = "cz.cop.communication.private-dispatch.v1"
    static func query(_ account: String) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false] }
    static func read(_ account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CSMDispatchProtectionError.keyUnavailable }; return data
    }
    static func save(_ data: Data, account: String) throws {
        var q = query(account); q[kSecValueData as String] = data; q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw CSMDispatchProtectionError.keyUnavailable }
    }
    static func remove(_ account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CSMDispatchProtectionError.keyUnavailable }
    }
}

private final class DispatchObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
