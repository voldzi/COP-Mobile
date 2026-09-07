import SwiftUI

struct StatusPill: View {
    var text: String
    var systemImage: String
    var tint: Color

    var body: some View {
        let content = Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .accessibilityLabel(Text(text))

        #if os(iOS)
        content
            .glassEffect(.regular.tint(tint.opacity(0.14)), in: .rect(cornerRadius: CSMTheme.controlRadius))
        #else
        content
            .background(tint.opacity(0.12), in: Capsule())
        #endif
    }
}

extension ConnectionMode {
    var tint: Color {
        switch self {
        case .online: CSMTheme.secureGreen
        case .degraded: CSMTheme.warningAmber
        case .offline: CSMTheme.criticalRed
        }
    }

    var symbolName: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .offline: "wifi.slash"
        }
    }
}

extension AlertSeverity {
    var tint: Color {
        switch self {
        case .info: CSMTheme.signalBlue
        case .warning: CSMTheme.warningAmber
        case .critical: CSMTheme.criticalRed
        }
    }

    var symbolName: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }
}
