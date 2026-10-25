import Foundation

enum ChatDeviceVerification: String, Codable, Equatable, Sendable { case unknown, verified, unverified }

extension ChatDeviceVerification {
    var title: String {
        switch self {
        case .unknown: CSMLocalization.text("chat.status.device.unknown.title", fallback: "Ověření telefonu není potvrzené")
        case .verified: CSMLocalization.text("chat.status.device.verified.title", fallback: "Telefon je ověřený")
        case .unverified: CSMLocalization.text("chat.status.device.unverified.title", fallback: "Telefon čeká na ověření")
        }
    }
    var userMessage: String {
        switch self {
        case .unknown: CSMLocalization.text("chat.status.device.unknown.message", fallback: "Obnovte konverzaci a zkontrolujte stav znovu. Dostupnost zálohy sama o sobě nepotvrzuje ověření telefonu.")
        case .verified: CSMLocalization.text("chat.status.device.verified.message", fallback: "Zabezpečení účtu tento telefon ověřilo. Dostupnost obsahu jednotlivých zpráv se kontroluje zvlášť.")
        case .unverified: CSMLocalization.text("chat.status.device.unverified.message", fallback: "Zkontrolujte možnosti ověření a obnovení níže. Bez ověření nemusí být všechny zprávy dostupné.")
        }
    }
}

struct MatrixEncryptionRecoveryStatus: Codable, Equatable, Sendable {
    var supported: Bool
    var keyBackupExists: Bool
    var keyBackupEnabled: Bool
    var recoveryEnabled: Bool
    var keyBackupUsable: Bool
    var matrixRustCompatible: Bool
    var needsSetup: Bool
    var needsRecovery: Bool
    var ready: Bool
    var backupState: String
    var recoveryState: String
    var detail: String?
    var deviceVerification: ChatDeviceVerification?

    init(
        supported: Bool,
        keyBackupExists: Bool,
        keyBackupEnabled: Bool,
        recoveryEnabled: Bool,
        keyBackupUsable: Bool? = nil,
        matrixRustCompatible: Bool? = nil,
        needsSetup: Bool,
        needsRecovery: Bool,
        ready: Bool? = nil,
        backupState: String,
        recoveryState: String,
        detail: String?,
        deviceVerification: ChatDeviceVerification = .unknown
    ) {
        let backupUsable = keyBackupUsable ?? keyBackupEnabled
        self.supported = supported
        self.keyBackupExists = keyBackupExists
        self.keyBackupEnabled = keyBackupEnabled
        self.recoveryEnabled = recoveryEnabled
        self.keyBackupUsable = backupUsable
        self.matrixRustCompatible = matrixRustCompatible ?? recoveryEnabled
        self.needsSetup = needsSetup
        self.needsRecovery = needsRecovery
        self.ready = ready ?? backupUsable
        self.backupState = backupState
        self.recoveryState = recoveryState
        self.detail = detail
        self.deviceVerification = deviceVerification
    }

    static let notLoaded = MatrixEncryptionRecoveryStatus(
        supported: false,
        keyBackupExists: false,
        keyBackupEnabled: false,
        recoveryEnabled: false,
        needsSetup: false,
        needsRecovery: false,
        ready: false,
        backupState: "not_loaded",
        recoveryState: "not_loaded",
        detail: nil
    )

    static func unsupported(_ detail: String) -> MatrixEncryptionRecoveryStatus {
        MatrixEncryptionRecoveryStatus(
            supported: false,
            keyBackupExists: false,
            keyBackupEnabled: false,
            recoveryEnabled: false,
            needsSetup: false,
            needsRecovery: false,
            ready: false,
            backupState: "unsupported",
            recoveryState: "unsupported",
            detail: detail
        )
    }

    static func unavailable(_ detail: String) -> MatrixEncryptionRecoveryStatus {
        MatrixEncryptionRecoveryStatus(
            supported: true,
            keyBackupExists: false,
            keyBackupEnabled: false,
            recoveryEnabled: false,
            needsSetup: false,
            needsRecovery: false,
            ready: false,
            backupState: "unavailable",
            recoveryState: "unavailable",
            detail: detail
        )
    }

    var requiresUserAction: Bool {
        supported && (needsRecovery || deviceVerification == .unverified)
    }

    var blocksSending: Bool {
        false
    }

    var hasMatrixRustCompatibilityWarning: Bool {
        supported && keyBackupUsable && !matrixRustCompatible
    }

    var primaryActionTitle: String {
        needsSetup
            ? CSMLocalization.text("matrix.recovery.setup.action", fallback: "Nastavit obnovu")
            : CSMLocalization.text("matrix.recovery.recover.action", fallback: "Obnovit zařízení")
    }

    var title: String {
        if keyBackupUsable {
            if hasMatrixRustCompatibilityWarning {
                return CSMLocalization.text(
                    "matrix.recovery.compatibility_warning.title",
                    fallback: "Obnovení historie vyžaduje kontrolu"
                )
            }
            return CSMLocalization.text("matrix.recovery.ready.title", fallback: "E2EE obnova je aktivní")
        }
        if needsSetup {
            return CSMLocalization.text("matrix.recovery.setup.title", fallback: "Doporučené nastavení obnovy")
        }
        if needsRecovery {
            return CSMLocalization.text("matrix.recovery.recover.title", fallback: "Starší historie není odemčená")
        }
        return CSMLocalization.text("matrix.recovery.checking.title", fallback: "Ověřuji zabezpečení chatu")
    }

    var userMessage: String {
        if keyBackupUsable {
            if hasMatrixRustCompatibilityWarning {
                return CSMLocalization.text(
                    "matrix.recovery.compatibility_warning.message",
                    fallback: "Přístup k záloze je dostupný. Její použití na dalším zařízení zatím není potvrzené."
                )
            }
            return CSMLocalization.text(
                "matrix.recovery.ready.subtitle",
                fallback: "Telefon má přístup k šifrované záloze klíčů pro více zařízení."
            )
        }
        if needsSetup {
            return CSMLocalization.text(
                "matrix.recovery.setup.subtitle",
                fallback: "Můžete vytvořit obnovovací klíč, aby šlo později číst historii i na dalších zařízeních. Běžné šifrované psaní tím není blokované."
            )
        }
        if needsRecovery {
            return CSMLocalization.text(
                "matrix.recovery.recover.subtitle",
                fallback: "Telefon zatím nemá odemčenou E2EE zálohu pro starší zprávy z webu nebo dalších zařízení. Nové šifrované zprávy zůstávají dostupné."
            )
        }
        return detail ?? CSMLocalization.text(
            "matrix.recovery.checking.subtitle",
            fallback: "Aplikace kontroluje stav šifrované obnovy."
        )
    }

    var technicalSummary: String {
        [
            "supported=\(supported)",
            "ready=\(ready)",
            "keyBackupExists=\(keyBackupExists)",
            "keyBackupEnabled=\(keyBackupEnabled)",
            "keyBackupUsable=\(keyBackupUsable)",
            "recoveryEnabled=\(recoveryEnabled)",
            "matrixRustCompatible=\(matrixRustCompatible)",
            "backupState=\(backupState)",
            "recoveryState=\(recoveryState)",
            detail.map { "detail=\($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

struct MatrixEncryptionRecoveryUserFacingError: Error, LocalizedError, Equatable, Sendable {
    enum Reason: String, Codable, Sendable {
        case webSecretStorageCompatibility
        case generic
    }

    var reason: Reason
    var userMessage: String
    var technicalDetail: String

    init(
        reason: Reason = .generic,
        userMessage: String,
        technicalDetail: String
    ) {
        self.reason = reason
        self.userMessage = userMessage
        self.technicalDetail = technicalDetail
    }

    var errorDescription: String? {
        userMessage
    }
}

protocol MatrixEncryptionRecoveryManaging: Sendable {
    func encryptionRecoveryStatus() async -> MatrixEncryptionRecoveryStatus
    func createEncryptionRecovery(reset: Bool) async throws -> String
    func resetEncryptionRecovery(oldRecoveryKey: String) async throws -> String
    func restoreEncryptionRecovery(recoveryKey: String) async throws
}
