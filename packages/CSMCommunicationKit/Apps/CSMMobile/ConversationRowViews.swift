import SwiftUI
import UIKit

struct ConversationSwipeActionsRow<Content: View>: View {
    var conversation: Conversation
    var isPinned: Bool
    var hasVisibleUnread: Bool
    var isMuted: Bool
    var onTogglePinned: () -> Void
    var onToggleUnread: () -> Void
    var onToggleMuted: () -> Void
    var onHide: () -> Void
    var onLeaveGroup: (() -> Void)?
    var content: Content

    init(
        conversation: Conversation,
        isPinned: Bool,
        hasVisibleUnread: Bool,
        isMuted: Bool,
        onTogglePinned: @escaping () -> Void,
        onToggleUnread: @escaping () -> Void,
        onToggleMuted: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onLeaveGroup: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.conversation = conversation
        self.isPinned = isPinned
        self.hasVisibleUnread = hasVisibleUnread
        self.isMuted = isMuted
        self.onTogglePinned = onTogglePinned
        self.onToggleUnread = onToggleUnread
        self.onToggleMuted = onToggleMuted
        self.onHide = onHide
        self.onLeaveGroup = onLeaveGroup
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    onTogglePinned()
                } label: {
                    Label(
                        isPinned
                            ? CSMLocalization.text("conversation.action.unpin.short", fallback: "Odepnout")
                            : CSMLocalization.text("conversation.action.pin.short", fallback: "Připnout"),
                        systemImage: isPinned ? "pin.slash.fill" : "pin.fill"
                    )
                }
                .tint(CSMTheme.warningAmber)
                .accessibilityLabel(isPinned
                    ? CSMLocalization.text("conversation.action.unpin_named", fallback: "Odepnout %@", conversation.title)
                    : CSMLocalization.text("conversation.action.pin_named", fallback: "Připnout %@", conversation.title))

                Button {
                    onToggleUnread()
                } label: {
                    Label(
                        hasVisibleUnread
                            ? CSMLocalization.text("conversation.action.read.short", fallback: "Přečtené")
                            : CSMLocalization.text("conversation.action.unread.short", fallback: "Nepřečtené"),
                        systemImage: hasVisibleUnread ? "envelope.open.fill" : "envelope.badge.fill"
                    )
                }
                .tint(CSMTheme.signalBlue)
                .accessibilityLabel(hasVisibleUnread
                    ? CSMLocalization.text("conversation.action.mark_read_named", fallback: "Označit %@ jako přečtené", conversation.title)
                    : CSMLocalization.text("conversation.action.mark_unread_named", fallback: "Označit %@ jako nepřečtené", conversation.title))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if conversation.type == .group, let onLeaveGroup {
                    Button(role: .destructive) {
                        onLeaveGroup()
                    } label: {
                        Label(
                            CSMLocalization.text("conversation.action.leave_group", fallback: "Opustit skupinu"),
                            systemImage: "rectangle.portrait.and.arrow.right"
                        )
                    }
                    .accessibilityLabel(CSMLocalization.text("conversation.action.leave_group_named", fallback: "Opustit skupinu %@", conversation.title))
                }

                Button {
                    onHide()
                } label: {
                    Label(
                        hideActionTitle,
                        systemImage: "archivebox.fill"
                    )
                }
                .tint(Color(uiColor: .systemGray))
                .accessibilityLabel(CSMLocalization.text("conversation.action.hide_named", fallback: "Skrýt %@", conversation.title))

                Button {
                    onToggleMuted()
                } label: {
                    Label(
                        isMuted
                            ? CSMLocalization.text("conversation.action.notifications_on.short", fallback: "Zapnout")
                            : CSMLocalization.text("conversation.action.mute.short", fallback: "Ztlumit"),
                        systemImage: isMuted ? "bell.fill" : "bell.slash.fill"
                    )
                }
                .tint(Color(uiColor: .systemGray))
                .accessibilityLabel(isMuted
                    ? CSMLocalization.text("conversation.action.notifications_on_named", fallback: "Zapnout oznámení %@", conversation.title)
                    : CSMLocalization.text("conversation.action.mute_named", fallback: "Ztlumit oznámení %@", conversation.title))
            }
        .accessibilityIdentifier("chat.conversationRow.\(conversation.title)")
        .accessibilityAction(
            named: isPinned
                ? CSMLocalization.text("conversation.action.unpin", fallback: "Odepnout konverzaci")
                : CSMLocalization.text("conversation.action.pin", fallback: "Připnout konverzaci")
        ) {
            onTogglePinned()
        }
        .accessibilityAction(
            named: hasVisibleUnread
                ? CSMLocalization.text("conversation.action.mark_read", fallback: "Označit jako přečtené")
                : CSMLocalization.text("conversation.action.mark_unread", fallback: "Označit jako nepřečtené")
        ) {
            onToggleUnread()
        }
        .accessibilityAction(
            named: isMuted
                ? CSMLocalization.text("conversation.action.notifications_on", fallback: "Zapnout oznámení")
                : CSMLocalization.text("conversation.action.mute", fallback: "Ztlumit oznámení")
        ) {
            onToggleMuted()
        }
        .accessibilityAction(named: CSMLocalization.text("conversation.action.hide", fallback: "Skrýt konverzaci")) {
            onHide()
        }
    }

    private var hideActionTitle: String {
        switch conversation.type {
        case .direct:
            CSMLocalization.text("conversation.action.hide_direct", fallback: "Skrýt chat")
        case .group:
            CSMLocalization.text("conversation.action.hide_group", fallback: "Skrýt ze seznamu")
        }
    }
}

struct ConversationRow: View {
    var conversation: Conversation
    var isSelected = false
    var isPinned = false
    var hasUnread = false
    var unreadCount = 0
    var isMuted = false
    var isManuallyUnread = false

    var body: some View {
        HStack(spacing: 11) {
            ConversationAvatar(
                title: conversation.title,
                type: conversation.type,
                tint: rowTint,
                size: 48,
                avatarDataUrl: conversation.avatarDataUrl,
                avatarRemoteUrl: conversation.avatarUrl,
                symbolOverride: conversation.isAIAssistantConversation ? "shield.lefthalf.filled" : nil,
                hasUnread: hasUnread,
                isMuted: isMuted,
                showsUnreadIndicator: false,
                showsTypeBadge: false
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(conversation.title)
                        .font(.body.weight(hasUnread ? .bold : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(CSMLocalization.text("conversation.row.muted", fallback: "Ztlumeno"))
                    } else if isManuallyUnread {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(CSMTheme.signalBlue)
                            .accessibilityLabel(CSMLocalization.text("conversation.row.manual_unread", fallback: "Ručně označeno jako nepřečtené"))
                    }
                    Spacer(minLength: 8)
                    if !updatedText.isEmpty {
                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(hasUnread && !isMuted ? CSMTheme.signalBlue : .secondary)
                    }
                    if hasUnread && !isMuted {
                        Circle()
                            .fill(CSMTheme.signalBlue)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                }

                HStack(spacing: 6) {
                    Text(subtitle)
                        .font(.subheadline.weight(hasUnread ? .semibold : .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            rowBackground,
            in: RoundedRectangle(cornerRadius: CSMTheme.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CSMTheme.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? CSMTheme.signalBlue.opacity(0.24) : Color.clear, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var rowTint: Color {
        conversation.type == .group ? CSMTheme.signalBlue : CSMTheme.relayCyan
    }

    private var updatedText: String {
        guard let date = conversation.lastActivityAt ?? conversation.updatedAt else { return "" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) {
            return CSMLocalization.text("conversation.date.yesterday", fallback: "Včera")
        }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day,
           days > 0,
           days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    private var subtitle: String {
        if let preview = conversation.lastActivityPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
            return preview
        }
        var parts = [
            conversation.type == .group
                ? CSMLocalization.text("conversation.kind.group", fallback: "Skupina")
                : CSMLocalization.text("conversation.kind.direct", fallback: "Přímá zpráva"),
            memberText
        ]
        if conversation.mapLinkCount > 0 {
            parts.append(
                conversation.mapLinkCount == 1
                    ? CSMLocalization.text("conversation.map.context.one", fallback: "mapový kontext")
                    : CSMLocalization.text("conversation.map.context.many", fallback: "%d mapové prvky", conversation.mapLinkCount)
            )
        }
        return parts.joined(separator: " • ")
    }

    private var memberText: String {
        let count = max(conversation.memberCount, conversation.members.count)
        if count == 1 { return CSMLocalization.text("conversation.member.one", fallback: "1 člen") }
        if count > 1 && count < 5 {
            return CSMLocalization.text("conversation.member.few", fallback: "%d členové", count)
        }
        return CSMLocalization.text("conversation.member.many", fallback: "%d členů", count)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color(uiColor: .tertiarySystemFill)
        }
        return Color.clear
    }

    private var accessibilityText: String {
        var parts = [conversation.title, subtitle]
        if isMuted {
            parts.append(CSMLocalization.text("conversation.accessibility.muted_part", fallback: "ztlumeno"))
        }
        if hasUnread {
            parts.append(
                unreadCount == 1
                    ? CSMLocalization.text("conversation.accessibility.new_message.one", fallback: "1 nová zpráva")
                    : CSMLocalization.text("conversation.accessibility.new_message.many", fallback: "%d nových zpráv", unreadCount)
            )
        }
        return parts.joined(separator: ", ")
    }
}

private struct ConversationUnreadBadge: View {
    var count: Int

    var body: some View {
        Text(displayCount)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .frame(minWidth: 20, minHeight: 20)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .background(CSMTheme.signalBlue, in: Capsule())
            .accessibilityHidden(true)
    }

    private var displayCount: String {
        count > 99 ? "99+" : "\(max(1, count))"
    }
}

struct PinnedConversationCard: View {
    var conversation: Conversation
    var messagingTrust: MessagingTrustPresentation
    var hasUnread = false
    var unreadCount = 0
    var isMuted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ConversationAvatar(
                    title: conversation.title,
                    type: conversation.type,
                    tint: CSMTheme.warningAmber,
                    size: 54,
                    avatarDataUrl: conversation.avatarDataUrl,
                    avatarRemoteUrl: conversation.avatarUrl,
                    symbolOverride: conversation.avatarDataUrl == nil && conversation.avatarUrl == nil ? "star.fill" : nil,
                    hasUnread: hasUnread,
                    isMuted: isMuted
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(CSMLocalization.text("conversation.row.muted", fallback: "Ztlumeno"))
                } else if hasUnread {
                    ConversationUnreadBadge(count: unreadCount)
                }
            }

            Label(CSMLocalization.text("conversation.pinned.continue", fallback: "Pokračovat v připnuté konverzaci"), systemImage: "arrow.right.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CSMTheme.warningAmber)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(CSMTheme.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .csmGlassSurface(tint: CSMTheme.warningAmber, cornerRadius: CSMTheme.cardRadius, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.pinnedConversationCard")
    }

    private var subtitle: String {
        let memberText = conversation.memberCount == 1
            ? CSMLocalization.text("conversation.member.one", fallback: "1 člen")
            : CSMLocalization.text("conversation.member.many", fallback: "%d členů", conversation.memberCount)
        if hasUnread {
            let unreadText = Self.unreadText(unreadCount)
            if let preview = conversation.lastActivityPreview?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                return CSMLocalization.text("conversation.pinned.unread.with_preview", fallback: "%@. %@", unreadText, preview)
            }
            return CSMLocalization.text("conversation.pinned.unread.with_members", fallback: "%@. %@.", unreadText, memberText)
        }
        if isMuted {
            return CSMLocalization.text("conversation.pinned.muted.subtitle", fallback: "%@. Oznámení jsou ztlumená.", memberText)
        }
        if messagingTrust.isQueueOnly {
            return CSMLocalization.text(
                "conversation.pinned.queue.subtitle",
                fallback: "%@. Zprávy se odešlou po obnovení bezpečného spojení.",
                memberText
            )
        }
        if messagingTrust.blocksSending {
            return CSMLocalization.text("conversation.pinned.blocked.subtitle", fallback: "%@. Chat se připravuje.", memberText)
        }
        if conversation.mapLinkCount > 0 {
            return CSMLocalization.text("conversation.pinned.map.subtitle", fallback: "%@. Má související mapový kontext.", memberText)
        }
        return CSMLocalization.text("conversation.pinned.default.subtitle", fallback: "%@. Rychlý návrat do nejdůležitější skupiny.", memberText)
    }

    private static func unreadText(_ count: Int) -> String {
        if count == 1 { return CSMLocalization.text("conversation.unread.one", fallback: "1 nová zpráva") }
        if count > 1 && count < 5 {
            return CSMLocalization.text("conversation.unread.few", fallback: "%d nové zprávy", count)
        }
        return CSMLocalization.text("conversation.unread.many", fallback: "%d nových zpráv", count)
    }
}

struct ConversationAvatar: View {
    var title: String
    var type: ConversationType
    var tint: Color
    var size: CGFloat
    var avatarDataUrl: String? = nil
    var avatarRemoteUrl: String? = nil
    var symbolOverride: String? = nil
    var hasUnread = false
    var isMuted = false
    var showsUnreadIndicator = true
    var showsTypeBadge = true

    var body: some View {
        CSMAvatarImageView(dataUrl: avatarDataUrl, remoteUrl: avatarRemoteUrl, size: size) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.16))
                if let symbolOverride {
                    Image(systemName: symbolOverride)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(tint)
                } else {
                    Text(initials)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(tint)
                }
            }
        }
        .overlay {
            if showsUnreadIndicator && hasUnread && !isMuted {
                Circle()
                    .strokeBorder(CSMTheme.signalBlue.opacity(0.86), lineWidth: 2)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsUnreadIndicator && hasUnread && !isMuted {
                Circle()
                    .fill(CSMTheme.signalBlue)
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                    }
                    .offset(x: 2, y: -1)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsTypeBadge {
                Image(systemName: type == .group ? "person.2.fill" : "person.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(tint, in: Circle())
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = title
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let value: String
        if words.count >= 2 {
            value = words.prefix(2).compactMap(\.first).map(String.init).joined()
        } else {
            value = String(title.prefix(2))
        }
        return value.uppercased()
    }
}
