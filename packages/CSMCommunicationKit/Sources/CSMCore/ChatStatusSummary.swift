import Foundation

/// Transport, received content and history recovery are independent witnesses.
/// A usable key backup is never proof that a conversation or call works.
struct ChatStatusSummary: Equatable {
    let title: String
    let subtitle: String
    let systemImage: String
    let needsAttention: Bool

    static func make(delivery: ChatDeliveryPresentation, unreadableMessageCount: Int,
                     verification: ChatDeviceVerification?) -> Self {
        if unreadableMessageCount > 0 {
            return Self(title: CSMLocalization.text("chat.status.content.unreadable.title", fallback: "Některé zprávy nelze přečíst"),
                subtitle: CSMLocalization.text("chat.status.content.unreadable.message", fallback: "Obnovte konverzaci. Pokud potíže trvají, zkontrolujte ověření telefonu a obnovení historie."),
                systemImage: "lock.trianglebadge.exclamationmark", needsAttention: true)
        }
        if delivery.isVisible {
            return Self(title: delivery.title, subtitle: delivery.subtitle, systemImage: delivery.systemImage, needsAttention: true)
        }
        if verification == .unverified {
            return Self(title: CSMLocalization.text("chat.status.device.unverified.title", fallback: "Telefon čeká na ověření"),
                subtitle: CSMLocalization.text("chat.status.device.unverified.message", fallback: "Zkontrolujte možnosti ověření a obnovení níže. Bez ověření nemusí být všechny zprávy dostupné."),
                systemImage: "shield.lefthalf.filled", needsAttention: true)
        }
        return Self(title: CSMLocalization.text("chat.status.messages.title", fallback: "Stav zpráv"),
            subtitle: CSMLocalization.text("chat.status.messages.message", fallback: "Potvrzení odeslání, doručení a přečtení najdete u jednotlivých zpráv."),
            systemImage: "lock.shield", needsAttention: false)
    }
}
