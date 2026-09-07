import SwiftUI
import UIKit

struct ConversationInboxSearchField: View {
    @Binding var text: String
    var placeholder = CSMLocalization.text("conversation.search.short", fallback: "Hledat")

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel(CSMLocalization.text("conversation.search.placeholder", fallback: "Hledat konverzace"))
                .accessibilityIdentifier("chat.conversationSearch")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(CSMLocalization.text("conversation.search.clear", fallback: "Vymazat hledání"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

struct ConversationListSectionHeader: View {
    var title: String
    var actionTitle: String?
    var showsSecureState = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.primary)

            if showsSecureState {
                Label(
                    CSMLocalization.text("conversation.secure.short", fallback: "Zabezpečeno"),
                    systemImage: "lock.fill"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CSMTheme.secureGreen)
                .labelStyle(.iconOnly)
                .accessibilityLabel(CSMLocalization.text("conversation.secure", fallback: "Zabezpečený chat"))
            }

            Spacer(minLength: 8)

            if let actionTitle, let onAction {
                Button(actionTitle, action: onAction)
                    .font(.subheadline)
                    .textCase(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

struct ConversationBottomSearchBar: View {
    @Binding var text: String
    var onCreateDirect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ConversationInboxSearchField(text: $text)
                .frame(maxWidth: .infinity)

            Button(action: onCreateDirect) {
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(CSMLocalization.text("conversation.create.direct", fallback: "Nová zpráva"))
            .accessibilityIdentifier("chat.createDirect")
        }
        .padding(.horizontal, 16)
        .padding(.top, 7)
        .padding(.bottom, 9)
        .background(.bar)
    }
}

struct QuickAccessConversationBubble: View {
    var conversation: Conversation
    var isSelected = false
    var isPinned = false
    var hasUnread = false
    var isMuted = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ConversationAvatar(
                    title: conversation.title,
                    type: conversation.type,
                    tint: tint,
                    size: 64,
                    avatarDataUrl: conversation.avatarDataUrl,
                    avatarRemoteUrl: conversation.avatarUrl,
                    hasUnread: hasUnread,
                    isMuted: isMuted,
                    showsUnreadIndicator: false,
                    showsTypeBadge: false
                )
                if isPinned {
                    Image(systemName: "star.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(CSMTheme.warningAmber, in: Circle())
                        .offset(x: 5, y: -3)
                        .accessibilityHidden(true)
                }
                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(.thinMaterial, in: Circle())
                        .offset(x: isPinned ? -13 : 4, y: isPinned ? -3 : -2)
                        .accessibilityHidden(true)
                }
            }

            Text(conversation.title)
                .font(.caption.weight(hasUnread ? .bold : .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(width: 82)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .background(
            isSelected ? tint.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.30) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var tint: Color {
        if isPinned {
            return CSMTheme.warningAmber
        }
        return conversation.type == .group ? CSMTheme.signalBlue : CSMTheme.relayCyan
    }

    private var accessibilityText: String {
        var parts = [conversation.title]
        if isPinned {
            parts.append(CSMLocalization.text("conversation.accessibility.pinned_part", fallback: "připnutá konverzace"))
        }
        if isMuted {
            parts.append(CSMLocalization.text("conversation.accessibility.muted_part", fallback: "ztlumeno"))
        } else if hasUnread {
            let count = max(conversation.unreadCount, 1)
            parts.append(
                count == 1
                    ? CSMLocalization.text("conversation.accessibility.new_message.one", fallback: "1 nová zpráva")
                    : CSMLocalization.text("conversation.accessibility.new_message.many", fallback: "%d nových zpráv", count)
            )
        }
        return parts.joined(separator: ", ")
    }
}

struct FavoriteConversationAddBubble: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus")
                .font(.title2.weight(.medium))
                .foregroundStyle(CSMTheme.signalBlue)
                .frame(width: 64, height: 64)
                .background {
                    Circle()
                        .strokeBorder(
                            Color.secondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                        )
                }

            Text(CSMLocalization.text("conversation.favorites.add.short", fallback: "Přidat"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 96)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(CSMLocalization.text("conversation.favorites.add", fallback: "Přidat do oblíbených"))
    }
}

struct EmptyConversationState: View {
    var onCreateDirect: () -> Void
    var onCreateGroup: () -> Void
    var onCreateAI: () -> Void
    var isOpeningAI: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                CSMLocalization.text("conversation.empty.title", fallback: "Napište první zprávu"),
                systemImage: "bubble.left.and.bubble.right"
            )
        } description: {
            Text(CSMLocalization.text(
                "conversation.empty.description",
                fallback: "Vyberte kolegu, vytvořte skupinu nebo začněte chat s AI."
            ))
        } actions: {
            VStack(spacing: 10) {
                ConversationActionButton(
                    title: CSMLocalization.text("conversation.create.direct", fallback: "Nová zpráva"),
                    systemImage: "square.and.pencil",
                    tint: CSMTheme.signalBlue,
                    action: onCreateDirect
                )
                ConversationActionButton(
                    title: CSMLocalization.text("conversation.create.group", fallback: "Nová skupina"),
                    systemImage: "person.3.fill",
                    tint: CSMTheme.relayCyan,
                    action: onCreateGroup
                )
                ConversationActionButton(
                    title: isOpeningAI
                        ? CSMLocalization.text("conversation.create.ai.opening", fallback: "Otevírám AI chat")
                        : CSMLocalization.text("conversation.create.ai", fallback: "Chat s AI agentem"),
                    systemImage: "shield.lefthalf.filled",
                    tint: CSMTheme.secureGreen,
                    action: onCreateAI
                )
                .disabled(isOpeningAI)
                .accessibilityIdentifier("chat.empty.openAI")
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityIdentifier("chat.emptyConversationState")
    }
}

struct ConversationLoadFailureState: View {
    var onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                CSMLocalization.text("conversation.list.unavailable.title", fallback: "Zprávy teď nelze načíst"),
                systemImage: "wifi.exclamationmark"
            )
        } description: {
            Text(CSMLocalization.text(
                "conversation.list.unavailable.message",
                fallback: "Zkontrolujte připojení a zkuste to znovu."
            ))
        } actions: {
            Button(action: onRetry) {
                Label(CSMLocalization.text("common.retry", fallback: "Zkusit znovu"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityIdentifier("chat.conversationLoadFailure")
    }
}

private struct ConversationActionButton: View {
    var title: String
    var systemImage: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: CSMTheme.controlRadius, style: .continuous))
        .csmGlassSurface(tint: tint, cornerRadius: CSMTheme.controlRadius, interactive: true)
        .accessibilityIdentifier(title == CSMLocalization.text("conversation.create.group", fallback: "Nová skupina") ? "chat.createGroup" : "chat.createDirect")
    }
}
