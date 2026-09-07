import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct MatrixEncryptionRecoveryBanner: View {
    var status: MatrixEncryptionRecoveryStatus
    var onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.horizontal.fill")
                .font(.title3)
                .foregroundStyle(CSMTheme.warningAmber)
                .frame(width: 34, height: 34)
                .background(CSMTheme.warningAmber.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(status.userMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Button(action: onAction) {
                Label(status.primaryActionTitle, systemImage: "arrow.forward.circle.fill")
                    .labelStyle(.iconOnly)
                    .imageScale(.large)
            }
            .buttonStyle(.glass)
            .foregroundStyle(CSMTheme.signalBlue)
            .accessibilityLabel(status.primaryActionTitle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous)
                .strokeBorder(CSMTheme.warningAmber.opacity(0.26), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityIdentifier("chat.encryptionRecoveryBanner")
    }
}

struct MatrixEncryptionRecoverySheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isRecoveryKeyFocused: Bool
    @State private var recoveryKeyInput = ""
    @State private var showsResetConfirmation = false
    @State private var showsTechnicalDetails = false

    var status: MatrixEncryptionRecoveryStatus
    var generatedKey: String?
    var errorText: String?
    var errorTechnicalDetail: String?
    var isWorking: Bool
    var onCreate: () -> Void
    var onRestore: (String) -> Void
    var onReset: (String) -> Void
    var onClearGeneratedKey: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: status.keyBackupUsable ? "lock.shield.fill" : "key.horizontal.fill")
                            .font(.title2)
                            .foregroundStyle(statusTint)
                            .frame(width: 44, height: 44)
                            .background(statusTint.opacity(0.14), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.title)
                                .font(.headline)
                            Text(status.userMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let generatedKey {
                    generatedKeySection(generatedKey)
                } else if status.keyBackupUsable {
                    readySection
                } else if status.needsRecovery {
                    restoreSection
                } else {
                    setupSection
                }

                if let errorText, !errorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(CSMTheme.warningAmber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if needsWebMobileRecoveryPreparation {
                    Section(CSMLocalization.text("matrix.recovery.web_repair.title", fallback: "Dokončení opravy")) {
                        Text(CSMLocalization.text(
                            "matrix.recovery.web_repair.instructions",
                            fallback: "1. Otevřete COP web a přihlaste se.\n2. V chatu otevřete E2EE a zvolte „Pokusit se vytvořit nový klíč pro iOS“.\n3. Potvrďte čistý recovery cyklus, nový klíč bezpečně uložte a vraťte se sem."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        Link(destination: URL(string: "https://cop.zeleznalady.cz/chat/")!) {
                            Label(
                                CSMLocalization.text("matrix.recovery.web_repair.open", fallback: "Otevřít COP web"),
                                systemImage: "safari"
                            )
                        }
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                        Text(technicalSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } label: {
                        Label(CSMLocalization.text("matrix.recovery.admin_details", fallback: "Podrobnosti pro správce"), systemImage: "wrench.and.screwdriver")
                    }
                }
            }
            .navigationTitle(CSMLocalization.text("matrix.recovery.sheet.title", fallback: "Obnova E2EE"))
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CSMLocalization.text("matrix.recovery.close", fallback: "Zavřít")) {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                resetConfirmationTitle,
                isPresented: $showsResetConfirmation,
                titleVisibility: .visible
            ) {
                Button(resetConfirmationActionTitle, role: .destructive) {
                    isRecoveryKeyFocused = false
                    // Clean-start intentionally ignores any typed legacy key. Retrying
                    // recoverAndReset with a web-only key leaves the device locked out.
                    onReset("")
                }
                Button(CSMLocalization.text("common.cancel", fallback: "Zrušit"), role: .cancel) {}
            } message: {
                Text(resetConfirmationMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("chat.encryptionRecoverySheet")
    }

    private var technicalSummary: String {
        [
            status.technicalSummary,
            errorTechnicalDetail.map { "lastRecoveryError=\($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    private var statusTint: Color {
        if status.hasMatrixRustCompatibilityWarning { return CSMTheme.warningAmber }
        return status.keyBackupUsable ? CSMTheme.secureGreen : CSMTheme.warningAmber
    }

    private var needsWebMobileRecoveryPreparation: Bool {
        let detail = [errorText, errorTechnicalDetail]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
        let identifiesCrossSigning = detail.contains("m.cross_signing") ||
            detail.contains("cross-signing") ||
            detail.contains("cross signing")
        return identifiesCrossSigning &&
            (detail.contains("ios matrix sdk") || detail.contains("import") || detail.contains("secret"))
    }

    private var setupSection: some View {
        Section {
            Text(CSMLocalization.text("matrix.recovery.setup.description", fallback: "CSM Messenger vytvoří obnovovací klíč pro Matrix E2EE key backup. Klíč se zobrazí jednou a musíte si ho uložit mimo telefon."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onCreate()
            } label: {
                Label(
                    isWorking
                        ? CSMLocalization.text("matrix.recovery.setup.working", fallback: "Vytvářím...")
                        : CSMLocalization.text("matrix.recovery.setup.create", fallback: "Vytvořit obnovovací klíč"),
                    systemImage: "key.horizontal.fill"
                )
            }
            .disabled(isWorking)
        }
    }

    private var restoreSection: some View {
        Section {
            Text(CSMLocalization.text("matrix.recovery.restore.description", fallback: "Zadejte obnovovací klíč uložený při nastavení ve webovém chatu nebo na jiném zařízení. Klíč se neuloží do aplikace."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $recoveryKeyInput)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 96)
                .focused($isRecoveryKeyFocused)
                .accessibilityLabel(CSMLocalization.text("matrix.recovery.restore.key_label", fallback: "Obnovovací klíč"))

            Button {
                isRecoveryKeyFocused = false
                onRestore(recoveryKeyInput)
            } label: {
                Label(
                    isWorking
                        ? CSMLocalization.text("matrix.recovery.restore.working", fallback: "Obnovuji...")
                        : CSMLocalization.text("matrix.recovery.restore.action", fallback: "Obnovit zařízení"),
                    systemImage: "arrow.clockwise.circle.fill"
                )
            }
            .disabled(isWorking || recoveryKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                isRecoveryKeyFocused = false
                showsResetConfirmation = true
            } label: {
                Label(CSMLocalization.text("matrix.recovery.restore.reset_without_history", fallback: "Začít znovu bez staré historie"), systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            }
            .disabled(isWorking)
        }
    }

    private var readySection: some View {
        Section {
            Label(CSMLocalization.text("matrix.recovery.ready.device_has_access", fallback: "Toto zařízení má přístup k E2EE záloze."), systemImage: "checkmark.seal.fill")
                .foregroundStyle(CSMTheme.secureGreen)
            Text(CSMLocalization.text("matrix.recovery.ready.key_not_stored", fallback: "Aplikace obnovovací klíč neukládá. Pokud ho už nemáte uložený, vygenerujte nový a bezpečně ho uložte mimo telefon."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                showsResetConfirmation = true
            } label: {
                Label(CSMLocalization.text("matrix.recovery.ready.rotate", fallback: "Vygenerovat nový obnovovací klíč"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isWorking)

            Button(CSMLocalization.text("matrix.recovery.done", fallback: "Hotovo")) {
                dismiss()
            }
        }
    }

    private func generatedKeySection(_ generatedKey: String) -> some View {
        Section {
            Text(CSMLocalization.text("matrix.recovery.generated.description", fallback: "Uložte tento obnovovací klíč do správce hesel nebo na jiné bezpečné místo. Bez něj nepůjde obnovit šifrovanou historii na novém zařízení."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(generatedKey)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .padding(.vertical, 6)

            Button {
                copyToPasteboard(generatedKey)
            } label: {
                Label(CSMLocalization.text("matrix.recovery.copy_key", fallback: "Zkopírovat klíč"), systemImage: "doc.on.doc")
            }

            Button(CSMLocalization.text("matrix.recovery.saved", fallback: "Mám uloženo")) {
                onClearGeneratedKey()
                dismiss()
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
    }

    private var resetConfirmationTitle: String {
        status.keyBackupUsable
            ? CSMLocalization.text("matrix.recovery.rotate.confirm.title", fallback: "Vygenerovat nový obnovovací klíč?")
            : CSMLocalization.text("matrix.recovery.reset.confirm.title", fallback: "Začít s novým obnovovacím klíčem?")
    }

    private var resetConfirmationActionTitle: String {
        status.keyBackupUsable
            ? CSMLocalization.text("matrix.recovery.rotate.confirm.action", fallback: "Vygenerovat nový klíč")
            : CSMLocalization.text("matrix.recovery.reset.create_new", fallback: "Vytvořit nový klíč")
    }

    private var resetConfirmationMessage: String {
        status.keyBackupUsable
            ? CSMLocalization.text(
                "matrix.recovery.rotate.warning",
                fallback: "Nový obnovovací klíč se zobrazí jednou. Starý klíč už nepoužívejte pro nové obnovení a nový klíč bezpečně uložte mimo telefon."
            )
            : CSMLocalization.text(
                "matrix.recovery.reset.warning",
                fallback: "Vytvoří se nový čistý E2EE stav a nový obnovovací klíč. Starý klíč zadaný výše se nepoužije. Starší šifrovaná historie nemusí být na tomto zařízení dostupná a nový klíč musíte bezpečně uložit."
            )
    }
}
