import SwiftUI

struct MobilePairingStatusSheet: View {
    @Environment(CommunicationModel.self) private var appModel
    var presentation: MobilePairingPresentation

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        statusIcon
                            .font(.title2.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.tint(iconTint.opacity(0.16)), in: .circle)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(statusTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(presentation.detail ?? defaultDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            if presentation.isInProgress {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if let expiresAt = presentation.expiresAt, presentation.isInProgress {
                        LabeledContent(
                            CSMLocalization.text("pairing.expires_at", fallback: "Platné do"),
                            value: expiresAt.formatted(date: .omitted, time: .shortened)
                        )
                    }
                }

                Section {
                    Label {
                        Text(CSMLocalization.text(
                            "pairing.security_note",
                            fallback: "Párování neobsahuje šifrovací klíče. Zprávy budou dostupné od nového čistého nastavení."
                        ))
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(CSMTheme.secureGreen)
                    }
                }
            }
            .navigationTitle(CSMLocalization.text("pairing.title", fallback: "Spárovat s COP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(CSMLocalization.text("pairing.dismiss", fallback: "Zavřít")) {
                        appModel.dismissMobilePairingPresentation()
                    }
                    .disabled(presentation.status == .claiming)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("mobilePairing.statusSheet")
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch presentation.status {
        case .needsSignIn:
            Image(systemName: "person.badge.key")
                .foregroundStyle(iconTint)
        case .claiming:
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .foregroundStyle(iconTint)
        case .waitingForWebConfirmation:
            Image(systemName: "hourglass")
                .foregroundStyle(iconTint)
        case .paired:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(iconTint)
        case .expired:
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(iconTint)
        case .accountMismatch:
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(iconTint)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(iconTint)
        }
    }

    private var iconTint: Color {
        switch presentation.status {
        case .paired:
            CSMTheme.secureGreen
        case .expired, .accountMismatch, .failed:
            CSMTheme.warningAmber
        case .needsSignIn, .claiming, .waitingForWebConfirmation:
            CSMTheme.relayCyan
        }
    }

    private var statusTitle: String {
        switch presentation.status {
        case .needsSignIn:
            CSMLocalization.text("pairing.status.needs_sign_in", fallback: "Přihlaste se stejným účtem jako ve webové aplikaci")
        case .claiming:
            CSMLocalization.text("pairing.status.claiming", fallback: "Připravuji zařízení")
        case .waitingForWebConfirmation:
            CSMLocalization.text("pairing.status.waiting", fallback: "Čeká se na potvrzení ve webové aplikaci")
        case .paired:
            CSMLocalization.text("pairing.status.paired", fallback: "Zařízení spárováno")
        case .expired:
            CSMLocalization.text("pairing.status.expired", fallback: "Párovací odkaz vypršel")
        case .accountMismatch:
            CSMLocalization.text("pairing.status.account_mismatch", fallback: "Přihlaste se stejným účtem jako ve webové aplikaci")
        case .failed:
            CSMLocalization.text("pairing.status.failed", fallback: "Párování se nepodařilo dokončit")
        }
    }

    private var defaultDetail: String {
        switch presentation.status {
        case .needsSignIn:
            CSMLocalization.text("pairing.detail.needs_sign_in", fallback: "Otevře se přihlášení csm-mobile.")
        case .claiming:
            CSMLocalization.text("pairing.detail.claiming", fallback: "Párování ověřuje zařízení u COP.")
        case .waitingForWebConfirmation:
            CSMLocalization.text("pairing.detail.waiting", fallback: "Potvrďte zařízení ve webové aplikaci COP.")
        case .paired:
            CSMLocalization.text("pairing.detail.paired", fallback: "Načítám aktuální COP nastavení a nový nativní Matrix/E2EE stav.")
        case .expired:
            CSMLocalization.text("pairing.detail.expired", fallback: "Vytvořte nové párování ve webové aplikaci.")
        case .accountMismatch:
            CSMLocalization.text("pairing.detail.same_account", fallback: "Přihlaste se stejným účtem jako ve webové aplikaci.")
        case .failed:
            CSMLocalization.text("pairing.detail.failed", fallback: "Zkuste vytvořit nové párování ve webové aplikaci.")
        }
    }
}
