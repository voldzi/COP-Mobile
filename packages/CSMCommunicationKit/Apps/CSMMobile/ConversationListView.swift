import SwiftUI
import UIKit

struct ConversationListView: View {
    @Environment(CommunicationModel.self) private var appModel
    var navigationMode: ConversationListNavigationMode = .push
    var onClose: (() -> Void)?
    var onConversationCreated: (Conversation) -> Void = { _ in }
    var onConversationSelected: (Conversation) -> Void = { _ in }
    @State private var composerMode: ConversationComposerMode?
    @State private var conversationSearchText = ""
    @State private var selectedFilter: ConversationInboxFilter = .all
    @State private var leaveConfirmationConversation: Conversation?
    @State private var showsAllFavorites = false
    @State private var showsFavoritePicker = false
    @State private var isOpeningAIAssistant = false

    var body: some View {
        conversationList
        .navigationTitle(CSMLocalization.text("conversation.inbox.title", fallback: "Zprávy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            conversationToolbar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConversationBottomSearchBar(
                text: $conversationSearchText,
                onCreateDirect: {
                    composerMode = .direct
                }
            )
        }
        .sheet(item: $composerMode) { mode in
            ConversationCreationSheet(mode: mode, onCreated: onConversationCreated)
        }
        .sheet(isPresented: $showsAllFavorites) {
            favoriteConversationsSheet
        }
        .sheet(isPresented: $showsFavoritePicker) {
            favoritePickerSheet
        }
        .confirmationDialog(
            CSMLocalization.text("conversation.leave.confirm.title", fallback: "Opustit skupinu?"),
            isPresented: Binding(
                get: { leaveConfirmationConversation != nil },
                set: { isPresented in
                    if !isPresented {
                        leaveConfirmationConversation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let conversation = leaveConfirmationConversation {
                Button(CSMLocalization.text("conversation.action.leave_group", fallback: "Opustit skupinu"), role: .destructive) {
                    Task {
                        await appModel.leaveGroupConversation(conversation)
                    }
                    leaveConfirmationConversation = nil
                }
            }
            Button(CSMLocalization.text("common.cancel", fallback: "Zrušit"), role: .cancel) {
                leaveConfirmationConversation = nil
            }
        } message: {
            Text(CSMLocalization.text(
                "conversation.leave.confirm.message",
                fallback: "Odejdete z Matrix místnosti. Historie na serveru se nemaže, ale tato skupina a lokální timeline cache se z tohoto zařízení odstraní."
            ))
        }
    }

    private var conversationList: some View {
        List {
            if shouldShowPinnedStrip {
                Section {
                    pinnedConversationGrid
                        .conversationChromeRow(top: 0, bottom: 8)
                }
            }

            Section {
                if appModel.visibleConversations.isEmpty,
                   appModel.conversations.isEmpty,
                   appModel.conversationListLoadState == .notLoaded || appModel.conversationListLoadState == .loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .accessibilityLabel(CSMLocalization.text("conversation.loading", fallback: "Načítám zprávy"))
                        .conversationChromeRow()
                } else if appModel.visibleConversations.isEmpty,
                          appModel.conversations.isEmpty,
                          appModel.conversationListLoadState == .failed {
                    ConversationLoadFailureState {
                        Task {
                            await appModel.refreshConversations()
                        }
                    }
                    .conversationChromeRow()
                } else if appModel.visibleConversations.isEmpty && appModel.conversations.isEmpty {
                    EmptyConversationState(
                        onCreateDirect: { composerMode = .direct },
                        onCreateGroup: { composerMode = .group },
                        onCreateAI: openAIAssistantConversation,
                        isOpeningAI: isOpeningAIAssistant
                    )
                    .conversationChromeRow()
                } else if filteredConversations.isEmpty {
                    ContentUnavailableView(
                        CSMLocalization.text("conversation.not_found.title", fallback: "Nic nenalezeno"),
                        systemImage: "magnifyingglass",
                        description: Text(CSMLocalization.text(
                            "conversation.not_found.description",
                            fallback: "Zkuste jiné jméno, skupinu nebo přepnout filtr."
                        ))
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .conversationChromeRow()
                } else {
                    ForEach(filteredConversations) { conversation in
                        ConversationSwipeActionsRow(
                            conversation: conversation,
                            isPinned: appModel.isConversationPinned(conversation),
                            hasVisibleUnread: appModel.conversationHasVisibleUnread(conversation),
                            isMuted: appModel.isConversationMuted(conversation),
                            onTogglePinned: {
                                appModel.togglePinnedConversation(conversation)
                            },
                            onToggleUnread: {
                                appModel.toggleConversationUnread(conversation)
                            },
                            onToggleMuted: {
                                appModel.toggleConversationMuted(conversation)
                            },
                            onHide: {
                                appModel.hideConversationFromList(conversation)
                            },
                            onLeaveGroup: conversation.type == .group && conversation.activeMatrixRoomId != nil ? {
                                leaveConfirmationConversation = conversation
                            } : nil
                        ) {
                            conversationNavigationCell(for: conversation) {
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: navigationMode == .selectionOnly && appModel.selectedConversation?.id == conversation.id,
                                    isPinned: appModel.isConversationPinned(conversation),
                                    hasUnread: appModel.conversationHasVisibleUnread(conversation),
                                    unreadCount: appModel.visibleUnreadCount(for: conversation),
                                    isMuted: appModel.isConversationMuted(conversation),
                                    isManuallyUnread: appModel.isConversationManuallyUnread(conversation)
                                )
                            }
                            .contextMenu {
                                conversationMenuActions(for: conversation)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 14))
                        .listRowBackground(Color(uiColor: .systemBackground))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemBackground))
        .listSectionSpacing(.compact)
        .refreshable {
            await appModel.refreshConversations()
        }
    }

    @ToolbarContentBuilder
    private var conversationToolbar: some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(CSMLocalization.text("conversation.close", fallback: "Zavřít chat"))
                .accessibilityIdentifier("chat.closeToMap")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(
                    CSMLocalization.text("conversation.filter.menu", fallback: "Filtr konverzací"),
                    selection: $selectedFilter
                ) {
                    ForEach(ConversationInboxFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.systemImage)
                            .tag(filter)
                    }
                }

                Divider()

                Button {
                    composerMode = .group
                } label: {
                    Label(
                        CSMLocalization.text("conversation.create.group", fallback: "Nová skupina"),
                        systemImage: "person.3.fill"
                    )
                }
                .accessibilityIdentifier("chat.createGroup")

                Button {
                    showsFavoritePicker = true
                } label: {
                    Label(
                        CSMLocalization.text("conversation.favorites.manage", fallback: "Spravovat oblíbené"),
                        systemImage: "star.fill"
                    )
                }
                .accessibilityIdentifier("chat.manageFavorites")

                Button {
                    NotificationCenter.default.post(name: .csmFieldReadinessDetailRequested, object: nil)
                } label: {
                    Label(
                        CSMLocalization.text("field.readiness.open", fallback: "Stav připravenosti"),
                        systemImage: "checkmark.shield.fill"
                    )
                }
                .accessibilityIdentifier("chat.fieldReadinessLED")
            } label: {
                Image(systemName: selectedFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(CSMLocalization.text("conversation.filter.menu", fallback: "Filtrovat konverzace"))
            .accessibilityIdentifier("chat.conversationFilterMenu")
        }
    }

    private var pinnedConversationGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            alignment: .center,
            spacing: 10
        ) {
            ForEach(Array(pinnedConversations.prefix(5))) { conversation in
                conversationNavigationCell(for: conversation) {
                    QuickAccessConversationBubble(
                        conversation: conversation,
                        isSelected: false,
                        isPinned: false,
                        hasUnread: appModel.conversationHasVisibleUnread(conversation),
                        isMuted: appModel.isConversationMuted(conversation)
                    )
                }
                .contextMenu {
                    conversationMenuActions(for: conversation)
                }
                .accessibilityIdentifier("chat.pinnedBubble.\(conversation.conversationId)")
            }

        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private var filteredConversations: [Conversation] {
        appModel.visibleConversations.filter { conversation in
            (isSearching || selectedFilter.includes(conversation)) &&
                conversationMatchesSearch(conversation)
        }
        .sorted(by: conversationSort)
    }

    private var isSearching: Bool {
        !conversationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var pinnedConversations: [Conversation] {
        appModel.pinnedConversations.filter { conversation in
            selectedFilter.includes(conversation) && conversationMatchesSearch(conversation)
        }
    }

    private var shouldShowPinnedStrip: Bool {
        !pinnedConversations.isEmpty &&
            conversationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func conversationMatchesSearch(_ conversation: Conversation) -> Bool {
        let query = conversationSearchText.csmSearchKey
        guard !query.isEmpty else { return true }

        if conversation.title.csmSearchKey.contains(query) {
            return true
        }
        if conversation.lastActivityPreview?.csmSearchKey.contains(query) == true {
            return true
        }
        return conversation.members.contains { member in
            member.userId.csmSearchKey.contains(query) ||
                member.displayName?.csmSearchKey.contains(query) == true ||
                member.role?.csmSearchKey.contains(query) == true
        }
    }

    private func conversationSort(_ lhs: Conversation, _ rhs: Conversation) -> Bool {
        let lhsDate = lhs.lastActivityAt ?? lhs.updatedAt ?? .distantPast
        let rhsDate = rhs.lastActivityAt ?? rhs.updatedAt ?? .distantPast
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    @ViewBuilder
    private func conversationNavigationCell<Content: View>(
        for conversation: Conversation,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            select(conversation)
            if navigationMode == .push {
                onConversationSelected(conversation)
            }
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func select(_ conversation: Conversation) {
        Task {
            await appModel.selectConversation(conversation)
        }
    }

    private func openAIAssistantConversation() {
        guard !isOpeningAIAssistant else { return }
        isOpeningAIAssistant = true
        Task {
            defer { isOpeningAIAssistant = false }
            guard let conversation = await appModel.openOrCreateAIAssistantConversation() else { return }
            onConversationCreated(conversation)
        }
    }

    private var favoriteConversationsSheet: some View {
        NavigationStack {
            List(pinnedConversations) { conversation in
                Button {
                    showsAllFavorites = false
                    select(conversation)
                    if navigationMode == .push {
                        onConversationSelected(conversation)
                    }
                } label: {
                    ConversationRow(
                        conversation: conversation,
                        isPinned: true,
                        hasUnread: appModel.conversationHasVisibleUnread(conversation),
                        unreadCount: appModel.visibleUnreadCount(for: conversation),
                        isMuted: appModel.isConversationMuted(conversation),
                        isManuallyUnread: appModel.isConversationManuallyUnread(conversation)
                    )
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(CSMLocalization.text("conversation.favorites.title", fallback: "Oblíbené"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CSMLocalization.text("common.done", fallback: "Hotovo")) {
                        showsAllFavorites = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var favoritePickerSheet: some View {
        NavigationStack {
            List(availableFavoriteConversations) { conversation in
                Button {
                    appModel.togglePinnedConversation(conversation)
                    showsFavoritePicker = false
                } label: {
                    ConversationRow(
                        conversation: conversation,
                        hasUnread: appModel.conversationHasVisibleUnread(conversation),
                        unreadCount: appModel.visibleUnreadCount(for: conversation),
                        isMuted: appModel.isConversationMuted(conversation),
                        isManuallyUnread: appModel.isConversationManuallyUnread(conversation)
                    )
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if availableFavoriteConversations.isEmpty {
                    ContentUnavailableView(
                        CSMLocalization.text("conversation.favorites.all_added", fallback: "Vše je v oblíbených"),
                        systemImage: "star.fill"
                    )
                }
            }
            .listStyle(.plain)
            .navigationTitle(CSMLocalization.text("conversation.favorites.add", fallback: "Přidat do oblíbených"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CSMLocalization.text("common.cancel", fallback: "Zrušit")) {
                        showsFavoritePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var availableFavoriteConversations: [Conversation] {
        appModel.visibleConversations
            .filter { !appModel.isConversationPinned($0) }
            .sorted(by: conversationSort)
    }

    @ViewBuilder
    private func conversationMenuActions(for conversation: Conversation) -> some View {
        Button {
            appModel.togglePinnedConversation(conversation)
        } label: {
            Label(
                appModel.isConversationPinned(conversation)
                    ? CSMLocalization.text("conversation.action.unpin", fallback: "Odepnout konverzaci")
                    : CSMLocalization.text("conversation.action.pin", fallback: "Připnout konverzaci"),
                systemImage: appModel.isConversationPinned(conversation) ? "star.slash.fill" : "star.fill"
            )
        }

        Button {
            appModel.toggleConversationUnread(conversation)
        } label: {
            Label(
                appModel.conversationHasVisibleUnread(conversation)
                    ? CSMLocalization.text("conversation.action.mark_read", fallback: "Označit jako přečtené")
                    : CSMLocalization.text("conversation.action.mark_unread", fallback: "Označit jako nepřečtené"),
                systemImage: appModel.conversationHasVisibleUnread(conversation) ? "envelope.open.fill" : "envelope.badge.fill"
            )
        }

        Button {
            appModel.toggleConversationMuted(conversation)
        } label: {
            Label(
                appModel.isConversationMuted(conversation)
                    ? CSMLocalization.text("conversation.action.notifications_on", fallback: "Zapnout oznámení")
                    : CSMLocalization.text("conversation.action.mute", fallback: "Ztlumit oznámení"),
                systemImage: appModel.isConversationMuted(conversation) ? "bell.fill" : "bell.slash.fill"
            )
        }

        Button {
            appModel.hideConversationFromList(conversation)
        } label: {
            Label(hideActionTitle(for: conversation), systemImage: "archivebox.fill")
        }

        if conversation.type == .group, conversation.activeMatrixRoomId != nil {
            Button(role: .destructive) {
                leaveConfirmationConversation = conversation
            } label: {
                Label(
                    CSMLocalization.text("conversation.action.leave_group", fallback: "Opustit skupinu"),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
        }
    }

    private func hideActionTitle(for conversation: Conversation) -> String {
        switch conversation.type {
        case .direct:
            CSMLocalization.text("conversation.action.hide_direct", fallback: "Skrýt chat")
        case .group:
            CSMLocalization.text("conversation.action.hide_group", fallback: "Skrýt ze seznamu")
        }
    }
}

private extension View {
    func conversationChromeRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
