import Foundation
import PhotosUI
import SwiftUI

private struct RecipientSearchRequestKey: Hashable {
    var query: String
    var revision: Int
}

private enum RecipientDirectoryState {
    case idle
    case loading(query: String)
    case results(query: String, recipients: [ConversationRecipient])
    case empty(query: String)
    case unavailable(query: String)

    var recipients: [ConversationRecipient] {
        guard case let .results(_, recipients) = self else { return [] }
        return recipients
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isEmptyResult: Bool {
        if case .empty = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

private func isRecipientSearchCancellation(_ error: Error) -> Bool {
    if error is CancellationError || Task.isCancelled {
        return true
    }
    return (error as? URLError)?.code == .cancelled
}

struct ConversationDetailSheet: View {
    @Environment(CommunicationModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAddMembers = false
    @State private var selectedGroupAvatarItem: PhotosPickerItem?
    @State private var isUpdatingGroupAvatar = false
    @State private var groupAvatarErrorText: String?

    var conversation: Conversation
    var messagingTrust: MessagingTrustPresentation
    var isPinned: Bool
    var onTogglePin: () -> Void
    var onOpenCOP: () -> Void

    var body: some View {
        let hasGroupAvatar = currentConversation.avatarDataUrl != nil || currentConversation.avatarUrl != nil
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            ConversationAvatar(
                                title: currentConversation.title,
                                type: currentConversation.type,
                                tint: currentConversation.type == .group ? CSMTheme.signalBlue : CSMTheme.relayCyan,
                                size: 56,
                                avatarDataUrl: detailAvatarDataUrl,
                                avatarRemoteUrl: detailAvatarRemoteUrl,
                                symbolOverride: currentConversation.isAIAssistantConversation ? "shield.lefthalf.filled" : nil
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentConversation.title)
                                    .font(.title3.weight(.semibold))
                                    .lineLimit(2)
                                Text(
                                    currentConversation.type == .group
                                        ? CSMLocalization.text("conversation.type.group_detail", fallback: "Skupinová konverzace")
                                        : CSMLocalization.text("conversation.kind.direct", fallback: "Přímá zpráva")
                                )
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Label(securityText, systemImage: securitySymbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(securityTint)

                        if currentConversation.type == .group {
                            Divider()
                            ConversationNotificationSubscriptionToggle(conversation: currentConversation)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if currentConversation.type == .group || currentConversation.mapLinkCount > 0 {
                    Section(CSMLocalization.text("conversation.filter.title", fallback: "Konverzace")) {
                        if currentConversation.type == .group {
                            DetailLabelRow(title: CSMLocalization.text("Členové", fallback: "Členové"), value: memberText, systemImage: "person.2.fill", tint: CSMTheme.signalBlue)
                            DetailLabelRow(
                                title: CSMLocalization.text("Oblíbená skupina", fallback: "Oblíbená skupina"),
                                value: isPinned
                                    ? CSMLocalization.text("Připnutá", fallback: "Připnutá")
                                    : CSMLocalization.text("Nepřipnutá", fallback: "Nepřipnutá"),
                                systemImage: isPinned ? "star.fill" : "star",
                                tint: CSMTheme.warningAmber
                            )
                        }
                        if currentConversation.mapLinkCount > 0 {
                            DetailLabelRow(title: CSMLocalization.text("Mapový kontext", fallback: "Mapový kontext"), value: mapContextText, systemImage: "map.fill", tint: CSMTheme.secureGreen)
                        }
                    }
                }

                Section {
                    if currentConversation.type == .group {
                        Button {
                            onTogglePin()
                        } label: {
                            Label(
                                isPinned
                                    ? CSMLocalization.text("conversation.action.unpin_group", fallback: "Odepnout skupinu")
                                    : CSMLocalization.text("conversation.action.pin_group", fallback: "Připnout skupinu"),
                                systemImage: isPinned ? "star.slash.fill" : "star.fill"
                            )
                        }

                        Button {
                            showsAddMembers = true
                        } label: {
                            Label(CSMLocalization.text("Přidat členy", fallback: "Přidat členy"), systemImage: "person.badge.plus")
                        }
                        .accessibilityIdentifier("chat.detail.addMembers")

                        PhotosPicker(selection: $selectedGroupAvatarItem, matching: .images) {
                            Label(
                                hasGroupAvatar
                                    ? CSMLocalization.text("conversation.group.avatar.change", fallback: "Změnit avatar skupiny")
                                    : CSMLocalization.text("conversation.group.avatar.select", fallback: "Vybrat avatar skupiny"),
                                systemImage: "photo.badge.plus"
                            )
                        }
                        .disabled(isUpdatingGroupAvatar)
                        .accessibilityIdentifier("chat.detail.groupAvatarPicker")

                        if hasGroupAvatar {
                            Button(role: .destructive) {
                                updateGroupAvatar(nil)
                            } label: {
                                Label(
                                    CSMLocalization.text("conversation.group.avatar.remove", fallback: "Odstranit avatar skupiny"),
                                    systemImage: "photo.badge.minus"
                                )
                            }
                            .disabled(isUpdatingGroupAvatar)
                            .accessibilityIdentifier("chat.detail.removeGroupAvatar")
                        }

                        if isUpdatingGroupAvatar {
                            ProgressView(CSMLocalization.text("conversation.group.avatar.saving", fallback: "Ukládám avatar skupiny"))
                        }
                        if let groupAvatarErrorText {
                            Text(groupAvatarErrorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }

                    Button {
                        dismiss()
                        onOpenCOP()
                    } label: {
                        Label(
                            CSMLocalization.text("conversation.detail.open_cop", fallback: "Otevřít COP"),
                            systemImage: "safari"
                        )
                    }
                }

                if currentConversation.type == .group && !currentConversation.members.isEmpty {
                    Section(CSMLocalization.text("Lidé", fallback: "Lidé")) {
                        ForEach(currentConversation.members) { member in
                            ConversationMemberDetailRow(member: member)
                        }
                    }
                }

                Section(CSMLocalization.text("Bezpečí", fallback: "Bezpečí")) {
                    DetailLabelRow(title: CSMLocalization.text("Odesílání", fallback: "Odesílání"), value: securityText, systemImage: securitySymbol, tint: securityTint)
                    DetailLabelRow(
                        title: CSMLocalization.text("Offline odeslání", fallback: "Offline odeslání"),
                        value: messagingTrust.isQueueOnly
                            ? CSMLocalization.text("Čeká na spojení", fallback: "Čeká na spojení")
                            : CSMLocalization.text("Připraveno", fallback: "Připraveno"),
                        systemImage: messagingTrust.isQueueOnly ? "tray.full.fill" : "checkmark.circle.fill",
                        tint: messagingTrust.isQueueOnly ? CSMTheme.warningAmber : CSMTheme.secureGreen
                    )
                }
            }
            .navigationTitle(CSMLocalization.text("watch.detail.title", fallback: "Detail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CSMLocalization.text("conversation.detail.done", fallback: "Hotovo")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showsAddMembers) {
            GroupMemberAddSheet(conversation: currentConversation)
        }
        .onChange(of: selectedGroupAvatarItem) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw AvatarImageError.unsupportedImage
                    }
                    let avatarDataUrl = try CSMAvatarImage.makeAvatarDataURL(from: data)
                    updateGroupAvatar(avatarDataUrl)
                } catch {
                    groupAvatarErrorText = groupAvatarFailureText(error)
                    selectedGroupAvatarItem = nil
                }
            }
        }
    }

    private func updateGroupAvatar(_ avatarDataUrl: String?) {
        isUpdatingGroupAvatar = true
        groupAvatarErrorText = nil
        Task {
            defer {
                isUpdatingGroupAvatar = false
                selectedGroupAvatarItem = nil
            }
            do {
                try await appModel.updateGroupConversationAvatar(avatarDataUrl, for: currentConversation)
            } catch {
                groupAvatarErrorText = groupAvatarFailureText(error)
            }
        }
    }

    private func groupAvatarFailureText(_ error: any Error) -> String {
        if error is AvatarImageError || error is CSMServiceError {
            return error.localizedDescription
        }
        if let issue = MessagingUserFacingIssue.make(errorText: error.localizedDescription) {
            return "\(issue.title). \(issue.message) \(issue.recoverySuggestion)"
        }
        return CSMLocalization.text(
            "conversation.group.avatar.failed",
            fallback: "Avatar skupiny se nepodařilo uložit. Zkuste akci znovu."
        )
    }

    private var currentConversation: Conversation {
        appModel.conversations.first { $0.conversationId == conversation.conversationId } ?? conversation
    }

    private var detailAvatarDataUrl: String? {
        guard currentConversation.type == .direct else { return currentConversation.avatarDataUrl }
        return directPeer?.avatarDataUrl
    }

    private var detailAvatarRemoteUrl: String? {
        guard currentConversation.type == .direct else { return currentConversation.avatarUrl }
        return directPeer?.avatarUrl
    }

    private var directPeer: ConversationMember? {
        guard currentConversation.type == .direct else { return nil }
        let selfIds = [
            appModel.actor?.subjectId,
            appModel.actor?.username,
            appModel.actor?.displayName
        ]
            .compactMap { $0 }
            .map(ConversationIdentity.canonicalKey)
        let ownIds = Set(selfIds)
        return currentConversation.members.first {
            !ownIds.contains(ConversationIdentity.canonicalKey($0.userId))
        }
    }

    private var memberText: String {
        let count = max(currentConversation.memberCount, currentConversation.members.count)
        if count == 1 { return CSMLocalization.text("conversation.member.one", fallback: "1 člen") }
        if count > 1 && count < 5 { return CSMLocalization.text("conversation.member.few", fallback: "%d členové", count) }
        return CSMLocalization.text("conversation.member.many", fallback: "%d členů", count)
    }

    private var mapContextText: String {
        currentConversation.mapLinkCount == 1
            ? CSMLocalization.text("conversation.map.item.one", fallback: "1 mapový prvek")
            : CSMLocalization.text("conversation.map.item.many", fallback: "%d mapové prvky", currentConversation.mapLinkCount)
    }

    private var securityText: String {
        if messagingTrust.blocksSending {
            return CSMLocalization.text("field.primary.chat.preparing", fallback: "Chat se připravuje")
        }
        if messagingTrust.isQueueOnly {
            return CSMLocalization.text("field.primary.messages.waiting", fallback: "Zprávy čekají")
        }
        if currentConversation.encrypted, messagingTrust.isReady {
            return CSMLocalization.text("conversation.security.ready", fallback: "Bezpečný chat")
        }
        return currentConversation.encrypted
            ? CSMLocalization.text("conversation.trust.checking", fallback: "Kontrola bezpečí")
            : CSMLocalization.text("conversation.security.unprotected", fallback: "Bez ochrany")
    }

    private var securitySymbol: String {
        if messagingTrust.blocksSending || messagingTrust.isQueueOnly {
            return messagingTrust.systemImage
        }
        return currentConversation.encrypted ? "lock.shield.fill" : "lock.open.fill"
    }

    private var securityTint: Color {
        if messagingTrust.blocksSending || messagingTrust.isQueueOnly {
            return CSMTheme.warningAmber
        }
        return currentConversation.encrypted ? CSMTheme.secureGreen : CSMTheme.criticalRed
    }
}

struct ConversationNotificationSubscriptionToggle: View {
    @Environment(CommunicationModel.self) private var appModel

    var conversation: Conversation

    var body: some View {
        if let subscriptionId = conversation.notificationGroupSubscriptionId {
            Toggle(isOn: subscriptionBinding(subscriptionId)) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CSMLocalization.text("Prioritní oznámení", fallback: "Prioritní oznámení"))
                            .font(.subheadline.weight(.semibold))
                        Text(detailText(isWatched: isWatched(subscriptionId)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: isWatched(subscriptionId) ? "bell.badge.fill" : "bell")
                        .foregroundStyle(isWatched(subscriptionId) ? CSMTheme.warningAmber : CSMTheme.relayCyan)
                }
            }
            .accessibilityIdentifier("chat.detail.notificationSubscription")
        }
    }

    private func subscriptionBinding(_ subscriptionId: String) -> Binding<Bool> {
        Binding {
            appModel.notificationSubscriptions.containsGroup(subscriptionId)
        } set: { enabled in
            Task {
                await appModel.setNotificationGroupSubscription(subscriptionId, enabled: enabled)
            }
        }
    }

    private func isWatched(_ subscriptionId: String) -> Bool {
        appModel.notificationSubscriptions.containsGroup(subscriptionId)
    }

    private func detailText(isWatched: Bool) -> String {
        if isWatched {
            return CSMLocalization.text("conversation.priority.enabled", fallback: "Telefon dostane prioritní upozornění pro tuto skupinu.")
        }
        if appModel.isConversationPinned(conversation) {
            return CSMLocalization.text(
                "conversation.priority.favorite_only",
                fallback: "Skupina je oblíbená v aplikaci, ale nebudí telefon prioritně."
            )
        }
        return CSMLocalization.text("conversation.priority.default", fallback: "Zprávy zůstanou v chatu bez prioritního probuzení telefonu.")
    }
}

struct DetailLabelRow: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}

struct ConversationMemberDetailRow: View {
    var member: ConversationMember

    var body: some View {
        HStack(spacing: 11) {
            CSMAvatarImageView(dataUrl: member.avatarDataUrl, remoteUrl: member.avatarUrl, size: 34) {
                Circle()
                    .fill(CSMTheme.relayCyan.opacity(0.16))
                    .overlay {
                        Text(initials)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CSMTheme.relayCyan)
                    }
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.10), lineWidth: 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                if isAdmin {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(CSMTheme.signalBlue, in: Circle())
                        .offset(x: 2, y: 2)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer()

            Text(roleText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(roleText)")
    }

    private var displayName: String {
        let name = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false
            ? name!
            : CSMLocalization.text("conversation.member.unnamed", fallback: "Člen skupiny")
    }

    private var initials: String {
        let words = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = String(words).uppercased()
        return value.isEmpty ? String(member.userId.prefix(2)).uppercased() : value
    }

    private var roleText: String {
        if isAdmin {
            CSMLocalization.text("conversation.role.admin", fallback: "správce")
        } else {
            CSMLocalization.text("conversation.role.member", fallback: "člen")
        }
    }

    private var isAdmin: Bool {
        switch member.role?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "owner", "admin":
            true
        default:
            false
        }
    }
}

struct DetailTextLine: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ConversationCreationSheet: View {
    @Environment(CommunicationModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    let mode: ConversationComposerMode
    var onCreated: (Conversation) -> Void = { _ in }

    @State private var title: String
    @State private var activeMode: ConversationComposerMode
    @State private var recipientSearchText = ""
    @State private var directoryState: RecipientDirectoryState = .idle
    @State private var directorySearchRevision = 0
    @State private var selectedRecipientIds: Set<String> = []
    @State private var selectedRecipientSnapshots: [String: ConversationRecipient] = [:]
    @State private var isCreating = false
    @FocusState private var isRecipientSearchFocused: Bool

    init(
        mode: ConversationComposerMode,
        onCreated: @escaping (Conversation) -> Void = { _ in }
    ) {
        self.mode = mode
        self.onCreated = onCreated
        _title = State(initialValue: "")
        _activeMode = State(initialValue: mode)
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeMode == .direct {
                    directRecipientPicker
                } else {
                    groupCreationForm
                }
            }
            .navigationTitle(activeMode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                creationToolbar
            }
        }
        .presentationDetents(activeMode == .direct ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: RecipientSearchRequestKey(query: recipientSearchText, revision: directorySearchRevision)) {
            await refreshDirectoryRecipients()
        }
        .onAppear {
            appModel.clearConversationOperationError()
        }
        .onChange(of: recipientSearchText) {
            appModel.clearConversationOperationError()
        }
        .task {
            guard activeMode == .direct else { return }
            try? await Task.sleep(for: .milliseconds(180))
            isRecipientSearchFocused = true
        }
    }

    private var canCreate: Bool {
        switch activeMode {
        case .group:
            return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .direct:
            return directRecipientDraft != nil
        }
    }

    private var suggestedGroupConversations: [Conversation] {
        let query = recipientSearchText.csmSearchKey
        return Array(
            appModel.visibleConversations
                .filter { conversation in
                    guard conversation.type == .group else { return false }
                    guard !query.isEmpty else { return true }
                    return conversation.title.csmSearchKey.contains(query) ||
                        conversation.members.contains { member in
                            member.displayName?.csmSearchKey.contains(query) == true ||
                                member.userId.csmSearchKey.contains(query)
                        }
                }
                .sorted { lhs, rhs in
                    let lhsDate = lhs.lastActivityAt ?? lhs.updatedAt ?? .distantPast
                    let rhsDate = rhs.lastActivityAt ?? rhs.updatedAt ?? .distantPast
                    return lhsDate > rhsDate
                }
                .prefix(6)
        )
    }

    private func openExistingConversation(_ conversation: Conversation) {
        guard !isCreating else { return }
        dismiss()
        onCreated(conversation)
    }

    private func createDirectConversation(with recipient: ConversationMemberDraft) async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }

        guard let createdConversation = await appModel.createDirectConversation(
            userId: recipient.userId,
            displayName: recipient.displayName
        ) else {
            return
        }

        dismiss()
        onCreated(createdConversation)
    }

    private var creationError: String? {
        guard !isCreating else { return nil }
        return appModel.conversationOperationErrorText
    }

    private var recipientCandidates: [ConversationRecipient] {
        CommunicationModel.mergedRecipients(
            appModel.knownConversationRecipients +
                directoryState.recipients +
                Array(selectedRecipientSnapshots.values)
        )
    }

    private var filteredRecipients: [ConversationRecipient] {
        let query = recipientSearchText.csmSearchKey
        guard !query.isEmpty else { return recipientCandidates }
        return recipientCandidates.filter { recipient in
            recipient.title.csmSearchKey.contains(query) ||
                recipient.userId.csmSearchKey.contains(query) ||
                recipient.handle?.csmSearchKey.contains(query) == true ||
                recipient.subtitle.csmSearchKey.contains(query)
        }
    }

    private var selectedRecipients: [ConversationRecipient] {
        recipientCandidates.filter { selectedRecipientIds.contains($0.id) }
    }

    private var selectedMemberDrafts: [ConversationMemberDraft] {
        uniqueDrafts(selectedRecipients.map(\.draft))
    }

    private var directRecipientDraft: ConversationMemberDraft? {
        selectedRecipients.first?.draft
    }

    private func create() async {
        guard canCreate else { return }
        isCreating = true
        defer { isCreating = false }

        let createdConversation: Conversation?
        switch activeMode {
        case .group:
            createdConversation = await appModel.createGroupConversation(title: title, members: selectedMemberDrafts)
        case .direct:
            guard let directRecipientDraft else { return }
            createdConversation = await appModel.createDirectConversation(userId: directRecipientDraft.userId, displayName: directRecipientDraft.displayName)
        }

        guard let createdConversation else {
            return
        }
        dismiss()
        onCreated(createdConversation)
    }

    private func toggle(_ recipient: ConversationRecipient) {
        switch activeMode {
        case .group:
            if selectedRecipientIds.contains(recipient.id) {
                selectedRecipientIds.remove(recipient.id)
                selectedRecipientSnapshots[recipient.id] = nil
            } else {
                selectedRecipientIds.insert(recipient.id)
                selectedRecipientSnapshots[recipient.id] = recipient
            }
        case .direct:
            if selectedRecipientIds.contains(recipient.id) {
                selectedRecipientIds.removeAll()
                selectedRecipientSnapshots.removeAll()
            } else {
                selectedRecipientIds = [recipient.id]
                selectedRecipientSnapshots = [recipient.id: recipient]
            }
        }
    }

    private var directRecipientPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(CSMLocalization.text("conversation.create.to", fallback: "Komu:"))
                    .foregroundStyle(.secondary)

                TextField(
                    CSMLocalization.text("conversation.create.recipient_placeholder", fallback: "Jméno, skupina nebo e-mail"),
                    text: $recipientSearchText
                )
                .focused($isRecipientSearchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .accessibilityIdentifier("chat.recipientSearch")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.secondary.opacity(0.13), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List {
                if recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button {
                            beginGroupCreation()
                        } label: {
                            ConversationCreationOptionRow(
                                title: CSMLocalization.text("conversation.create.group", fallback: "Nová skupina"),
                                systemImage: "person.3.fill",
                                tint: CSMTheme.relayCyan
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.newMessage.createGroup")

                        Button {
                            Task {
                                await openAIAssistantConversation()
                            }
                        } label: {
                            ConversationCreationOptionRow(
                                title: CSMLocalization.text("conversation.create.ai", fallback: "Chat s AI agentem"),
                                systemImage: "shield.lefthalf.filled",
                                tint: CSMTheme.secureGreen
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreating)
                        .accessibilityIdentifier("chat.newMessage.aiAssistant")
                    }
                }

                if directoryState.isLoading {
                    RecipientDirectoryLoadingRow()
                        .accessibilityIdentifier("chat.recipientSearch.loading")
                }

                if !suggestedGroupConversations.isEmpty {
                    Section {
                        ForEach(suggestedGroupConversations) { conversation in
                            Button {
                                openExistingConversation(conversation)
                            } label: {
                                ExistingConversationDestinationRow(conversation: conversation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat.recipient.group.\(conversation.conversationId)")
                        }
                    }
                }

                if !filteredRecipients.isEmpty {
                    Section {
                        ForEach(filteredRecipients) { recipient in
                            Button {
                                Task {
                                    await createDirectConversation(with: recipient.draft)
                                }
                            } label: {
                                RecipientSelectionRow(
                                    recipient: recipient,
                                    isSelected: false,
                                    mode: .direct
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isCreating)
                            .accessibilityIdentifier("chat.recipient.\(recipient.userId)")
                        }
                    }
                }

                if filteredRecipients.isEmpty,
                   suggestedGroupConversations.isEmpty,
                   directoryState.isEmptyResult {
                    RecipientSearchEmptyRow()
                        .accessibilityIdentifier("chat.recipientSearch.empty")
                }

                if filteredRecipients.isEmpty,
                   suggestedGroupConversations.isEmpty,
                   directoryState.isUnavailable {
                    RecipientDirectoryUnavailableRow {
                        directorySearchRevision += 1
                    }
                    .accessibilityIdentifier("chat.recipientSearch.unavailable")
                }

                if let creationError {
                    Section {
                        MessagingIssueCard(errorText: creationError)
                    }
                }

            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if isCreating {
                    ProgressView(CSMLocalization.text("conversation.create.opening", fallback: "Otevírám konverzaci"))
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var groupCreationForm: some View {
        Form {
            Section {
                TextField(CSMLocalization.text("Jméno skupiny", fallback: "Jméno skupiny"), text: $title)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("chat.newGroup.title")

                TextField(CSMLocalization.text("conversation.create.search_people", fallback: "Hledat lidi"), text: $recipientSearchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .accessibilityIdentifier("chat.recipientSearch")

                if directoryState.isLoading {
                    RecipientDirectoryLoadingRow()
                        .accessibilityIdentifier("chat.recipientSearch.loading")
                }

                ForEach(filteredRecipients) { recipient in
                    RecipientSelectionRow(
                        recipient: recipient,
                        isSelected: selectedRecipientIds.contains(recipient.id),
                        mode: .group
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggle(recipient)
                    }
                    .accessibilityIdentifier("chat.recipient.\(recipient.userId)")
                }

                if filteredRecipients.isEmpty,
                   directoryState.isEmptyResult {
                    RecipientSearchEmptyRow()
                        .accessibilityIdentifier("chat.recipientSearch.empty")
                }

                if filteredRecipients.isEmpty,
                   directoryState.isUnavailable {
                    RecipientDirectoryUnavailableRow {
                        directorySearchRevision += 1
                    }
                    .accessibilityIdentifier("chat.recipientSearch.unavailable")
                }

                if !selectedRecipients.isEmpty {
                    SelectedRecipientsSummary(
                        selectedRecipients: selectedRecipients,
                        mode: .group
                    )
                }
            } header: {
                Text(CSMLocalization.text("conversation.create.section.group_members", fallback: "Skupina a členové"))
            } footer: {
                Text(CSMLocalization.text(
                    "conversation.create.group.directory_only",
                    fallback: "Vybrat lze jen registrované uživatele. Přesný login nebo e-mail pomůže najít i neveřejný profil."
                ))
            }

            ConversationCreationSafetySection()

            if let creationError {
                Section {
                    MessagingIssueCard(errorText: creationError)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var creationToolbar: some ToolbarContent {
        if activeMode == .direct {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .disabled(isCreating)
                .accessibilityLabel(CSMLocalization.text("common.close", fallback: "Zavřít"))
                .accessibilityIdentifier("chat.newMessage.close")
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button(
                    mode == .direct
                        ? CSMLocalization.text("common.back", fallback: "Zpět")
                        : CSMLocalization.text("Zrušit", fallback: "Zrušit")
                ) {
                    if mode == .direct {
                        returnToDirectCreation()
                    } else {
                        dismiss()
                    }
                }
                .disabled(isCreating)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(
                    isCreating
                        ? CSMLocalization.text("Vytvářím", fallback: "Vytvářím")
                        : CSMLocalization.text("Vytvořit", fallback: "Vytvořit")
                ) {
                    Task {
                        await create()
                    }
                }
                .disabled(!canCreate || isCreating)
            }
        }
    }

    private func beginGroupCreation() {
        isRecipientSearchFocused = false
        recipientSearchText = ""
        directoryState = .idle
        selectedRecipientIds.removeAll()
        selectedRecipientSnapshots.removeAll()
        title = ""
        activeMode = .group
    }

    private func returnToDirectCreation() {
        title = ""
        recipientSearchText = ""
        directoryState = .idle
        selectedRecipientIds.removeAll()
        selectedRecipientSnapshots.removeAll()
        activeMode = .direct
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            isRecipientSearchFocused = true
        }
    }

    private func openAIAssistantConversation() async {
        guard !isCreating else { return }
        isCreating = true
        defer { isCreating = false }
        guard let conversation = await appModel.openOrCreateAIAssistantConversation() else { return }
        dismiss()
        onCreated(conversation)
    }

    private func uniqueDrafts(_ drafts: [ConversationMemberDraft]) -> [ConversationMemberDraft] {
        var seen = Set<String>()
        return drafts.filter { draft in
            let id = draft.userId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !id.isEmpty, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private func refreshDirectoryRecipients() async {
        let query = recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            directoryState = .idle
            return
        }

        directoryState = .loading(query: query)
        do {
            try await Task.sleep(for: .milliseconds(250))
            let recipients = try await appModel.searchConversationRecipients(matching: query, limit: 20)
            guard !Task.isCancelled,
                  recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }
            directoryState = recipients.isEmpty
                ? .empty(query: query)
                : .results(query: query, recipients: recipients)
        } catch {
            guard !isRecipientSearchCancellation(error),
                  recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }
            directoryState = .unavailable(query: query)
        }
    }
}

private struct ConversationCreationOptionRow: View {
    var title: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: Circle())
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

struct GroupMemberAddSheet: View {
    @Environment(CommunicationModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    var conversation: Conversation

    @State private var recipientSearchText = ""
    @State private var directoryState: RecipientDirectoryState = .idle
    @State private var directorySearchRevision = 0
    @State private var selectedRecipientIds: Set<String> = []
    @State private var selectedRecipientSnapshots: [String: ConversationRecipient] = [:]
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(CSMLocalization.text("conversation.create.search_people", fallback: "Hledat lidi"), text: $recipientSearchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("chat.addMembers.search")

                    if directoryState.isLoading {
                        RecipientDirectoryLoadingRow()
                            .accessibilityIdentifier("chat.addMembers.search.loading")
                    }

                    ForEach(filteredRecipients) { recipient in
                        RecipientSelectionRow(
                            recipient: recipient,
                            isSelected: selectedRecipientIds.contains(recipient.id),
                            mode: .group
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(recipient)
                        }
                        .accessibilityIdentifier("chat.addMembers.recipient.\(recipient.userId)")
                    }
                    if filteredRecipients.isEmpty && directoryState.isEmptyResult {
                        RecipientSearchEmptyRow()
                            .accessibilityIdentifier("chat.addMembers.search.empty")
                    }

                    if filteredRecipients.isEmpty && directoryState.isUnavailable {
                        RecipientDirectoryUnavailableRow {
                            directorySearchRevision += 1
                        }
                        .accessibilityIdentifier("chat.addMembers.search.unavailable")
                    }

                    if !selectedRecipients.isEmpty {
                        SelectedRecipientsSummary(
                            selectedRecipients: selectedRecipients,
                            mode: .group
                        )
                    }
                } header: {
                    Text(CSMLocalization.text("conversation.create.section.select_people", fallback: "Vybrat lidi"))
                } footer: {
                    Text(CSMLocalization.text(
                        "conversation.create.group.directory_only",
                        fallback: "Přidat lze jen registrované uživatele. Přesný login nebo e-mail pomůže najít i neveřejný profil."
                    ))
                }

                ConversationCreationSafetySection()

                if let saveError {
                    Section {
                        MessagingIssueCard(errorText: saveError)
                    }
                }
            }
            .navigationTitle(CSMLocalization.text("Přidat členy", fallback: "Přidat členy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CSMLocalization.text("Zrušit", fallback: "Zrušit")) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        isSaving
                            ? CSMLocalization.text("Ukládám", fallback: "Ukládám")
                            : CSMLocalization.text("Přidat", fallback: "Přidat")
                    ) {
                        Task {
                            await addMembers()
                        }
                    }
                    .disabled(!canAdd || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task(id: RecipientSearchRequestKey(query: recipientSearchText, revision: directorySearchRevision)) {
            await refreshDirectoryRecipients()
        }
        .onAppear {
            appModel.clearConversationOperationError()
        }
        .onChange(of: recipientSearchText) {
            appModel.clearConversationOperationError()
        }
    }

    private var currentConversation: Conversation {
        appModel.conversations.first { $0.conversationId == conversation.conversationId } ?? conversation
    }

    private var recipientCandidates: [ConversationRecipient] {
        let existingIds = Set(currentConversation.members.map { ConversationIdentity.canonicalKey($0.userId) })
        return CommunicationModel.mergedRecipients(
            appModel.knownConversationRecipients +
                directoryState.recipients +
                Array(selectedRecipientSnapshots.values)
        ).filter { recipient in
            !existingIds.contains(ConversationIdentity.canonicalKey(recipient.userId))
        }
    }

    private var filteredRecipients: [ConversationRecipient] {
        let query = recipientSearchText.csmSearchKey
        guard !query.isEmpty else { return recipientCandidates }
        return recipientCandidates.filter { recipient in
            recipient.title.csmSearchKey.contains(query) ||
                recipient.userId.csmSearchKey.contains(query) ||
                recipient.handle?.csmSearchKey.contains(query) == true ||
                recipient.subtitle.csmSearchKey.contains(query)
        }
    }

    private var selectedRecipients: [ConversationRecipient] {
        recipientCandidates.filter { selectedRecipientIds.contains($0.id) }
    }

    private var selectedMemberDrafts: [ConversationMemberDraft] {
        uniqueDrafts(selectedRecipients.map(\.draft))
    }

    private var canAdd: Bool {
        !selectedMemberDrafts.isEmpty
    }

    private var saveError: String? {
        guard !isSaving else { return nil }
        return appModel.conversationOperationErrorText
    }

    private func addMembers() async {
        guard canAdd else { return }
        isSaving = true
        defer { isSaving = false }

        guard await appModel.addMembers(to: currentConversation, members: selectedMemberDrafts) != nil else {
            return
        }
        dismiss()
    }

    private func toggle(_ recipient: ConversationRecipient) {
        if selectedRecipientIds.contains(recipient.id) {
            selectedRecipientIds.remove(recipient.id)
            selectedRecipientSnapshots[recipient.id] = nil
        } else {
            selectedRecipientIds.insert(recipient.id)
            selectedRecipientSnapshots[recipient.id] = recipient
        }
    }

    private func uniqueDrafts(_ drafts: [ConversationMemberDraft]) -> [ConversationMemberDraft] {
        var seen = Set(currentConversation.members.map { ConversationIdentity.canonicalKey($0.userId) })
        return drafts.filter { draft in
            let id = ConversationIdentity.canonicalKey(draft.userId)
            guard !id.isEmpty, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private func refreshDirectoryRecipients() async {
        let query = recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            directoryState = .idle
            return
        }

        directoryState = .loading(query: query)
        do {
            try await Task.sleep(for: .milliseconds(250))
            let excluded = Set(currentConversation.members.map(\.userId))
            let recipients = try await appModel.searchConversationRecipients(
                matching: query,
                excludingUserIds: excluded,
                limit: 20
            )
            guard !Task.isCancelled,
                  recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }
            directoryState = recipients.isEmpty
                ? .empty(query: query)
                : .results(query: query, recipients: recipients)
        } catch {
            guard !isRecipientSearchCancellation(error),
                  recipientSearchText.trimmingCharacters(in: .whitespacesAndNewlines) == query else {
                return
            }
            directoryState = .unavailable(query: query)
        }
    }
}

struct RecipientSelectionRow: View {
    var recipient: ConversationRecipient
    var isSelected: Bool
    var mode: ConversationComposerMode

    var body: some View {
        HStack(spacing: 12) {
            ConversationAvatar(
                title: recipient.title,
                type: .direct,
                tint: isSelected ? CSMTheme.signalBlue : CSMTheme.relayCyan,
                size: 38,
                avatarDataUrl: recipient.avatarDataUrl,
                avatarRemoteUrl: recipient.avatarUrl,
                showsTypeBadge: false
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !recipient.subtitle.isEmpty {
                    Text(recipient.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if mode == .direct {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? CSMTheme.signalBlue : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isSelected
                ? CSMLocalization.text("conversation.recipient.selected", fallback: "%@, vybráno", recipient.title)
                : CSMLocalization.text("conversation.recipient.unselected", fallback: "%@, nevybráno", recipient.title)
        )
    }
}

struct ExistingConversationDestinationRow: View {
    var conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            ConversationAvatar(
                title: conversation.title,
                type: conversation.type,
                tint: CSMTheme.signalBlue,
                size: 40,
                avatarDataUrl: conversation.avatarDataUrl,
                avatarRemoteUrl: conversation.avatarUrl,
                showsTypeBadge: false
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(memberSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var memberSummary: String {
        let count = max(conversation.memberCount, conversation.members.count)
        let members: String
        if count == 1 {
            members = CSMLocalization.text("conversation.member.one", fallback: "1 člen")
        } else if count > 1 && count < 5 {
            members = CSMLocalization.text("conversation.member.few", fallback: "%d členové", count)
        } else {
            members = CSMLocalization.text("conversation.member.many", fallback: "%d členů", count)
        }
        return "\(CSMLocalization.text("conversation.kind.group", fallback: "Skupina")) · \(members)"
    }
}

struct RecipientDirectoryLoadingRow: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text(CSMLocalization.text("conversation.recipient.searching_directory", fallback: "Hledám uživatele"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecipientSearchEmptyRow: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(CSMLocalization.text("conversation.recipient.no_match.title", fallback: "Nikoho jsme nenašli"))
                    .font(.subheadline.weight(.semibold))
                Text(CSMLocalization.text("conversation.recipient.no_match.message", fallback: "Zkontrolujte jméno nebo e-mail a zkuste to znovu."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundStyle(CSMTheme.warningAmber)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecipientDirectoryUnavailableRow: View {
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(CSMLocalization.text(
                        "conversation.recipient.unavailable.title",
                        fallback: "Vyhledávání teď není dostupné"
                    ))
                        .font(.subheadline.weight(.semibold))
                    Text(CSMLocalization.text(
                        "conversation.recipient.unavailable.message",
                        fallback: "Zkontrolujte připojení a zkuste to znovu."
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(CSMTheme.warningAmber)
            }

            Button(action: onRetry) {
                Label(CSMLocalization.text("common.retry", fallback: "Zkusit znovu"), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .accessibilityElement(children: .contain)
    }
}

struct ConversationCreationSafetySection: View {
    @State private var showsDetails = false

    var body: some View {
        Section {
            Label(CSMLocalization.text("Zprávy zůstanou chráněné", fallback: "Zprávy zůstanou chráněné"), systemImage: "lock.shield.fill")
            Label(CSMLocalization.text("Při výpadku se uloží v zařízení", fallback: "Při výpadku se uloží v zařízení"), systemImage: "tray.full.fill")
            DisclosureGroup(isExpanded: $showsDetails) {
                Text(CSMLocalization.text(
                    "Správa konverzace pracuje jen s adresáty a názvem. Obsah chatu, fotky, soubory a poloha zůstávají v zabezpečeném toku nebo v lokální chráněné frontě, dokud se neobnoví spojení.",
                    fallback: "Správa konverzace pracuje jen s adresáty a názvem. Obsah chatu, fotky, soubory a poloha zůstávají v zabezpečeném toku nebo v lokální chráněné frontě, dokud se neobnoví spojení."
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            } label: {
                Label(CSMLocalization.text("Jak je to chráněné", fallback: "Jak je to chráněné"), systemImage: "info.circle")
                    .foregroundStyle(CSMTheme.signalBlue)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

struct MessagingIssueCard: View {
    var errorText: String

    private var issue: MessagingUserFacingIssue {
        MessagingUserFacingIssue.make(errorText: errorText) ?? MessagingUserFacingIssue(
            title: CSMLocalization.text("messaging.issue.generic.title", fallback: "Akci se nepodařilo dokončit"),
            message: CSMLocalization.text(
                "messaging.issue.generic.message",
                fallback: "Aplikace zachová chráněná data v zařízení a dovolí pokus zopakovat."
            ),
            recoverySuggestion: CSMLocalization.text(
                "messaging.issue.generic.recovery",
                fallback: "Zkontrolujte připojení a zkuste akci znovu."
            ),
            technicalDetail: errorText,
            systemImage: "exclamationmark.triangle.fill"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.title, systemImage: issue.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CSMTheme.warningAmber)
                .fixedSize(horizontal: false, vertical: true)

            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(issue.recoverySuggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("chat.messagingIssueCard")
    }
}

struct SelectedRecipientsSummary: View {
    var selectedRecipients: [ConversationRecipient]
    var mode: ConversationComposerMode

    var body: some View {
        Label(summary, systemImage: mode == .group ? "person.3.fill" : "person.fill.checkmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CSMTheme.signalBlue)
    }

    private var summary: String {
        let count = selectedRecipients.count
        if mode == .direct {
            return CSMLocalization.text("Adresát vybrán", fallback: "Adresát vybrán")
        }
        if count == 1 { return CSMLocalization.text("conversation.recipients.one", fallback: "1 člen vybrán") }
        if count > 1 && count < 5 { return CSMLocalization.text("conversation.recipients.few", fallback: "%d členové vybráni", count) }
        return CSMLocalization.text("conversation.recipients.many", fallback: "%d členů vybráno", count)
    }
}
