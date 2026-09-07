import SwiftUI

enum CSMTheme {
    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 8
    static let compactSpacing: CGFloat = 8
    static let regularSpacing: CGFloat = 12
    static let looseSpacing: CGFloat = 16
    static let panelPadding: CGFloat = 14

    static let secureGreen = Color(red: 0.05, green: 0.58, blue: 0.34)
    static let signalBlue = Color(red: 0.10, green: 0.48, blue: 0.84)
    static let relayCyan = Color(red: 0.05, green: 0.62, blue: 0.66)
    static let warningAmber = Color(red: 0.86, green: 0.48, blue: 0.10)
    static let criticalRed = Color(red: 0.82, green: 0.14, blue: 0.16)
    static let commandInk = Color(red: 0.08, green: 0.11, blue: 0.14)
}

struct CSMGlassPanel<Content: View>: View {
    var tint: Color
    var interactive: Bool
    @ViewBuilder var content: Content

    init(
        tint: Color = .accentColor,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tint = tint
        self.interactive = interactive
        self.content = content()
    }

    var body: some View {
        content
            .padding(CSMTheme.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            }
            .csmGlassSurface(tint: tint, cornerRadius: CSMTheme.cardRadius, interactive: interactive)
    }
}

struct CSMMetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CSMTrustItem: Identifiable {
    var id: String { "\(title)-\(value)-\(systemImage)" }
    var title: String
    var value: String
    var systemImage: String
    var tint: Color
}

struct CSMTrustBadge: View {
    var item: CSMTrustItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(item.tint)
                .frame(width: 18, height: 18)
                .background(item.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(item.value)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .csmGlassSurface(tint: item.tint, cornerRadius: CSMTheme.cardRadius)
        .accessibilityElement(children: .combine)
    }
}

struct CSMTrustStrip: View {
    var items: [CSMTrustItem]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: CSMTheme.compactSpacing) {
                ForEach(items) { item in
                    CSMTrustBadge(item: item)
                }
            }
            HStack(spacing: 6) {
                ForEach(items) { item in
                    CSMCompactTrustBadge(item: item)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct CSMCompactTrustBadge: View {
    var item: CSMTrustItem

    var body: some View {
        VStack(spacing: 2) {
            Text(item.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(item.value)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .csmGlassSurface(tint: item.tint, cornerRadius: CSMTheme.cardRadius)
        .accessibilityElement(children: .combine)
    }
}

struct CSMSectionLabel: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0)
    }
}

extension View {
    @ViewBuilder
    func csmGlassSurface(
        tint: Color = .accentColor,
        cornerRadius: CGFloat = CSMTheme.cardRadius,
        interactive: Bool = false
    ) -> some View {
        #if os(iOS)
        if interactive {
            glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: cornerRadius))
        }
        #else
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    @ViewBuilder
    func csmCircularGlassButton(tint: Color = .accentColor) -> some View {
        #if os(iOS)
        glassEffect(.regular.tint(tint.opacity(0.12)).interactive(), in: .circle)
        #else
        background(.regularMaterial, in: Circle())
        #endif
    }
}
