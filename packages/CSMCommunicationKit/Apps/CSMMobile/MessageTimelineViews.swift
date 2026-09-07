import Observation
import SwiftUI
import UIKit

struct MessageDayDivider: View {
    var date: Date

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .accessibilityIdentifier("chat.messageDayDivider")
            .accessibilityLabel(CSMLocalization.text("message.timeline.from", fallback: "Zprávy z %@", label))
    }

    private var label: String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) {
            return "\(CSMLocalization.text("message.timeline.today", fallback: "Dnes")) \(time)"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "\(CSMLocalization.text("message.timeline.yesterday", fallback: "Včera")) \(time)"
        }
        return "\(date.formatted(.dateTime.day().month(.wide).year())) \(time)"
    }
}

enum MessageGroupPosition: Equatable, Sendable {
    case single
    case first
    case middle
    case last

    var isFirstInGroup: Bool {
        self == .single || self == .first
    }

    var isLastInGroup: Bool {
        self == .single || self == .last
    }
}

struct ChatTimelinePresentation: Sendable {
    var messages: [ChatMessage]
    var searchableMessages: [ChatMessage]
    var rows: [TimelineMessageRow]

    static let empty = ChatTimelinePresentation(
        messages: [],
        searchableMessages: [],
        rows: []
    )

    static func make(
        messages: [ChatMessage],
        voiceCallMessages: [ChatMessage],
        searchText: String,
        matchingMessageIDs: Set<String>? = nil
    ) -> ChatTimelinePresentation {
        let query = normalizedQuery(searchText)
        let sortedMessages = (messages + voiceCallMessages).sorted(by: messageSort)
        let matchesQuery: (ChatMessage) -> Bool = { message in
            if let matchingMessageIDs {
                return matchingMessageIDs.contains(message.id)
            }
            return matches(message, query: query)
        }
        let searchableMessages = query.isEmpty
            ? []
            : messages.filter(matchesQuery).sorted(by: messageSort)
        let visibleMessages = query.isEmpty
            ? sortedMessages
            : sortedMessages.filter(matchesQuery)

        return ChatTimelinePresentation(
            messages: visibleMessages,
            searchableMessages: searchableMessages,
            rows: TimelineMessageRow.makeRows(from: visibleMessages)
        )
    }

    private static func normalizedQuery(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func matches(_ message: ChatMessage, query: String) -> Bool {
        message.body.lowercased().contains(query) ||
            message.senderDisplayName.lowercased().contains(query) ||
            message.attachments.contains { $0.title.lowercased().contains(query) } ||
            message.replyTo?.bodyPreview.lowercased().contains(query) == true
    }

    private static func messageSort(_ left: ChatMessage, _ right: ChatMessage) -> Bool {
        if left.sentAt == right.sentAt {
            return left.id < right.id
        }
        return left.sentAt < right.sentAt
    }
}

struct TimelineMessageRow: Identifiable, Sendable {
    var message: ChatMessage
    var position: MessageGroupPosition
    var showsDateDivider: Bool
    var showsSender: Bool
    var showsAvatar: Bool
    var topSpacing: CGFloat

    var id: String { message.id }

    static func makeRows(from messages: [ChatMessage]) -> [TimelineMessageRow] {
        messages.indices.map { index in
            let message = messages[index]
            let previous = index > messages.startIndex ? messages[messages.index(before: index)] : nil
            let next = index < messages.index(before: messages.endIndex) ? messages[messages.index(after: index)] : nil
            let groupedWithPrevious = previous.map { belongsToSameVisualGroup($0, message) } ?? false
            let groupedWithNext = next.map { belongsToSameVisualGroup(message, $0) } ?? false
            let showsDateDivider = previous.map {
                !Calendar.current.isDate($0.sentAt, inSameDayAs: message.sentAt)
            } ?? true

            return TimelineMessageRow(
                message: message,
                position: position(groupedWithPrevious: groupedWithPrevious, groupedWithNext: groupedWithNext),
                showsDateDivider: showsDateDivider,
                showsSender: !message.presentationIsOwnMessage && !groupedWithPrevious,
                showsAvatar: !message.presentationIsOwnMessage && !groupedWithNext,
                topSpacing: showsDateDivider ? 10 : (groupedWithPrevious ? 1 : 12)
            )
        }
    }

    private static func position(
        groupedWithPrevious: Bool,
        groupedWithNext: Bool
    ) -> MessageGroupPosition {
        switch (groupedWithPrevious, groupedWithNext) {
        case (false, false):
            return .single
        case (false, true):
            return .first
        case (true, true):
            return .middle
        case (true, false):
            return .last
        }
    }

    private static func belongsToSameVisualGroup(_ first: ChatMessage, _ second: ChatMessage) -> Bool {
        guard first.presentationSenderId == second.presentationSenderId,
              first.presentationIsOwnMessage == second.presentationIsOwnMessage,
              Calendar.current.isDate(first.sentAt, inSameDayAs: second.sentAt) else {
            return false
        }
        return abs(second.sentAt.timeIntervalSince(first.sentAt)) <= 5 * 60
    }
}

struct ChatTimelinePresentationKey: Hashable, Sendable {
    var timelineRevision: UInt64
    var searchText: String
    var matchingMessageIDs: [String]
}

/// Screen-owned presentation cache. Row grouping and search projection are
/// prepared only when the timeline revision or query changes, never on an
/// unrelated SwiftUI body evaluation.
@MainActor
@Observable
final class ChatTimelinePresentationStore {
    private(set) var presentation = ChatTimelinePresentation.empty
    private var currentKey: ChatTimelinePresentationKey?

    func update(
        key: ChatTimelinePresentationKey,
        messages: [ChatMessage],
        voiceCallMessages: [ChatMessage]
    ) async {
        guard currentKey != key else { return }
        let query = key.searchText
        let matchingIDs = query.isEmpty ? nil : Set(key.matchingMessageIDs)
        let next = await Task.detached(priority: .userInitiated) {
            ChatPerformance.measure(
                "timeline-presentation",
                budgetMilliseconds: ChatPerformanceBudget.interactionMilliseconds
            ) {
                ChatTimelinePresentation.make(
                    messages: messages,
                    voiceCallMessages: voiceCallMessages,
                    searchText: query,
                    matchingMessageIDs: matchingIDs
                )
            }
        }.value
        guard !Task.isCancelled else { return }
        currentKey = key
        presentation = next
    }

    func reset() {
        currentKey = nil
        presentation = .empty
    }
}

enum MessageReplySwipePolicy {
    static let replyThreshold: CGFloat = 64
    static let maximumOffset: CGFloat = 76
    static let horizontalDominance: CGFloat = 1.35

    static func dragOffset(for translation: CGSize) -> CGFloat {
        guard translation.width > 0,
              translation.width > abs(translation.height) else {
            return 0
        }
        return min(maximumOffset, translation.width)
    }

    static func shouldReply(for translation: CGSize) -> Bool {
        translation.width > replyThreshold &&
            translation.width > abs(translation.height) * horizontalDominance
    }
}

enum TimelineScrollPolicy {
    static func shouldFollowLatest(
        previousVisibleMessageCount: Int,
        currentVisibleMessageCount: Int,
        isAtBottom: Bool,
        lastMessageIsOwn: Bool
    ) -> Bool {
        guard currentVisibleMessageCount > 0 else { return false }
        return previousVisibleMessageCount == 0 || isAtBottom || lastMessageIsOwn
    }
}

struct TimelineViewportKey: Hashable, Sendable {
    var firstMessageID: String?
    var lastMessageID: String?
    var count: Int

    init(rows: [TimelineMessageRow]) {
        firstMessageID = rows.first?.id
        lastMessageID = rows.last?.id
        count = rows.count
    }
}

struct MessageBubble: View {
    var message: ChatMessage
    var groupPosition: MessageGroupPosition = .single
    var showsSender = true
    var showsAvatar = true
    var senderAvatarDataUrl: String?
    var senderAvatarRemoteUrl: String?
    var searchText: String = ""
    var onReply: () -> Void = {}
    var isSelectionMode = false
    var isSelected = false
    var isActiveSearchMatch = false
    var onToggleSelection: () -> Void = {}
    var onReact: (String) -> Void = { _ in }
    var onOpenAttachment: (MessageAttachment) -> Void = { _ in }
    var onShowActions: () -> Void = {}
    @State private var horizontalDrag: CGFloat = 0
    private let quickReactions = ["❤️", "👍", "👎", "‼️", "❓", "🤣", "😀"]

    var body: some View {
        HStack(alignment: .bottom, spacing: 7) {
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isSelected ? CSMTheme.signalBlue : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isSelected
                        ? CSMLocalization.text("message.selection.cancel", fallback: "Zrušit výběr zprávy")
                        : CSMLocalization.text("message.selection.select", fallback: "Vybrat zprávu")
                )
            }

            if message.presentationIsOwnMessage {
                Spacer(minLength: 48)
            } else {
                MessageSenderAvatar(
                    name: message.presentationSenderDisplayName,
                    avatarDataUrl: senderAvatarDataUrl,
                    avatarRemoteUrl: senderAvatarRemoteUrl,
                    isVisible: showsAvatar
                )
            }
            VStack(alignment: .leading, spacing: 6) {
                if showsSender {
                    Text(message.presentationSenderDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if message.isPinned {
                        Label(CSMLocalization.text("message.pinned", fallback: "Připnuto"), systemImage: "pin.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.84) : CSMTheme.warningAmber)
                    }
                    if message.isDeleted {
                        Label(CSMLocalization.text("message.deleted", fallback: "Zpráva byla smazána"), systemImage: "nosign")
                            .font(.subheadline.italic())
                            .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.72) : .secondary)
                    } else if let replyTo = message.replyTo {
                        ReplyReferenceView(reply: replyTo, isOwnMessage: message.presentationIsOwnMessage)
                    }
                    if !message.isDeleted && !message.presentationBody.isEmpty {
                        Text(message.presentationBody)
                            .font(.body)
                            .foregroundStyle(message.presentationIsOwnMessage ? .white : .primary)
                    }
                    if !message.isDeleted {
                        ForEach(message.attachments) { attachment in
                            MessageAttachmentChip(
                                attachment: attachment,
                                isOwnMessage: message.presentationIsOwnMessage,
                                onOpen: {
                                    onOpenAttachment(attachment)
                                }
                            )
                        }
                    }
                    if showsMetadataRow {
                        HStack(spacing: 4) {
                            Text(message.sentAt, style: .time)
                            if message.presentationIsOwnMessage || message.deliveryState == .failed || message.deliveryState == .pending {
                                Image(systemName: deliverySymbol)
                            }
                            if showsDeliveryLabel {
                                Text(deliveryLabel)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.72) : .secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 430, alignment: .leading)
                .background(
                    message.presentationIsOwnMessage ? CSMTheme.signalBlue : Color(uiColor: .systemGray5),
                    in: bubbleShape
                )
                .overlay {
                    bubbleShape
                        .stroke(bubbleStrokeColor, lineWidth: isSelected || isActiveSearchMatch ? 2 : 1)
                }
                .contentShape(bubbleShape)
                .overlay(alignment: message.presentationIsOwnMessage ? .bottomTrailing : .bottomLeading) {
                    if !message.isDeleted && !message.reactions.isEmpty {
                        MessageReactionStrip(reactions: message.reactions, isOwnMessage: message.presentationIsOwnMessage)
                            .offset(x: message.presentationIsOwnMessage ? -14 : 14, y: 12)
                    }
                }
                .padding(.bottom, message.reactions.isEmpty ? 0 : 12)
                .overlay(alignment: .leading) {
                    if horizontalDrag > 8, !message.isDeleted {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CSMTheme.signalBlue)
                            .frame(width: 30, height: 30)
                            .background(.thinMaterial, in: Circle())
                            .offset(x: -40)
                            .opacity(min(1, horizontalDrag / 46))
                    }
                }
                .offset(x: replyDragOffset)
                .simultaneousGesture(replyGesture)
                .onTapGesture {
                    if isSelectionMode {
                        onToggleSelection()
                    }
                }
                .contextMenu {
                    if !isSelectionMode {
                        messageContextMenu
                    }
                }
                .accessibilityAction(
                    named: Text(CSMLocalization.text("message.action.reply", fallback: "Odpovědět"))
                ) {
                    guard !message.isDeleted else { return }
                    onReply()
                }
                .accessibilityAction(
                    named: Text(CSMLocalization.text("message.action.more", fallback: "Další akce"))
                ) {
                    onShowActions()
                }
            }

            if !message.presentationIsOwnMessage {
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.presentationIsOwnMessage ? .trailing : .leading)
        .animation(.snappy, value: isSelectionMode)
        .animation(.snappy, value: isSelected)
        .animation(.snappy, value: isActiveSearchMatch)
    }

    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(
            isOwnMessage: message.presentationIsOwnMessage,
            showsTail: groupPosition.isLastInGroup
        )
    }

    private var replyDragOffset: CGFloat {
        guard !message.isDeleted, !isSelectionMode else { return 0 }
        return horizontalDrag
    }

    private var replyGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard !message.isDeleted, !isSelectionMode else { return }
                horizontalDrag = MessageReplySwipePolicy.dragOffset(for: value.translation)
            }
            .onEnded { value in
                defer {
                    withAnimation(.snappy) {
                        horizontalDrag = 0
                    }
                }
                guard !message.isDeleted, !isSelectionMode else { return }
                guard MessageReplySwipePolicy.shouldReply(for: value.translation) else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onReply()
            }
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        if !message.isDeleted {
            Button {
                onReply()
            } label: {
                Label(
                    CSMLocalization.text("message.action.reply", fallback: "Odpovědět"),
                    systemImage: "arrowshape.turn.up.left"
                )
            }

            Menu {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                    }
                }
            } label: {
                Label(
                    CSMLocalization.text("message.action.react", fallback: "Reagovat"),
                    systemImage: "face.smiling"
                )
            }
        }

        if !message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !message.isDeleted {
            Button {
                UIPasteboard.general.string = message.presentationBody
            } label: {
                Label(
                    CSMLocalization.text("message.action.copy", fallback: "Zkopírovat"),
                    systemImage: "doc.on.doc"
                )
            }
        }

        if !message.isDeleted {
            Button {
                onToggleSelection()
            } label: {
                Label(
                    CSMLocalization.text("message.action.select", fallback: "Vybrat"),
                    systemImage: "checkmark.circle"
                )
            }
        }

        Button {
            onShowActions()
        } label: {
            Label(
                CSMLocalization.text("message.action.more", fallback: "Další akce"),
                systemImage: "ellipsis.circle"
            )
        }
    }

    private var deliverySymbol: String {
        switch message.deliveryState {
        case .pending: "clock"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle"
        case .read: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
        }
    }

    private var deliveryLabel: String {
        switch message.deliveryState {
        case .pending: CSMLocalization.text("message.delivery.pending", fallback: "čeká")
        case .sent: CSMLocalization.text("message.delivery.sent", fallback: "odesláno")
        case .delivered: CSMLocalization.text("message.delivery.delivered", fallback: "doručeno")
        case .read: CSMLocalization.text("message.delivery.read", fallback: "přečteno")
        case .failed: CSMLocalization.text("message.delivery.failed", fallback: "neodesláno")
        }
    }

    private var bubbleStrokeColor: Color {
        if isSelected {
            return CSMTheme.signalBlue.opacity(0.85)
        }
        if isActiveSearchMatch {
            return CSMTheme.warningAmber.opacity(0.95)
        }
        return .clear
    }

    private var showsDeliveryLabel: Bool {
        switch message.deliveryState {
        case .pending, .failed:
            return true
        case .sent, .delivered, .read:
            return false
        }
    }

    private var showsMetadataRow: Bool {
        message.presentationIsOwnMessage || groupPosition.isLastInGroup || message.deliveryState == .pending || message.deliveryState == .failed
    }
}

private struct MessageSenderAvatar: View {
    var name: String
    var avatarDataUrl: String?
    var avatarRemoteUrl: String?
    var isVisible: Bool

    var body: some View {
        ZStack {
            if isVisible {
                CSMAvatarImageView(dataUrl: avatarDataUrl, remoteUrl: avatarRemoteUrl, size: 28) {
                    ZStack {
                        Circle()
                            .fill(CSMTheme.relayCyan.opacity(0.16))
                        Text(initials)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CSMTheme.relayCyan)
                    }
                }
            }
        }
        .frame(width: 28, height: 28)
        .overlay {
            if isVisible {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name
            .split { !$0.isLetter && !$0.isNumber }
            .prefix(2)
            .compactMap(\.first)
        let value = String(words).uppercased()
        return value.isEmpty ? String(name.prefix(2)).uppercased() : value
    }
}

struct PinnedMessageBanner: View {
    var message: ChatMessage
    var additionalCount: Int
    var onOpen: () -> Void
    var onUnpin: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill")
                        .font(.headline)
                        .foregroundStyle(CSMTheme.warningAmber)
                        .frame(width: 28, height: 28)
                        .background(CSMTheme.warningAmber.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            additionalCount > 0
                                ? CSMLocalization.text("Připnuté zprávy", fallback: "Připnuté zprávy")
                                : CSMLocalization.text("Připnutá zpráva", fallback: "Připnutá zpráva")
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(previewText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if additionalCount > 0 {
                        Text("+\(additionalCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CSMTheme.signalBlue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(CSMTheme.signalBlue.opacity(0.12), in: Capsule())
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CSMLocalization.text("Otevřít připnutou zprávu", fallback: "Otevřít připnutou zprávu"))

            Button(action: onUnpin) {
                Image(systemName: "pin.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.secondary)
            .accessibilityLabel(CSMLocalization.text("Odepnout zprávu", fallback: "Odepnout zprávu"))
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CSMTheme.warningAmber.opacity(0.22), lineWidth: 1)
        }
    }

    private var previewText: String {
        if !message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message.presentationBody
        }
        if let attachment = message.attachments.first {
            return attachment.title
        }
        return CSMLocalization.text("message.preview.default", fallback: "Zpráva")
    }
}

struct MessageActionOverlay: View {
    var message: ChatMessage
    var onDismiss: () -> Void
    var onReply: () -> Void
    var onCopy: () -> Void
    var onReact: (String) -> Void
    var onSendSticker: (MessageStickerTemplate) -> Void
    var onTranslate: () async -> LocalAIMessageTranslation?
    var onForward: () -> Void
    var onSelect: () -> Void
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    @State private var showsExtendedReactions = false
    @State private var showsAdvancedActions = false
    @State private var showsStickerPicker = false
    @State private var translation: LocalAIMessageTranslation?
    @State private var isTranslating = false
    @State private var translationErrorText: String?
    @State private var actionContentFrame = CGRect.null

    private let quickReactions = ["❤️", "👍", "👎", "‼️", "❓", "🤣", "😀"]
    private let extendedReactions = ["🙏", "✅", "👀", "🔥", "⚠️", "📍", "⭐", "🚗", "🫡", "💪", "😢", "😮"]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black
                .opacity(0.22)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {
                    Spacer(minLength: 80)

                    VStack(spacing: 10) {
                        MessageActionPreviewBubble(message: message)

                        if !message.isDeleted {
                            reactionBar
                        }

                        actionMenu

                        if let translation {
                            MessageTranslationCard(translation: translation)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        } else if let translationErrorText {
                            MessageTranslationErrorCard(text: translationErrorText)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if !message.attachments.isEmpty && !message.isDeleted {
                            attachmentSummary
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MessageActionContentFramePreferenceKey.self,
                                value: proxy.frame(in: .named("message-action-overlay"))
                            )
                        }
                    }

                    Spacer(minLength: 128)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
        }
        .coordinateSpace(name: "message-action-overlay")
        .onPreferenceChange(MessageActionContentFramePreferenceKey.self) { frame in
            actionContentFrame = frame
        }
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named("message-action-overlay"))
                .onEnded { value in
                    guard !actionContentFrame.contains(value.location) else { return }
                    onDismiss()
                }
        )
        .sheet(isPresented: $showsStickerPicker) {
            MessageStickerPickerSheet { sticker in
                showsStickerPicker = false
                onSendSticker(sticker)
            }
        }
        .accessibilityIdentifier("chat.messageActionOverlay")
    }

    private var reactionBar: some View {
        VStack(alignment: message.presentationIsOwnMessage ? .trailing : .leading, spacing: 8) {
            HStack(spacing: 14) {
                ForEach(quickReactions, id: \.self) { emoji in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 27))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat.reaction.\(emoji)")
                    .accessibilityLabel(CSMLocalization.text("message.action.react", fallback: "Reagovat %@", emoji))
                }

                Divider()
                    .frame(height: 26)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) {
                        showsExtendedReactions.toggle()
                    }
                } label: {
                    Image(systemName: showsExtendedReactions ? "chevron.up.circle.fill" : "face.smiling")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CSMLocalization.text("message.action.more_reactions", fallback: "Další reakce"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.26), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

            if showsExtendedReactions {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 8), count: 6), spacing: 8) {
                    ForEach(extendedReactions, id: \.self) { emoji in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onReact(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(width: 38, height: 38)
                                .background(Color.white.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.reaction.extended.\(emoji)")
                        .accessibilityLabel(CSMLocalization.text("message.action.react", fallback: "Reagovat %@", emoji))
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: message.presentationIsOwnMessage ? .topTrailing : .topLeading)))
            }
        }
        .frame(maxWidth: .infinity, alignment: message.presentationIsOwnMessage ? .trailing : .leading)
        .padding(.horizontal, 12)
    }

    private var actionMenu: some View {
        VStack(spacing: 0) {
            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.reply", fallback: "Odpovědět"),
                systemImage: "arrowshape.turn.up.left",
                isDisabled: message.isDeleted,
                action: onReply
            )
            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.add_sticker", fallback: "Přidat nálepku"),
                systemImage: "face.smiling",
                isDisabled: message.isDeleted
            ) {
                showsStickerPicker = true
            }

            MessageActionDivider()

            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.copy", fallback: "Zkopírovat"),
                systemImage: "doc.on.doc",
                isDisabled: message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.isDeleted,
                action: onCopy
            )
            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.translate", fallback: "Přeložit"),
                systemImage: "character.bubble",
                statusText: isTranslating ? CSMLocalization.text("common.working", fallback: "pracuji") : nil,
                isDisabled: message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || message.isDeleted || isTranslating
            ) {
                Task {
                    await translateSelectedMessage()
                }
            }
            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.select", fallback: "Vybrat"),
                systemImage: "checkmark.circle",
                isDisabled: message.isDeleted,
                action: onSelect
            )
            MessageActionMenuButton(
                title: CSMLocalization.text("message.action.more", fallback: "Další..."),
                systemImage: "ellipsis.circle",
                showsDisclosure: true,
                isExpanded: showsAdvancedActions
            ) {
                withAnimation(.snappy) {
                    showsAdvancedActions.toggle()
                }
            }

            if showsAdvancedActions {
                MessageActionDivider()

                MessageActionMenuButton(
                    title: CSMLocalization.text("message.action.forward", fallback: "Přeposlat"),
                    systemImage: "arrowshape.turn.up.forward",
                    isDisabled: message.isDeleted,
                    action: onForward
                )
                MessageActionMenuButton(
                    title: message.isPinned
                        ? CSMLocalization.text("message.action.unpin", fallback: "Odepnout zprávu")
                        : CSMLocalization.text("message.action.pin", fallback: "Připnout zprávu"),
                    systemImage: message.isPinned ? "pin.slash" : "pin",
                    isDisabled: message.isDeleted || !message.id.hasPrefix("$"),
                    action: onTogglePin
                )
                MessageActionMenuButton(
                    title: CSMLocalization.text("message.action.delete", fallback: "Odstranit zprávu"),
                    systemImage: "trash",
                    role: .destructive,
                    isDisabled: message.isDeleted,
                    action: onDelete
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: 326)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
        .frame(maxWidth: .infinity, alignment: message.presentationIsOwnMessage ? .trailing : .leading)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("chat.messageActionMenu")
    }

    private func translateSelectedMessage() async {
        await MainActor.run {
            isTranslating = true
            translationErrorText = nil
        }
        let result = await onTranslate()
        await MainActor.run {
            withAnimation(.snappy) {
                translation = result
                translationErrorText = result == nil
                    ? CSMLocalization.text("message.translation.unavailable", fallback: "Lokální překlad není dostupný pro tuto zprávu.")
                    : nil
                isTranslating = false
            }
        }
    }

    private var attachmentSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(message.attachments) { attachment in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(attachment.chatDetailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: attachment.chatSystemImageName)
                        .foregroundStyle(attachment.chatTint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 326, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(maxWidth: .infinity, alignment: message.presentationIsOwnMessage ? .trailing : .leading)
        .padding(.horizontal, 12)
    }
}

private struct MessageActionContentFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct MessageStickerTemplate: Identifiable, Hashable {
    enum Style: String, CaseIterable {
        case blue
        case green
        case amber
        case red
        case cyan

        var gradientColors: [UIColor] {
            switch self {
            case .blue:
                return [UIColor.systemBlue, UIColor.systemTeal]
            case .green:
                return [UIColor.systemGreen, UIColor.systemMint]
            case .amber:
                return [UIColor.systemOrange, UIColor.systemYellow]
            case .red:
                return [UIColor.systemRed, UIColor.systemPink]
            case .cyan:
                return [UIColor.systemCyan, UIColor.systemBlue]
            }
        }
    }

    var id: String
    var glyph: String
    var symbolName: String?
    var title: String
    var subtitle: String
    var style: Style

    init(
        id: String,
        glyph: String,
        title: String,
        subtitle: String,
        style: Style,
        symbolName: String? = nil
    ) {
        self.id = id
        self.glyph = glyph
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }

    static let builtIn: [MessageStickerTemplate] = [
        MessageStickerTemplate(id: "ok", glyph: "OK", title: "OK", subtitle: "Potvrzení", style: .blue),
        MessageStickerTemplate(id: "enroute", glyph: "→", title: "Na cestě", subtitle: "Jedu", style: .green, symbolName: "arrow.right"),
        MessageStickerTemplate(id: "need-help", glyph: "!", title: "Potřebuji pomoc", subtitle: "Priorita", style: .red, symbolName: "exclamationmark"),
        MessageStickerTemplate(id: "seen", glyph: "✓", title: "Vidím", subtitle: "Beru na vědomí", style: .cyan, symbolName: "checkmark"),
        MessageStickerTemplate(id: "wait", glyph: "…", title: "Čekám", subtitle: "Vyčkávám", style: .amber, symbolName: "ellipsis"),
        MessageStickerTemplate(id: "location", glyph: "⌖", title: "Pošlu polohu", subtitle: "Lokace", style: .green, symbolName: "location.fill")
    ]

    func messageAttachment() -> MessageAttachment {
        let asset = Self.renderedAsset(for: self)
        return MessageAttachment(
            kind: .sticker,
            title: title,
            mimeType: "image/png",
            payloadData: asset.pngData
        )
    }

    func previewImage() -> UIImage {
        Self.renderedAsset(for: self).image
    }

    private struct RenderedStickerAsset {
        var pngData: Data
        var image: UIImage
    }

    // Rendering stickers is intentionally cached because the picker is rebuilt frequently.
    private static let renderedAssets: [String: RenderedStickerAsset] = Dictionary(
        uniqueKeysWithValues: builtIn.map { sticker in
            (sticker.id, sticker.renderedStickerAsset())
        }
    )

    private static func renderedAsset(for sticker: MessageStickerTemplate) -> RenderedStickerAsset {
        renderedAssets[sticker.id] ?? sticker.renderedStickerAsset()
    }

    private func renderedStickerAsset() -> RenderedStickerAsset {
        let data = renderPNGData()
        return RenderedStickerAsset(pngData: data, image: UIImage(data: data) ?? UIImage())
    }

    private func renderPNGData() -> Data {
        let size = CGSize(width: 384, height: 384)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: rect.insetBy(dx: 18, dy: 18), cornerRadius: 76)
            path.addClip()

            let colors = style.gradientColors.map(\.cgColor) as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
            if let gradient {
                cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            UIColor.white.withAlphaComponent(0.16).setFill()
            UIBezierPath(ovalIn: CGRect(x: 42, y: 36, width: 108, height: 108)).fill()
            UIColor.white.withAlphaComponent(0.10).setFill()
            UIBezierPath(ovalIn: CGRect(x: 238, y: 244, width: 122, height: 122)).fill()

            let glyphRect = CGRect(x: 38, y: 74, width: size.width - 76, height: 154)
            drawPrimaryGlyph(in: glyphRect)

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            (title as NSString).draw(
                in: CGRect(x: 34, y: 242, width: size.width - 68, height: 54),
                withAttributes: centeredAttributes(titleAttributes)
            )

            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82)
            ]
            (subtitle as NSString).draw(
                in: CGRect(x: 34, y: 298, width: size.width - 68, height: 38),
                withAttributes: centeredAttributes(subtitleAttributes)
            )
        }
    }

    private func drawPrimaryGlyph(in rect: CGRect) {
        if let symbolName,
           let symbol = UIImage(
            systemName: symbolName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 122, weight: .black)
           )?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            let aspect = symbol.size.width / max(symbol.size.height, 1)
            let targetHeight = min(rect.height, 132)
            let targetWidth = min(rect.width, targetHeight * aspect)
            let targetRect = CGRect(
                x: rect.midX - targetWidth / 2,
                y: rect.midY - targetHeight / 2,
                width: targetWidth,
                height: targetHeight
            )
            symbol.draw(in: targetRect)
            return
        }

        let glyphAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: glyph.count <= 2 ? 142 : 112, weight: .black),
            .foregroundColor: UIColor.white
        ]
        (glyph as NSString).draw(
            in: rect,
            withAttributes: centeredAttributes(glyphAttributes)
        )
    }

    private func centeredAttributes(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        var values = attributes
        values[.paragraphStyle] = paragraph
        return values
    }
}

private struct MessageStickerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (MessageStickerTemplate) -> Void

    private let columns = [GridItem(.adaptive(minimum: 128), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(MessageStickerTemplate.builtIn) { sticker in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(sticker)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                Image(uiImage: sticker.previewImage())
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 96, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                Text(sticker.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(sticker.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(CSMLocalization.text("message.sticker.picker.title", fallback: "Nálepky"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CSMLocalization.text("common.cancel", fallback: "Zrušit")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MessageTranslationCard: View {
    var translation: LocalAIMessageTranslation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "character.bubble.fill")
                    .foregroundStyle(CSMTheme.relayCyan)
                Text(languageSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((translation.confidence * 100).rounded())) %")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(translation.translatedText)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Text(translation.safetyNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: 326, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CSMTheme.relayCyan.opacity(0.22), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("chat.messageTranslationCard")
    }

    private var languageSummary: String {
        "\(translation.sourceLanguageCode.uppercased()) → \(translation.targetLanguageCode.uppercased())"
    }
}

private struct MessageTranslationErrorCard: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CSMTheme.warningAmber)
            .padding(12)
            .frame(maxWidth: 326, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }
}

private struct MessageActionPreviewBubble: View {
    var message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.presentationIsOwnMessage {
                Spacer(minLength: 58)
            }

            VStack(alignment: .leading, spacing: 7) {
                if message.isPinned {
                    Label(CSMLocalization.text("message.pinned", fallback: "Připnuto"), systemImage: "pin.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.84) : CSMTheme.warningAmber)
                }

                if message.isDeleted {
                    Label(CSMLocalization.text("message.deleted", fallback: "Zpráva byla smazána"), systemImage: "nosign")
                        .font(.body.italic())
                        .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.72) : .secondary)
                } else if let replyTo = message.replyTo {
                    ReplyReferenceView(reply: replyTo, isOwnMessage: message.presentationIsOwnMessage)
                }

                if !message.isDeleted {
                    if !message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(message.presentationBody)
                            .font(.body)
                            .foregroundStyle(message.presentationIsOwnMessage ? .white : .primary)
                            .lineLimit(5)
                    } else if let attachment = message.attachments.first {
                        Label(attachment.title, systemImage: attachment.chatSystemImageName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(message.presentationIsOwnMessage ? .white : .primary)
                    }
                }

                if !message.isDeleted && !message.reactions.isEmpty {
                    MessageReactionStrip(reactions: message.reactions, isOwnMessage: message.presentationIsOwnMessage)
                }

                HStack(spacing: 4) {
                    Text(message.sentAt, style: .time)
                    if message.presentationIsOwnMessage || message.deliveryState == .pending || message.deliveryState == .failed {
                        Image(systemName: deliverySymbol)
                    }
                    if let deliveryLabel {
                        Text(deliveryLabel)
                    }
                }
                .font(.caption2)
                .foregroundStyle(message.presentationIsOwnMessage ? .white.opacity(0.72) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: 430, alignment: .leading)
            .background(message.presentationIsOwnMessage ? CSMTheme.signalBlue : Color(uiColor: .systemGray5), in: bubbleShape)
            .overlay {
                bubbleShape
                    .strokeBorder(Color.white.opacity(message.presentationIsOwnMessage ? 0.12 : 0.0), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 18, y: 8)

            if !message.presentationIsOwnMessage {
                Spacer(minLength: 58)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.presentationIsOwnMessage ? .trailing : .leading)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 20,
                bottomLeading: message.presentationIsOwnMessage ? 20 : 6,
                bottomTrailing: message.presentationIsOwnMessage ? 6 : 20,
                topTrailing: 20
            ),
            style: .continuous
        )
    }

    private var deliverySymbol: String {
        switch message.deliveryState {
        case .pending: "clock"
        case .sent: "checkmark"
        case .delivered: "checkmark.circle"
        case .read: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle"
        }
    }

    private var deliveryLabel: String? {
        switch message.deliveryState {
        case .pending:
            return CSMLocalization.text("message.delivery.pending", fallback: "čeká")
        case .failed:
            return CSMLocalization.text("message.delivery.failed", fallback: "neodesláno")
        case .sent, .delivered, .read:
            return nil
        }
    }
}

private struct MessageActionMenuButton: View {
    var title: String
    var systemImage: String
    var statusText: String?
    var role: ButtonRole?
    var showsDisclosure = false
    var isExpanded = false
    var isDisabled = false
    var action: () -> Void

    init(
        title: String,
        systemImage: String,
        statusText: String? = nil,
        role: ButtonRole? = nil,
        showsDisclosure: Bool = false,
        isExpanded: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.statusText = statusText
        self.role = role
        self.showsDisclosure = showsDisclosure
        self.isExpanded = isExpanded
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            guard !isDisabled else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 18) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.medium))
                    .frame(width: 30, height: 30)
                Text(title)
                    .font(.title3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
                if let statusText {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                if showsDisclosure {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.6) : foregroundColor)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        role == .destructive ? .red : .primary
    }
}

private struct MessageActionDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 70)
            .padding(.trailing, 18)
            .padding(.vertical, 4)
    }
}

struct ForwardMessageBundle: Identifiable {
    let id = UUID()
    var messages: [ChatMessage]
}

struct SelectedMessageAttachment: Identifiable {
    var attachment: MessageAttachment
    var messageId: String

    var id: String { "\(messageId):\(attachment.id)" }
}

struct ForwardMessageSheet: View {
    @Environment(\.dismiss) private var dismiss

    var messages: [ChatMessage]
    var conversations: [Conversation]
    var activeConversationId: String?
    var onForward: ([Conversation]) -> Void

    @State private var searchText = ""
    @State private var selectedConversationIds: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForwardMessagesPreview(messages: messages)
                }

                Section(CSMLocalization.text("message.forward.select_conversations", fallback: "Vybrat konverzace")) {
                    ForEach(filteredConversations) { conversation in
                        Button {
                            toggle(conversation)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: conversation.type == .group ? "person.3.fill" : "person.fill")
                                    .foregroundStyle(CSMTheme.signalBlue)
                                    .frame(width: 30, height: 30)
                                    .background(CSMTheme.signalBlue.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(conversation.title)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if conversation.conversationId == activeConversationId {
                                            Text(CSMLocalization.text("message.forward.current", fallback: "aktuální"))
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    Text(
                                        conversation.type == .group
                                            ? CSMLocalization.text("conversation.kind.group", fallback: "Skupina")
                                            : CSMLocalization.text("conversation.kind.direct", fallback: "Přímá zpráva")
                                    )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedConversationIds.contains(conversation.conversationId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedConversationIds.contains(conversation.conversationId) ? CSMTheme.secureGreen : .secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: CSMLocalization.text("message.forward.search", fallback: "Najít konverzaci"))
            .navigationTitle(CSMLocalization.text("message.action.forward", fallback: "Přeposlat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CSMLocalization.text("common.cancel", fallback: "Zrušit")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(CSMLocalization.text("message.forward.send", fallback: "Odeslat")) {
                        onForward(selectedConversations)
                        dismiss()
                    }
                    .disabled(selectedConversationIds.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.lowercased().contains(query) ||
                $0.members.contains { member in
                    member.displayName?.lowercased().contains(query) == true ||
                        member.userId.lowercased().contains(query)
                }
        }
    }

    private var selectedConversations: [Conversation] {
        conversations.filter { selectedConversationIds.contains($0.conversationId) }
    }

    private func toggle(_ conversation: Conversation) {
        if selectedConversationIds.contains(conversation.conversationId) {
            selectedConversationIds.remove(conversation.conversationId)
        } else {
            selectedConversationIds.insert(conversation.conversationId)
        }
    }
}

private struct ForwardMessagesPreview: View {
    var messages: [ChatMessage]

    var body: some View {
        if messages.count == 1, let message = messages.first {
            MessageActionPreview(message: message)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Label(summaryText, systemImage: "arrowshape.turn.up.forward.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(CSMTheme.signalBlue)

                ForEach(messages.prefix(4)) { message in
                    HStack(alignment: .top, spacing: 8) {
                                Image(systemName: previewSymbol(for: message))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.presentationSenderDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(previewText(for: message))
                                .font(.subheadline)
                                .lineLimit(2)
                        }
                    }
                }

                if messages.count > 4 {
                    Text(CSMLocalization.text("message.forward.more", fallback: "+%d dalších", messages.count - 4))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var summaryText: String {
        if messages.count > 1 && messages.count < 5 {
            return CSMLocalization.text("message.forward.count.few", fallback: "%d zprávy k přeposlání", messages.count)
        }
        return CSMLocalization.text("message.forward.count.many", fallback: "%d zpráv k přeposlání", messages.count)
    }

    private func previewText(for message: ChatMessage) -> String {
        if message.isDeleted {
            return CSMLocalization.text("message.forward.deleted", fallback: "Smazaná zpráva")
        }
        if !message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message.presentationBody
        }
        if let attachment = message.attachments.first {
            return attachment.title
        }
        return CSMLocalization.text("message.preview.default", fallback: "Zpráva")
    }

    private func previewSymbol(for message: ChatMessage) -> String {
        if message.isDeleted {
            return "nosign"
        }
        return message.attachments.first?.chatSystemImageName ?? "text.bubble.fill"
    }
}

private struct MessageActionPreview: View {
    var message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(message.presentationSenderDisplayName)
                    .font(.subheadline.weight(.semibold))
                if message.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(CSMTheme.warningAmber)
                }
                Spacer()
                Text(message.sentAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if message.isDeleted {
                Label(CSMLocalization.text("message.deleted", fallback: "Zpráva byla smazána"), systemImage: "nosign")
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
            } else if !message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(message.presentationBody)
                    .font(.body)
                    .lineLimit(5)
                    .textSelection(.enabled)
            } else if let attachment = message.attachments.first {
                Label(attachment.title, systemImage: attachment.chatSystemImageName)
                    .font(.body.weight(.medium))
            }

            if !message.reactions.isEmpty {
                MessageReactionStrip(reactions: message.reactions)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ReplyReferenceView: View {
    var reply: MessageReplyReference
    var isOwnMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reply.senderDisplayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOwnMessage ? .white.opacity(0.92) : CSMTheme.signalBlue)
            Text(reply.bodyPreview)
                .font(.caption)
                .foregroundStyle(isOwnMessage ? .white.opacity(0.76) : .secondary)
                .lineLimit(2)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(replyBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isOwnMessage ? Color.white.opacity(0.78) : CSMTheme.signalBlue)
                .frame(width: 3)
        }
    }

    private var replyBackground: Color {
        isOwnMessage ? Color.white.opacity(0.15) : CSMTheme.signalBlue.opacity(0.08)
    }
}

struct MessageReactionStrip: View {
    var reactions: [MessageReaction]
    var isOwnMessage = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(reactions.filter { $0.count > 0 }) { reaction in
                Text("\(reaction.emoji) \(reaction.count)")
                    .font(.caption2.weight(reaction.reactedByMe ? .bold : .regular))
                    .foregroundStyle(reaction.reactedByMe ? CSMTheme.signalBlue : .primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color(uiColor: .systemBackground),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .stroke(
                                reaction.reactedByMe ? CSMTheme.signalBlue.opacity(0.72) : Color.secondary.opacity(0.28),
                                lineWidth: reaction.reactedByMe ? 1.5 : 1
                            )
                    }
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .accessibilityIdentifier("chat.reactionStrip.\(reaction.emoji)")
            }
        }
    }
}

private struct ChatBubbleShape: Shape {
    var isOwnMessage: Bool
    var showsTail: Bool

    func path(in rect: CGRect) -> Path {
        let tailWidth: CGFloat = showsTail ? 9 : 0
        let bodyRect = CGRect(
            x: isOwnMessage ? rect.minX : rect.minX + tailWidth,
            y: rect.minY,
            width: max(0, rect.width - tailWidth),
            height: rect.height
        )
        var path = Path(roundedRect: bodyRect, cornerRadius: 18, style: .continuous)
        guard showsTail else { return path }

        var tail = Path()
        if isOwnMessage {
            tail.move(to: CGPoint(x: bodyRect.maxX - 7, y: bodyRect.maxY - 19))
            tail.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - 2),
                control: CGPoint(x: bodyRect.maxX - 1, y: bodyRect.maxY - 5)
            )
            tail.addQuadCurve(
                to: CGPoint(x: bodyRect.maxX - 13, y: bodyRect.maxY - 7),
                control: CGPoint(x: bodyRect.maxX - 2, y: bodyRect.maxY)
            )
        } else {
            tail.move(to: CGPoint(x: bodyRect.minX + 7, y: bodyRect.maxY - 19))
            tail.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - 2),
                control: CGPoint(x: bodyRect.minX + 1, y: bodyRect.maxY - 5)
            )
            tail.addQuadCurve(
                to: CGPoint(x: bodyRect.minX + 13, y: bodyRect.maxY - 7),
                control: CGPoint(x: bodyRect.minX + 2, y: bodyRect.maxY)
            )
        }
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}

struct MessageAttachmentChip: View {
    var attachment: MessageAttachment
    var isOwnMessage = false
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            if let image = attachment.chatPreviewImage {
                VStack(alignment: .leading, spacing: 8) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 280)
                        .frame(height: 188)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .clipped()

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isOwnMessage ? .white : .primary)
                                .lineLimit(1)
                            Text(attachment.chatDetailText)
                                .font(.caption2)
                                .foregroundStyle(isOwnMessage ? .white.opacity(0.72) : .secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isOwnMessage ? .white.opacity(0.68) : .secondary)
                    }
                }
                .frame(maxWidth: 280)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    attachmentPreview

                    VStack(alignment: .leading, spacing: 3) {
                        Text(attachment.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOwnMessage ? .white : .primary)
                            .lineLimit(1)
                        Text(attachment.chatDetailText)
                            .font(.caption2)
                            .foregroundStyle(isOwnMessage ? .white.opacity(0.72) : .secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isOwnMessage ? .white.opacity(0.54) : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(attachment.chatPreviewImage == nil ? 9 : 0)
        .background(
            attachment.chatPreviewImage == nil ? attachmentBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.attachment.\(attachment.id)")
        .accessibilityLabel(CSMLocalization.text("attachment.open", fallback: "Otevřít přílohu %@", attachment.title))
    }

    private var attachmentBackground: Color {
        isOwnMessage ? Color.white.opacity(0.14) : Color.secondary.opacity(0.10)
    }

    @ViewBuilder
    private var attachmentPreview: some View {
        if let image = attachment.chatPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: attachment.chatSystemImageName)
                .font(.headline)
                .frame(width: 42, height: 42)
                .foregroundStyle(isOwnMessage ? .white : attachment.chatTint)
                .background(
                    (isOwnMessage ? Color.white.opacity(0.14) : attachment.chatTint.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }
}
