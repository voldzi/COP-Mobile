import SwiftUI

struct LoginView: View {
    @Environment(CommunicationModel.self) private var appModel
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            SecureLoginBackdrop()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 28)

                    VStack(spacing: 14) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
                            .glassEffect(.regular.tint(CSMTheme.secureGreen.opacity(0.22)), in: .circle)

                        VStack(spacing: 8) {
                            Text("CSM Messenger")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(.white)
                            Text(CSMLocalization.text("login.subtitle", fallback: "Bezpečné spojení pro krizové situace"))
                                .font(.body)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            if appModel.mobilePairingPresentation != nil {
                                MobilePairingLoginNotice()
                            }
                            LoginProtectionRow(
                                systemName: "building.columns.fill",
                                title: CSMLocalization.text("login.org.title", fallback: "Přihlášení přes vaši organizaci"),
                                text: CSMLocalization.text(
                                    "login.org.text",
                                    fallback: "Otevře se ověřená přihlašovací stránka a aplikace dostane jen výsledek přihlášení."
                                )
                            )
                            LoginProtectionRow(
                                systemName: "lock.iphone",
                                title: CSMLocalization.text("login.reauth.title", fallback: "Méně opakovaného přihlašování"),
                                text: CSMLocalization.text(
                                    "login.reauth.text",
                                    fallback: "Přístup ukládáme v klíčence zařízení a obnovujeme ho bez zbytečného otevírání webu."
                                )
                            )
                            LoginProtectionRow(
                                systemName: "bubble.left.and.text.bubble.right.fill",
                                title: CSMLocalization.text("login.content.title", fallback: "Obsah zpráv zůstává chráněný"),
                                text: CSMLocalization.text(
                                    "login.content.text",
                                    fallback: "Přihlášení nesdílí texty chatů, přílohy ani historii konverzací."
                                )
                            )
                        }
                        .padding(.bottom, 4)

                        Button {
                            Task {
                                await appModel.signIn()
                            }
                        } label: {
                            Label(buttonTitle, systemImage: "person.badge.key.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .disabled(appModel.authState == .signingIn || appModel.authState == .checking)
                        .accessibilityIdentifier("login.signInButton")

                        if appModel.authState == .signingIn || appModel.authState == .checking {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(CSMLocalization.text(
                            "login.platform_notice",
                            fallback: "iPhone může před prvním přihlášením zobrazit systémové potvrzení. Znamená jen propojení aplikace s ověřenou přihlašovací stránkou, ne souhlas se sdílením obsahu zpráv."
                        ))
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)

                        if let lastError = appModel.lastError {
                            Text(lastError)
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.red.opacity(0.92))
                                .padding(.top, 4)
                        }
                    }
                    .padding(18)
                    .glassEffect(.regular.tint(.white.opacity(0.08)), in: .rect(cornerRadius: CSMTheme.cardRadius))

                    Spacer(minLength: 28)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)

            if let onClose {
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(.white)
                        .accessibilityLabel(CSMLocalization.text("conversation.close", fallback: "Zavřít chat"))
                        .accessibilityIdentifier("login.closeToMap")

                        Spacer()
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .accessibilityIdentifier("login.root")
    }

    private var buttonTitle: String {
        if appModel.mobilePairingPresentation != nil, appModel.authState == .signedOut {
            return CSMLocalization.text("login.state.pairing_sign_in", fallback: "Přihlásit a spárovat s COP")
        }
        switch appModel.authState {
        case .checking:
            return CSMLocalization.text("login.state.checking", fallback: "Kontroluji přihlášení")
        case .locked:
            return CSMLocalization.text("login.state.locked", fallback: "Odemknout")
        case .signingIn:
            return CSMLocalization.text("login.state.signing_in", fallback: "Otevírám přihlášení")
        case .signedIn:
            return CSMLocalization.text("login.state.signed_in", fallback: "Přihlášeno")
        case .signedOut:
            return CSMLocalization.text("login.state.signed_out", fallback: "Pokračovat k přihlášení")
        }
    }
}

private struct MobilePairingLoginNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "qrcode.viewfinder")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CSMTheme.relayCyan)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(CSMTheme.relayCyan.opacity(0.16)), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(CSMLocalization.text("pairing.login_notice.title", fallback: "Spárovat s COP"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(CSMLocalization.text(
                    "pairing.login_notice.detail",
                    fallback: "Přihlaste se stejným účtem jako ve webové aplikaci."
                ))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LoginProtectionRow: View {
    var systemName: String
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(CSMTheme.secureGreen)
                .frame(width: 30, height: 30)
                .glassEffect(.regular.tint(CSMTheme.secureGreen.opacity(0.14)), in: .circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SecureLoginBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let background = Path(CGRect(origin: .zero, size: size))
            context.fill(background, with: .color(CSMTheme.commandInk))

            let gridColor = Color.white.opacity(0.055)
            for x in stride(from: 0.0, through: size.width, by: 38) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
            }
            for y in stride(from: 0.0, through: size.height, by: 38) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(gridColor), lineWidth: 1)
            }

            let center = CGPoint(x: size.width * 0.72, y: size.height * 0.30)
            for index in 0..<3 {
                let radius = CGFloat(90 + index * 58)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(CSMTheme.relayCyan.opacity(0.20 - Double(index) * 0.04)), lineWidth: 1.2)
            }

            let route = Path { path in
                path.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.72))
                path.addLine(to: CGPoint(x: size.width * 0.38, y: size.height * 0.62))
                path.addLine(to: CGPoint(x: size.width * 0.58, y: size.height * 0.68))
                path.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.54))
            }
            context.stroke(route, with: .color(CSMTheme.secureGreen.opacity(0.48)), lineWidth: 3)
        }
        .ignoresSafeArea()
    }
}
