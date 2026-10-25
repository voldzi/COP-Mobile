import Foundation

/// Content availability is separate from delivery. Received ciphertext is not
/// an outgoing-send failure. Only this bounded category is stored, never keys.
enum MessageDecryptionFailure: String, Codable, Equatable, Hashable, Sendable {
    case missingKeys, senderVerificationRequired, senderIdentityChanged
    case unknownSenderDevice, recipientVerificationRequired, historicalKeysUnavailable
    case sentBeforeJoining, withheldBySender, unsupportedEncryption

    var userMessage: String {
        switch self {
        case .missingKeys:
            "Tuto zprávu zatím nelze přečíst. Zkuste obnovit konverzaci nebo otevřít Stav chatu."
        case .senderVerificationRequired:
            "Zařízení odesílatele zatím není bezpečně ověřené. Otevřete Stav chatu."
        case .senderIdentityChanged:
            "Změnilo se zabezpečení odesílatele. Před přečtením zprávy je potřeba ověřit jeho identitu."
        case .unknownSenderDevice:
            "Zařízení odesílatele zatím nelze bezpečně ověřit. Zkuste obnovit konverzaci."
        case .recipientVerificationRequired:
            "Pro přečtení této zprávy je potřeba ověřit tento telefon. Otevřete Stav chatu."
        case .historicalKeysUnavailable:
            "Tato starší zpráva nemá v tomto telefonu dostupné klíče. Bez jejich obnovení ji nelze přečíst."
        case .sentBeforeJoining:
            "Zpráva vznikla před vaším přidáním do konverzace. Potřebné klíče tento telefon nemá."
        case .withheldBySender:
            "Klíče k této zprávě se nepodařilo získat od odesílatele. Otevřete Stav chatu."
        case .unsupportedEncryption:
            "Tento typ zabezpečené zprávy aplikace neumí otevřít. Požádejte podporu o pomoc."
        }
    }
}

extension ChatMessage {
    var hasUnavailableEncryptedContent: Bool {
        if decryptionFailure != nil { return true }
        let legacy = body.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
        return ["zpravu se nepodarilo desifrovat na tomto zarizeni.",
                "zpravu nelze desifrovat na tomto zarizeni.", "unable to decrypt"].contains(legacy)
    }
}
