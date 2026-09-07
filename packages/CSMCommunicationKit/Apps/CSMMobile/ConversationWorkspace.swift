import SwiftUI
import UIKit
struct ConversationWorkspace: View {
    @Environment(CommunicationModel.self) private var appModel
    var rootTrustTopPadding: CGFloat = 0
    var locationShareProvider:
        (@MainActor @Sendable () async throws -> CSMCommunicationLocation)?
    var onClose: (() -> Void)?
    var onOpenCOP: (() -> Void)?
    var onStartVoiceCall: ((String, String, [String]?) -> Void)?
    @State private var navigationPath: [String] = []

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ConversationListView(
                onClose: onClose,
                onConversationCreated: { conversation in
                    openConversation(conversation)
                },
                onConversationSelected: { conversation in
                    openConversation(conversation)
                }
            )
                .padding(.top, rootTrustTopPadding)
                .navigationDestination(for: String.self) { conversationID in
                    if let conversation = appModel.conversations.first(where: {
                        $0.conversationId == conversationID
                    }) {
                        ChatView(
                            explicitConversation: conversation,
                            locationShareProvider: locationShareProvider,
                            onOpenCOP: onOpenCOP,
                            onStartVoiceCall: onStartVoiceCall
                        )
                    } else {
                        ContentUnavailableView(
                            CSMLocalization.text(
                                "conversation.unavailable.title",
                                fallback: "Konverzace není dostupná"
                            ),
                            systemImage: "bubble.left.and.exclamationmark.bubble.right"
                        )
                    }
                }
        }
        .accessibilityIdentifier("chat.workspace")
        .onReceive(NotificationCenter.default.publisher(for: .csmNavigationDestinationRequested)) { notification in
            guard
                notification.userInfo?["destination"] as? CSMNavigationDestination == .conversations,
                let conversation = appModel.selectedConversation
            else { return }
            openConversation(conversation)
        }
        .alert(
            CSMLocalization.text("conversation.action.status.title", fallback: "Chat"),
            isPresented: Binding(
                get: { appModel.conversationActionStatusText != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.clearConversationActionStatus()
                    }
                }
            )
        ) {
            Button(CSMLocalization.text("common.ok", fallback: "OK"), role: .cancel) {
                appModel.clearConversationActionStatus()
            }
        } message: {
            Text(appModel.conversationActionStatusText ?? "")
        }
    }

    private func openConversation(_ conversation: Conversation) {
        navigationPath = [conversation.conversationId]
    }
}


struct ChatView: View {
    @Environment(CommunicationModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    var explicitConversation: Conversation?
    var locationShareProvider:
        (@MainActor @Sendable () async throws -> CSMCommunicationLocation)?
    var onOpenCOP: (() -> Void)?
    var onStartVoiceCall: ((String, String, [String]?) -> Void)?
    @State private var draft = ""
    @State private var localSummary: LocalAIConversationSummary?
    @State private var replyTo: MessageReplyReference?
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var showsPendingRecoveryConfirmation = false
    @State private var showsEncryptionRecoverySheet = false
    @State private var actionMessage: ChatMessage?
    @State private var forwardBundle: ForwardMessageBundle?
    @State private var deleteConfirmationMessage: ChatMessage?
    @State private var isSelectionMode = false
    @State private var selectedMessageIds: Set<String> = []
    @State private var showsBulkDeleteConfirmation = false
    @State private var activeSearchMessageId: String?
    @State private var indexedSearchMessageIDs: Set<String> = []
    @State private var selectedAttachment: SelectedMessageAttachment?
    @State private var showsLeaveGroupConfirmation = false
    @State private var showsChatStatusDetail = false
    @State private var callUnavailableMessage: String?
    @State private var isTimelineAtBottom = true
    @State private var previousVisibleMessageCount = 0
    @State private var isLoadingEarlierMessages = false
    @State private var pendingPrependAnchorID: String?
    @State private var timelinePresentationStore = ChatTimelinePresentationStore()
    private let timelineBottomID = "chat.timeline.bottom"

    var activeConversation: Conversation? {
        explicitConversation ?? appModel.selectedConversation
    }

    private var isLoadingActiveConversation: Bool {
        guard let activeConversation else { return false }
        return appModel.loadingConversationId == activeConversation.conversationId
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedMessages: [ChatMessage] {
        appModel.messages.filter { selectedMessageIds.contains($0.id) }
    }

    private var timelinePresentationKey: ChatTimelinePresentationKey {
        ChatTimelinePresentationKey(
            timelineRevision: appModel.timelineStore.state.revision,
            searchText: trimmedSearchText,
            matchingMessageIDs: indexedSearchMessageIDs.sorted()
        )
    }

    var body: some View {
        let timeline = timelinePresentationStore.presentation

        AnyView(VStack(spacing: 0) {
            if let activeConversation {
                if isSearchVisible || !searchText.isEmpty {
                    ChatSearchBar(
                        text: $searchText,
                        resultCount: timeline.searchableMessages.count,
                        activeIndex: activeSearchIndex(in: timeline.searchableMessages),
                        onPrevious: {
                            moveSearchSelection(delta: -1)
                        },
                        onNext: {
                            moveSearchSelection(delta: 1)
                        }
                    )
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if isSelectionMode {
                    MessageSelectionBar(
                        selectedCount: selectedMessageIds.count,
                        canAct: !selectedMessages.isEmpty,
                        canForward: selectedMessages.contains { !$0.isDeleted },
                        onCancel: {
                            clearMessageSelection()
                        },
                        onForward: {
                            let messages = selectedMessages.filter { !$0.isDeleted }
                            guard !messages.isEmpty else { return }
                            forwardBundle = ForwardMessageBundle(messages: messages)
                        },
                        onDelete: {
                            showsBulkDeleteConfirmation = true
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                timelineViewport(timeline)
                aiAgentStatusPanel(for: activeConversation)
                if let localSummary {
                    LocalConversationSummaryPanel(
                        summary: localSummary,
                        onDismiss: {
                            withAnimation(.snappy) {
                                self.localSummary = nil
                            }
                        }
                    )
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                        .background(Color(uiColor: .systemBackground))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                MessageComposer(
                    text: $draft,
                    onSend: {
                        let body = draft
                        let reply = replyTo
                        draft = ""
                        replyTo = nil
                        Task {
                            let sent = await appModel.sendMessage(
                                OutgoingMessageDraft(body: body, replyTo: reply)
                            )
                            guard !sent, draft.isEmpty else { return }
                            draft = body
                            replyTo = reply
                        }
                    },
                    onSendDraft: { draft in
                        var enriched = draft
                        if enriched.replyTo == nil {
                            enriched.replyTo = replyTo
                        }
                        replyTo = nil
                        Task {
                            await appModel.sendMessage(enriched)
                        }
                    },
                    onAssist: {
                        let requestedConversationId = activeConversation.conversationId
                        Task {
                            let summary = await appModel.summarizeActiveConversation()
                            guard self.activeConversation?.conversationId == requestedConversationId else { return }
                            withAnimation(.snappy) {
                                localSummary = summary
                            }
                        }
                    },
                    aiAgentAvailable: activeConversation.isAIAssistantConversation || activeConversation.linkedCommunityGroupId != nil,
                    mentionCandidates: activeConversation.members,
                    locationShareProvider: locationShareProvider,
                    sendBlockedMessage: appModel.messagingSendBlockedMessage,
                    sendBlockedActionTitle: encryptionRecoveryPresentation?.primaryActionTitle,
                    onSendBlockedAction: encryptionRecoveryPresentation == nil ? nil : {
                        showsEncryptionRecoverySheet = true
                    },
                    replyTo: $replyTo
                )
            } else {
                ContentUnavailableView(CSMLocalization.text("conversation.filter.title", fallback: "Konverzace"), systemImage: "message")
            }
        }
        .task(id: activeConversation?.id) {
            if let explicitConversation {
                await appModel.selectConversation(explicitConversation)
            }
            localSummary = nil
            searchText = ""
            isSearchVisible = false
            clearMessageSelection()
            activeSearchMessageId = nil
            previousVisibleMessageCount = 0
            isTimelineAtBottom = true
            pendingPrependAnchorID = nil
            timelinePresentationStore.reset()
        }
        .task(id: timelinePresentationKey) {
            await timelinePresentationStore.update(
                key: timelinePresentationKey,
                messages: appModel.messages,
                voiceCallMessages: appModel.voiceCallTimelineMessages
            )
        }
        .task(id: searchText) {
            let query = trimmedSearchText
            guard !query.isEmpty else {
                indexedSearchMessageIDs = []
                activeSearchMessageId = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let ids = await appModel.timelineStore.searchMessageIDs(query)
            guard !Task.isCancelled, query == trimmedSearchText else { return }
            indexedSearchMessageIDs = Set(ids)
            activeSearchMessageId = ids.first
        }
        .onChange(of: isSearchVisible) { _, value in
            if value {
                activeSearchMessageId = currentSearchableMessages.first?.id
            } else {
                activeSearchMessageId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .csmVoiceCallTimelineChanged)) { notification in
            guard
                let activeConversation,
                let changedRoomID = notification.userInfo?["roomId"] as? String,
                activeConversation.activeMatrixRoomId == changedRoomID
            else { return }
            Task {
                await appModel.refreshVoiceCallTimeline(for: activeConversation)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog(
            CSMLocalization.text("Odstranit čekající zprávy?", fallback: "Odstranit čekající zprávy?"),
            isPresented: $showsPendingRecoveryConfirmation,
            titleVisibility: .visible
        ) {
            Button(CSMLocalization.text("Odstranit z telefonu", fallback: "Odstranit z telefonu"), role: .destructive) {
                Task {
                    await appModel.discardPendingMessagesForActiveConversation()
                }
            }
            Button(CSMLocalization.text("Zrušit", fallback: "Zrušit"), role: .cancel) {}
        } message: {
            Text(CSMLocalization.text(
                "Odstraní se jen zprávy, které ještě neopustily tento telefon. Doručené zprávy v chatu zůstanou.",
                fallback: "Odstraní se jen zprávy, které ještě neopustily tento telefon. Doručené zprávy v chatu zůstanou."
            ))
        }
        .confirmationDialog(
            CSMLocalization.text("conversation.leave.confirm.title", fallback: "Opustit skupinu?"),
            isPresented: $showsLeaveGroupConfirmation,
            titleVisibility: .visible
        ) {
            if let activeConversation {
                Button(CSMLocalization.text("conversation.action.leave_group", fallback: "Opustit skupinu"), role: .destructive) {
                    Task {
                        let didLeave = await appModel.leaveGroupConversation(activeConversation)
                        if didLeave {
                            dismiss()
                        }
                    }
                }
            }
            Button(CSMLocalization.text("common.cancel", fallback: "Zrušit"), role: .cancel) {}
        } message: {
            Text(CSMLocalization.text(
                "conversation.leave.confirm.message",
                fallback: "Odejdete z Matrix místnosti. Historie na serveru se nemaže, ale tato skupina a lokální timeline cache se z tohoto zařízení odstraní."
            ))
        }
        .overlay {
            if let message = actionMessage {
                MessageActionOverlay(
                    message: message,
                    onDismiss: {
                        actionMessage = nil
                    },
                    onReply: {
                        replyTo = message.replyReference
                        actionMessage = nil
                    },
                    onCopy: {
                        copyMessageBody(message)
                        actionMessage = nil
                    },
                    onReact: { emoji in
                        Task {
                            await appModel.toggleReaction(emoji, on: message)
                        }
                        actionMessage = nil
                    },
                    onSendSticker: { sticker in
                        let reply = message.replyReference
                        let attachment = sticker.messageAttachment()
                        Task {
                            await appModel.sendMessage(OutgoingMessageDraft(
                                body: sticker.title,
                                attachments: [attachment],
                                replyTo: reply
                            ))
                        }
                        actionMessage = nil
                    },
                    onTranslate: {
                        await appModel.translateMessage(message)
                    },
                    onForward: {
                        forwardBundle = ForwardMessageBundle(messages: [message])
                        actionMessage = nil
                    },
                    onSelect: {
                        beginMessageSelection(with: message)
                        actionMessage = nil
                    },
                    onTogglePin: {
                        Task {
                            await appModel.togglePinnedMessage(message)
                        }
                        actionMessage = nil
                    },
                    onDelete: {
                        deleteConfirmationMessage = message
                        actionMessage = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(20)
            }
        })
        .animation(.snappy, value: actionMessage?.id)
        .sheet(item: $forwardBundle) { bundle in
            ForwardMessageSheet(
                messages: bundle.messages,
                conversations: appModel.visibleConversations,
                activeConversationId: activeConversation?.conversationId
            ) { targets in
                Task {
                    await appModel.forwardMessages(bundle.messages, to: targets)
                    clearMessageSelection()
                }
            }
        }
        .sheet(item: $selectedAttachment) { selection in
            let message = appModel.messages.first { $0.id == selection.messageId }
            let conversation = activeConversation
            let activeShare = appModel.activeLiveLocationShare.flatMap { share in
                share.conversationId == conversation?.conversationId ? share : nil
            }
            MessageAttachmentDetailSheet(
                attachment: selection.attachment,
                canManageLiveLocation: message?.isOwnMessage == true
                    && conversation != nil
                    && locationShareProvider != nil,
                activeLiveLocationShare: activeShare,
                onStartLiveLocationShare: { duration in
                    guard let conversation, let locationShareProvider else {
                        throw CSMServiceError.unavailable("Aktuální poloha teď není dostupná.")
                    }
                    try await appModel.startLiveLocationShare(
                        durationSeconds: duration,
                        in: conversation,
                        locationProvider: locationShareProvider
                    )
                },
                onStopLiveLocationShare: {
                    try await appModel.stopLiveLocationShare()
                }
            )
        }
        .sheet(isPresented: $showsChatStatusDetail) {
            ChatStatusDetailSheet(
                deliveryPresentation: deliveryPresentation,
                encryptionRecoveryStatus: encryptionRecoveryPresentation,
                onSync: {
                    Task {
                        await appModel.synchronizePendingMessagesForActiveConversation()
                    }
                },
                onDiscardPending: deliveryPresentation.pendingCount > 0 ? {
                    showsPendingRecoveryConfirmation = true
                } : nil,
                onOpenEncryptionRecovery: {
                    showsEncryptionRecoverySheet = true
                }
            )
        }
        .confirmationDialog(
            CSMLocalization.text("Smazat vybrané zprávy?", fallback: "Smazat vybrané zprávy?"),
            isPresented: $showsBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(CSMLocalization.text("Smazat u mě", fallback: "Smazat u mě"), role: .destructive) {
                let messages = selectedMessages
                Task {
                    await appModel.deleteMessagesLocally(messages)
                    clearMessageSelection()
                }
            }

            let redactionCandidates = selectedMessages.filter { $0.isOwnMessage && !$0.isDeleted && $0.deliveryState != .pending }
            if !redactionCandidates.isEmpty {
                Button(CSMLocalization.text("Smazat moje pro všechny", fallback: "Smazat moje pro všechny"), role: .destructive) {
                    Task {
                        await appModel.redactMessagesForEveryone(redactionCandidates)
                        clearMessageSelection()
                    }
                }
            }

            Button(CSMLocalization.text("Zrušit", fallback: "Zrušit"), role: .cancel) {}
        } message: {
            Text(CSMLocalization.text(
                "Smazání u mě skryje vybrané zprávy jen v tomto zařízení. Smazání pro všechny lze provést pouze u vašich již odeslaných zpráv.",
                fallback: "Smazání u mě skryje vybrané zprávy jen v tomto zařízení. Smazání pro všechny lze provést pouze u vašich již odeslaných zpráv."
            ))
        }
        .confirmationDialog(
            CSMLocalization.text("Smazat zprávu?", fallback: "Smazat zprávu?"),
            isPresented: Binding(
                get: { deleteConfirmationMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteConfirmationMessage = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            if let message = deleteConfirmationMessage {
                Button(CSMLocalization.text("Smazat u mě", fallback: "Smazat u mě"), role: .destructive) {
                    Task {
                        await appModel.deleteMessageLocally(message)
                    }
                    deleteConfirmationMessage = nil
                }

                if message.isOwnMessage && !message.isDeleted && message.deliveryState != .pending {
                    Button(CSMLocalization.text("Smazat pro všechny", fallback: "Smazat pro všechny"), role: .destructive) {
                        Task {
                            await appModel.redactMessageForEveryone(message)
                        }
                        deleteConfirmationMessage = nil
                    }
                }
            }
            Button(CSMLocalization.text("Zrušit", fallback: "Zrušit"), role: .cancel) {
                deleteConfirmationMessage = nil
            }
        } message: {
            Text(CSMLocalization.text(
                "Smazání u mě skryje zprávu jen v tomto zařízení. Smazání pro všechny odešle Matrix redakci do celé konverzace.",
                fallback: "Smazání u mě skryje zprávu jen v tomto zařízení. Smazání pro všechny odešle Matrix redakci do celé konverzace."
            ))
        }
        .sheet(isPresented: $showsEncryptionRecoverySheet) {
            MatrixEncryptionRecoverySheet(
                status: appModel.matrixEncryptionRecoveryStatus,
                generatedKey: appModel.matrixEncryptionRecoveryGeneratedKey,
                errorText: appModel.matrixEncryptionRecoveryErrorText,
                errorTechnicalDetail: appModel.matrixEncryptionRecoveryErrorTechnicalDetail,
                isWorking: appModel.matrixEncryptionRecoveryWorking,
                onCreate: {
                    Task {
                        await appModel.createMatrixEncryptionRecovery(reset: false)
                    }
                },
                onRestore: { recoveryKey in
                    Task {
                        await appModel.restoreMatrixEncryptionRecovery(recoveryKey: recoveryKey)
                    }
                },
                onReset: { oldRecoveryKey in
                    Task {
                        await appModel.resetMatrixEncryptionRecovery(oldRecoveryKey: oldRecoveryKey)
                    }
                },
                onClearGeneratedKey: {
                    appModel.clearMatrixEncryptionRecoveryGeneratedKey()
                }
            )
        }
        .alert(
            CSMLocalization.text("Hovor není připraven", fallback: "Hovor není připraven"),
            isPresented: Binding(
                get: { callUnavailableMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        callUnavailableMessage = nil
                    }
                }
            )
        ) {
            Button(CSMLocalization.text("OK", fallback: "OK"), role: .cancel) {
                callUnavailableMessage = nil
            }
        } message: {
            Text(callUnavailableMessage ?? "")
        }
        .navigationTitle(activeConversation?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let activeConversation {
                ToolbarItem(placement: .principal) {
                    ChatNavigationTitle(
                        conversation: activeConversation,
                        avatarDataUrl: activeConversationAvatarDataUrl,
                        avatarRemoteUrl: activeConversationAvatarRemoteUrl,
                        messagingTrust: appModel.messagingTrustPresentation,
                        deliveryPresentation: deliveryPresentation,
                        encryptionRecoveryStatus: encryptionRecoveryPresentation,
                        isPinned: appModel.isConversationPinned(activeConversation),
                        isSearchVisible: isSearchVisible,
                        onToggleSearch: {
                            withAnimation(.snappy) {
                                isSearchVisible.toggle()
                                if !isSearchVisible {
                                    searchText = ""
                                }
                            }
                        },
                        onShowStatusDetail: {
                            showsChatStatusDetail = true
                        },
                        onTogglePin: {
                            appModel.togglePinnedConversation(activeConversation)
                        },
                        onHideConversation: {
                            appModel.hideConversationFromList(activeConversation)
                            dismiss()
                        },
                        onLeaveGroup: activeConversation.type == .group && activeConversation.activeMatrixRoomId != nil ? {
                            showsLeaveGroupConfirmation = true
                        } : nil,
                        onOpenCOP: {
                            onOpenCOP?()
                        }
                    )
                }

                if activeConversation.type == .direct && !activeConversation.isAIAssistantConversation {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            startVoiceCall(in: activeConversation)
                        } label: {
                            Image(systemName: "phone.fill")
                        }
                        .foregroundStyle(
                            activeConversation.activeMatrixRoomId == nil || onStartVoiceCall == nil
                                ? Color.secondary
                                : CSMTheme.signalBlue
                        )
                        .accessibilityLabel(
                            CSMLocalization.text("chat.call.direct.start", fallback: "Zavolat")
                        )
                        .accessibilityIdentifier("chat.startVoiceCall")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func aiAgentStatusPanel(for conversation: Conversation) -> some View {
        if appModel.aiAgentStatusConversationId == conversation.conversationId,
           let statusText = appModel.aiAgentStatusText {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .accessibilityIdentifier("chat.aiAgentStatus")
        }
    }

    private func timelineViewport(_ timeline: ChatTimelinePresentation) -> some View {
        let senderAvatars = messageAvatarsByIdentity
        let senderAvatarRemoteURLs = messageAvatarRemoteURLsByIdentity

        return ScrollViewReader { proxy in
            if let pinnedMessage = appModel.pinnedMessages.first {
                PinnedMessageBanner(
                    message: pinnedMessage,
                    additionalCount: max(0, appModel.pinnedMessages.count - 1),
                    onOpen: {
                        withAnimation(.snappy) {
                            proxy.scrollTo(pinnedMessage.id, anchor: .center)
                        }
                    },
                    onUnpin: {
                        Task {
                            await appModel.togglePinnedMessage(pinnedMessage)
                        }
                    }
                )
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
            }

            ScrollView {
                VStack(spacing: 0) {
                    if appModel.timelineStore.state.hasEarlierMessages {
                        loadEarlierMessagesButton(timeline)
                    }

                    ChatTimelineListView(
                        rows: timeline.rows,
                        searchText: searchText,
                        isSelectionMode: isSelectionMode,
                        selectedMessageIds: selectedMessageIds,
                        activeSearchMessageId: activeSearchMessageId,
                        avatarDataURLForMessage: { message in
                            avatarDataUrl(for: message, using: senderAvatars)
                        },
                        avatarRemoteURLForMessage: { message in
                            avatarRemoteUrl(for: message, using: senderAvatarRemoteURLs)
                        },
                        onReply: { message in
                            guard !isVoiceCallTimelineEvent(message) else { return }
                            replyTo = message.replyReference
                        },
                        onToggleSelection: { message in
                            guard !isVoiceCallTimelineEvent(message) else { return }
                            toggleMessageSelection(message)
                        },
                        onReact: { emoji, message in
                            guard !isVoiceCallTimelineEvent(message) else { return }
                            Task {
                                await appModel.toggleReaction(emoji, on: message)
                            }
                        },
                        onOpenAttachment: { attachment, message in
                            selectedAttachment = SelectedMessageAttachment(
                                attachment: attachment,
                                messageId: message.id
                            )
                        },
                        onShowActions: { message in
                            guard !isVoiceCallTimelineEvent(message) else { return }
                            presentMessageActions(for: message)
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    if appModel.timelineStore.state.hasLaterMessages {
                        returnToLatestMessagesButton
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(timelineBottomID)
                        .onAppear {
                            isTimelineAtBottom = true
                        }
                        .onDisappear {
                            isTimelineAtBottom = false
                        }
                }
            }
            .accessibilityIdentifier("chat.timeline")
            .overlay {
                if timeline.messages.isEmpty {
                    ChatTimelineEmptyOverlay(
                        isLoading: isLoadingActiveConversation,
                        isSearchEmpty: trimmedSearchText.isEmpty
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: TimelineViewportKey(rows: timeline.rows)) { _, viewport in
                if let pendingPrependAnchorID,
                   timeline.rows.contains(where: { $0.id == pendingPrependAnchorID }) {
                    self.pendingPrependAnchorID = nil
                    previousVisibleMessageCount = viewport.count
                    proxy.scrollTo(pendingPrependAnchorID, anchor: .top)
                    return
                }
                let shouldFollow = TimelineScrollPolicy.shouldFollowLatest(
                    previousVisibleMessageCount: previousVisibleMessageCount,
                    currentVisibleMessageCount: viewport.count,
                    isAtBottom: isTimelineAtBottom,
                    lastMessageIsOwn: timeline.rows.last?.message.isOwnMessage == true
                )
                previousVisibleMessageCount = viewport.count
                guard shouldFollow else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(timelineBottomID, anchor: .bottom)
                }
            }
            .onChange(of: activeSearchMessageId) { _, messageId in
                guard let messageId else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(messageId, anchor: .center)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func loadEarlierMessagesButton(_ timeline: ChatTimelinePresentation) -> some View {
        Button {
            guard !isLoadingEarlierMessages else { return }
            isLoadingEarlierMessages = true
            let previousCount = appModel.messages.count
            pendingPrependAnchorID = timeline.rows.first?.id
            Task {
                await appModel.loadEarlierMessagesForActiveConversation()
                if appModel.messages.count == previousCount {
                    pendingPrependAnchorID = nil
                }
                isLoadingEarlierMessages = false
            }
        } label: {
            if isLoadingEarlierMessages {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(
                    CSMLocalization.text(
                        "message.timeline.load_earlier",
                        fallback: "Načíst starší zprávy"
                    ),
                    systemImage: "arrow.up.circle"
                )
            }
        }
        .buttonStyle(.borderless)
        .disabled(isLoadingEarlierMessages)
        .padding(.top, 10)
        .accessibilityIdentifier("chat.loadEarlierMessages")
    }

    private var returnToLatestMessagesButton: some View {
        Button {
            Task {
                await appModel.returnToLatestMessagesForActiveConversation()
            }
        } label: {
            Label(
                CSMLocalization.text(
                    "message.timeline.return_latest",
                    fallback: "Zpět na nejnovější zprávy"
                ),
                systemImage: "arrow.down.circle"
            )
        }
        .buttonStyle(.borderless)
        .padding(.bottom, 10)
        .accessibilityIdentifier("chat.returnToLatestMessages")
    }

    private func startVoiceCall(in conversation: Conversation) {
        guard conversation.type == .direct, !conversation.isAIAssistantConversation else {
            callUnavailableMessage = CSMLocalization.text(
                "chat.call.direct_only",
                fallback: "Hlasové hovory jsou dostupné pouze v přímém chatu mezi dvěma lidmi."
            )
            return
        }
        guard let roomID = conversation.activeMatrixRoomId else {
            callUnavailableMessage = CSMLocalization.text(
                "Konverzace se ještě synchronizuje. Zkuste hovor znovu za chvíli.",
                fallback: "Konverzace se ještě synchronizuje. Zkuste hovor znovu za chvíli."
            )
            return
        }
        guard let onStartVoiceCall else {
            callUnavailableMessage = CSMLocalization.text(
                "Hovory nyní nejsou dostupné. Zavřete chat, znovu jej otevřete a akci opakujte.",
                fallback: "Hovory nyní nejsou dostupné. Zavřete chat, znovu jej otevřete a akci opakujte."
            )
            return
        }
        // Matrix can contain historical aliases for the same person. Those
        // transport identities are not authoritative COP subject identifiers.
        // The API resolves the canonical direct peer from the server-owned
        // conversation bound to this room and validates that it is one-to-one.
        onStartVoiceCall(roomID, conversation.title, nil)
    }

    private func isVoiceCallTimelineEvent(_ message: ChatMessage) -> Bool {
        message.id.hasPrefix("voice-call:")
    }

    private var deliveryPresentation: ChatDeliveryPresentation {
        ChatDeliveryPresentation.make(
            trust: appModel.messagingTrustPresentation,
            pendingCount: appModel.pendingMessageCount,
            transportError: appModel.messagingTransportErrorText,
            syncStatus: appModel.messageOutboxSyncStatusText
        )
    }

    private var encryptionRecoveryPresentation: MatrixEncryptionRecoveryStatus? {
        guard activeConversation.map({ $0.e2eeRequired || $0.encrypted }) == true else {
            return nil
        }
        let status = appModel.matrixEncryptionRecoveryStatus
        return status.requiresUserAction || status.hasMatrixRustCompatibilityWarning ? status : nil
    }

    private func presentMessageActions(for message: ChatMessage) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        actionMessage = message
    }

    private func beginMessageSelection(with message: ChatMessage) {
        withAnimation(.snappy) {
            isSelectionMode = true
            selectedMessageIds = [message.id]
        }
    }

    private var activeConversationAvatarDataUrl: String? {
        guard let activeConversation else { return nil }
        if activeConversation.type == .direct,
           let peerAvatar = activeConversation.members.compactMap({ member -> String? in
               guard !isOwnIdentity(member.userId) else { return nil }
               return normalizedAvatarDataUrl(member.avatarDataUrl)
           }).first {
            return peerAvatar
        }
        if activeConversation.type == .direct {
            return nil
        }
        return normalizedAvatarDataUrl(activeConversation.avatarDataUrl)
    }

    private var activeConversationAvatarRemoteUrl: String? {
        guard let activeConversation else { return nil }
        if activeConversation.type == .direct,
           let peerAvatar = activeConversation.members.compactMap({ member -> String? in
               guard !isOwnIdentity(member.userId) else { return nil }
               return normalizedAvatarUrl(member.avatarUrl)
           }).first {
            return peerAvatar
        }
        if activeConversation.type == .direct {
            return nil
        }
        return normalizedAvatarUrl(activeConversation.avatarUrl)
    }

    private var messageAvatarsByIdentity: [String: String] {
        var values: [String: String] = [:]
        if let activeConversation {
            for member in activeConversation.members {
                guard let avatarDataUrl = normalizedAvatarDataUrl(member.avatarDataUrl) else { continue }
                storeAvatar(avatarDataUrl, for: member.userId, in: &values)
                if let displayName = member.displayName {
                    storeAvatar(avatarDataUrl, for: displayName, in: &values)
                }
            }
        }

        if let ownAvatarDataUrl = normalizedAvatarDataUrl(appModel.effectiveOperatorProfile.avatarDataUrl) {
            for identity in ownIdentityValues {
                storeAvatar(ownAvatarDataUrl, for: identity, in: &values)
            }
        }
        return values
    }

    private var messageAvatarRemoteURLsByIdentity: [String: String] {
        var values: [String: String] = [:]
        if let activeConversation {
            for member in activeConversation.members {
                guard let avatarUrl = normalizedAvatarUrl(member.avatarUrl) else { continue }
                storeAvatar(avatarUrl, for: member.userId, in: &values)
                if let displayName = member.displayName {
                    storeAvatar(avatarUrl, for: displayName, in: &values)
                }
            }
        }
        return values
    }

    private var ownIdentityValues: [String] {
        var values: [String] = []
        if let actor = appModel.actor {
            values.append(actor.subjectId)
            values.append(actor.username)
            values.append(actor.displayName)
        }
        if let displayName = appModel.effectiveOperatorProfile.displayName {
            values.append(displayName)
        }
        return values
    }

    private func avatarDataUrl(for message: ChatMessage, using values: [String: String]) -> String? {
        guard !message.isAIAgentFallbackResponse else { return nil }
        return normalizedAvatarDataUrl(message.senderAvatarDataUrl) ??
            values[ConversationIdentity.canonicalKey(message.senderId)] ??
            values[normalizedIdentity(message.senderDisplayName)]
    }

    private func avatarRemoteUrl(for message: ChatMessage, using values: [String: String]) -> String? {
        guard !message.isAIAgentFallbackResponse else { return nil }
        return normalizedAvatarUrl(message.senderAvatarUrl) ??
            values[ConversationIdentity.canonicalKey(message.senderId)] ??
            values[normalizedIdentity(message.senderDisplayName)]
    }

    private func isOwnIdentity(_ value: String) -> Bool {
        let ownIdentities = Set(ownIdentityValues.map(ConversationIdentity.canonicalKey).filter { !$0.isEmpty })
        return ownIdentities.contains(ConversationIdentity.canonicalKey(value))
    }

    private func storeAvatar(_ avatarDataUrl: String, for identity: String, in values: inout [String: String]) {
        let canonicalKey = ConversationIdentity.canonicalKey(identity)
        let normalizedKey = normalizedIdentity(identity)
        guard !canonicalKey.isEmpty else { return }
        values[canonicalKey] = avatarDataUrl
        values[normalizedKey] = avatarDataUrl
    }

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedAvatarDataUrl(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func normalizedAvatarUrl(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func toggleMessageSelection(_ message: ChatMessage) {
        withAnimation(.snappy) {
            if !isSelectionMode {
                isSelectionMode = true
            }
            if selectedMessageIds.contains(message.id) {
                selectedMessageIds.remove(message.id)
            } else {
                selectedMessageIds.insert(message.id)
            }
            if selectedMessageIds.isEmpty {
                isSelectionMode = false
            }
        }
    }

    private func clearMessageSelection() {
        withAnimation(.snappy) {
            isSelectionMode = false
            selectedMessageIds.removeAll()
        }
    }

    private func moveSearchSelection(delta: Int) {
        let matches = currentSearchableMessages
        guard !matches.isEmpty else {
            activeSearchMessageId = nil
            return
        }

        let currentIndex = activeSearchIndex(in: matches) ?? 0
        let nextIndex = (currentIndex + delta + matches.count) % matches.count
        activeSearchMessageId = matches[nextIndex].id
    }

    private var currentSearchableMessages: [ChatMessage] {
        timelinePresentationStore.presentation.searchableMessages
    }

    private func activeSearchIndex(in messages: [ChatMessage]) -> Int? {
        guard let activeSearchMessageId else { return nil }
        return messages.firstIndex { $0.id == activeSearchMessageId }
    }

    private func copyMessageBody(_ message: ChatMessage) {
        let text = message.presentationBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }
}

struct ChatSearchBar: View {
    @Binding var text: String
    var resultCount: Int
    var activeIndex: Int?
    var onPrevious: () -> Void
    var onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(CSMLocalization.text("Hledat ve zprávách", fallback: "Hledat ve zprávách"), text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .accessibilityLabel(CSMLocalization.text("Hledat ve zprávách", fallback: "Hledat ve zprávách"))
                .accessibilityIdentifier("chat.searchField")
            if !text.isEmpty {
                Text(resultText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .foregroundStyle(resultCount > 0 ? CSMTheme.signalBlue : .secondary)
                .disabled(resultCount == 0)
                .accessibilityLabel(CSMLocalization.text("Předchozí nalezená zpráva", fallback: "Předchozí nalezená zpráva"))

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .foregroundStyle(resultCount > 0 ? CSMTheme.signalBlue : .secondary)
                .disabled(resultCount == 0)
                .accessibilityLabel(CSMLocalization.text("Další nalezená zpráva", fallback: "Další nalezená zpráva"))

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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var resultText: String {
        guard resultCount > 0 else { return "0" }
        let displayIndex = (activeIndex ?? 0) + 1
        return "\(displayIndex)/\(resultCount)"
    }
}

private struct MessageSelectionBar: View {
    var selectedCount: Int
    var canAct: Bool
    var canForward: Bool
    var onCancel: () -> Void
    var onForward: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.headline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glass)
            .foregroundStyle(.secondary)
            .accessibilityLabel(CSMLocalization.text("Zrušit výběr zpráv", fallback: "Zrušit výběr zpráv"))

            Text(selectionText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer()

            Button(action: onForward) {
                Label(CSMLocalization.text("Přeposlat", fallback: "Přeposlat"), systemImage: "arrowshape.turn.up.forward.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .foregroundStyle(canForward ? CSMTheme.signalBlue : .secondary)
            .disabled(!canForward)
            .accessibilityLabel(CSMLocalization.text("Přeposlat vybrané zprávy", fallback: "Přeposlat vybrané zprávy"))

            Button(action: onDelete) {
                Label(CSMLocalization.text("Smazat", fallback: "Smazat"), systemImage: "trash.fill")
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glass)
            .foregroundStyle(canAct ? CSMTheme.criticalRed : .secondary)
            .disabled(!canAct)
            .accessibilityLabel(CSMLocalization.text("Smazat vybrané zprávy", fallback: "Smazat vybrané zprávy"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityIdentifier("chat.messageSelectionBar")
    }

    private var selectionText: String {
        if selectedCount == 1 {
            return CSMLocalization.text("conversation.selection.one", fallback: "1 zpráva vybrána")
        }
        if selectedCount > 1 && selectedCount < 5 {
            return CSMLocalization.text("conversation.selection.few", fallback: "%d zprávy vybrány", selectedCount)
        }
        return CSMLocalization.text("conversation.selection.many", fallback: "%d zpráv vybráno", selectedCount)
    }
}

private struct ChatTimelineListView: View {
    var rows: [TimelineMessageRow]
    var searchText: String
    var isSelectionMode: Bool
    var selectedMessageIds: Set<String>
    var activeSearchMessageId: String?
    var avatarDataURLForMessage: (ChatMessage) -> String?
    var avatarRemoteURLForMessage: (ChatMessage) -> String?
    var onReply: (ChatMessage) -> Void
    var onToggleSelection: (ChatMessage) -> Void
    var onReact: (String, ChatMessage) -> Void
    var onOpenAttachment: (MessageAttachment, ChatMessage) -> Void
    var onShowActions: (ChatMessage) -> Void

    var body: some View {
        LazyVStack(spacing: 2) {
            ForEach(rows) { row in
                ChatTimelineRowView(
                    row: row,
                    searchText: searchText,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedMessageIds.contains(row.message.id),
                    isActiveSearchMatch: row.message.id == activeSearchMessageId,
                    senderAvatarDataUrl: avatarDataURLForMessage(row.message),
                    senderAvatarRemoteUrl: avatarRemoteURLForMessage(row.message),
                    onReply: {
                        onReply(row.message)
                    },
                    onToggleSelection: {
                        onToggleSelection(row.message)
                    },
                    onReact: { emoji in
                        onReact(emoji, row.message)
                    },
                    onOpenAttachment: { attachment in
                        onOpenAttachment(attachment, row.message)
                    },
                    onShowActions: {
                        onShowActions(row.message)
                    }
                )
                .id(row.message.id)
            }
        }
    }
}

private struct ChatTimelineRowView: View {
    var row: TimelineMessageRow
    var searchText: String
    var isSelectionMode: Bool
    var isSelected: Bool
    var isActiveSearchMatch: Bool
    var senderAvatarDataUrl: String?
    var senderAvatarRemoteUrl: String?
    var onReply: () -> Void
    var onToggleSelection: () -> Void
    var onReact: (String) -> Void
    var onOpenAttachment: (MessageAttachment) -> Void
    var onShowActions: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if row.showsDateDivider {
                MessageDayDivider(date: row.message.sentAt)
            }
            MessageBubble(
                message: row.message,
                groupPosition: row.position,
                showsSender: row.showsSender,
                showsAvatar: row.showsAvatar,
                senderAvatarDataUrl: senderAvatarDataUrl,
                senderAvatarRemoteUrl: senderAvatarRemoteUrl,
                searchText: searchText,
                onReply: onReply,
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
                isActiveSearchMatch: isActiveSearchMatch,
                onToggleSelection: onToggleSelection,
                onReact: onReact,
                onOpenAttachment: onOpenAttachment,
                onShowActions: onShowActions
            )
            .padding(.top, row.topSpacing)
        }
    }
}

private struct ChatTimelineEmptyOverlay: View {
    var isLoading: Bool
    var isSearchEmpty: Bool

    var body: some View {
        if isLoading {
            ProgressView()
                .controlSize(.regular)
                .accessibilityLabel(CSMLocalization.text(
                    "chat.loading.messages",
                    fallback: "Načítám zprávy"
                ))
        } else if isSearchEmpty {
            ContentUnavailableView(
                CSMLocalization.text("Zatím tu nejsou zprávy", fallback: "Zatím tu nejsou zprávy"),
                systemImage: "bubble.left.and.text.bubble.right",
                description: Text(CSMLocalization.text(
                    "Napište první zprávu nebo přidejte fotku, soubor, polohu či hlasovou poznámku.",
                    fallback: "Napište první zprávu nebo přidejte fotku, soubor, polohu či hlasovou poznámku."
                ))
            )
        } else {
            ContentUnavailableView(
                CSMLocalization.text("conversation.not_found.title", fallback: "Nic nenalezeno"),
                systemImage: "magnifyingglass"
            )
        }
    }
}

struct LocalConversationSummaryPanel: View {
    var summary: LocalAIConversationSummary
    var onDismiss: () -> Void

    var body: some View {
        CSMGlassPanel(tint: CSMTheme.relayCyan) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(summary.title, systemImage: "wand.and.sparkles")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    StatusPill(text: CSMLocalization.text("V zařízení", fallback: "V zařízení"), systemImage: "iphone.gen3", tint: CSMTheme.relayCyan)
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(CSMLocalization.text("chat.local_ai.dismiss", fallback: "Skrýt lokální AI souhrn"))
                    .accessibilityIdentifier("chat.localAISummary.dismiss")
                }
                ForEach(summary.bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "smallcircle.filled.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !summary.unresolvedItems.isEmpty {
                    Text(CSMLocalization.text("Otevřené body", fallback: "Otevřené body"))
                        .font(.caption.weight(.semibold))
                    ForEach(summary.unresolvedItems, id: \.self) { item in
                        Label(item, systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(CSMTheme.warningAmber)
                    }
                }
                Text(summary.safetyNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("chat.localAISummary")
    }
}

struct MessagingQueueBanner: View {
    @State private var showsTechnicalDetail = false

    var presentation: ChatDeliveryPresentation
    var onSync: () -> Void
    var onDiscard: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: presentation.systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text(presentation.subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                if presentation.pendingCount > 0 {
                    Text("\(presentation.pendingCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
                }
                if presentation.canSync {
                    Button(action: onSync) {
                        Label(CSMLocalization.text("Zkusit odeslat", fallback: "Zkusit odeslat"), systemImage: presentation.syncStatus == "syncing" ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise.circle.fill")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(CSMTheme.signalBlue)
                    .disabled(presentation.syncStatus == "syncing")
                    .accessibilityLabel(CSMLocalization.text("Zkusit odeslat čekající zprávy", fallback: "Zkusit odeslat čekající zprávy"))
                } else {
                    Image(systemName: "lock.shield.fill")
                        .imageScale(.large)
                        .foregroundStyle(tint)
                        .accessibilityLabel(CSMLocalization.text("Bezpečný chat není připravený", fallback: "Bezpečný chat není připravený"))
                }

                Button {
                    withAnimation(.snappy) {
                        showsTechnicalDetail.toggle()
                    }
                } label: {
                    Label(
                        showsTechnicalDetail
                            ? CSMLocalization.text("Skrýt detail", fallback: "Skrýt detail")
                            : CSMLocalization.text("Zobrazit detail", fallback: "Zobrazit detail"),
                        systemImage: showsTechnicalDetail ? "chevron.up.circle" : "info.circle"
                    )
                        .labelStyle(.iconOnly)
                        .imageScale(.large)
                }
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    showsTechnicalDetail
                        ? CSMLocalization.text("Skrýt detail o odeslání", fallback: "Skrýt detail o odeslání")
                        : CSMLocalization.text("Zobrazit detail o odeslání", fallback: "Zobrazit detail o odeslání")
                )

                if let onDiscard, presentation.pendingCount > 0 {
                    Button(action: onDiscard) {
                        Label(CSMLocalization.text("Spravovat čekající zprávy", fallback: "Spravovat čekající zprávy"), systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                            .imageScale(.large)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(CSMLocalization.text("Spravovat čekající zprávy", fallback: "Spravovat čekající zprávy"))
                }
            }

            if showsTechnicalDetail {
                VStack(alignment: .leading, spacing: 6) {
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let syncStatusText = presentation.syncStatusText {
                        Label(syncStatusText, systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let technicalDetail = presentation.technicalDetail {
                        Divider()
                        Label(CSMLocalization.text("Podrobnosti pro správce", fallback: "Podrobnosti pro správce"), systemImage: "wrench.and.screwdriver")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chat.deliveryTechnicalDetailsLabel")

                        Text(technicalDetail)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .accessibilityIdentifier("chat.messagingQueueBanner")
    }

    private var tint: Color {
        switch presentation.severity {
        case .waiting:
            return CSMTheme.warningAmber
        case .warning:
            return CSMTheme.signalBlue
        case .blocked:
            return CSMTheme.warningAmber
        }
    }
}

struct ChatStatusIndicator: View {
    var deliveryPresentation: ChatDeliveryPresentation
    var encryptionRecoveryStatus: MatrixEncryptionRecoveryStatus?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(tint)
                    .frame(width: 13, height: 13)
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.92), lineWidth: 2)
                    }
                    .shadow(color: tint.opacity(0.42), radius: 5)
                    .frame(width: 34, height: 34)

                if deliveryPresentation.pendingCount > 0 {
                    Text("\(deliveryPresentation.pendingCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(minWidth: 16, minHeight: 16)
                        .background(CSMTheme.warningAmber, in: Circle())
                        .offset(x: 1, y: -1)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat.statusIndicator")
        .accessibilityLabel(CSMLocalization.text("chat.status.led.accessibility", fallback: "Stav chatu: %@. Klepnutím zobrazíte detail.", title))
        .zIndex(4)
    }

    private var title: String {
        if let encryptionRecoveryStatus, encryptionRecoveryStatus.requiresUserAction {
            return encryptionRecoveryStatus.title
        }
        if let encryptionRecoveryStatus, encryptionRecoveryStatus.hasMatrixRustCompatibilityWarning {
            return encryptionRecoveryStatus.title
        }
        if deliveryPresentation.isVisible {
            return deliveryPresentation.title
        }
        return CSMLocalization.text("chat.status.ready.title", fallback: "Bezpečný chat")
    }

    private var tint: Color {
        if encryptionRecoveryStatus?.requiresUserAction == true {
            return CSMTheme.warningAmber
        }
        if encryptionRecoveryStatus?.hasMatrixRustCompatibilityWarning == true {
            return CSMTheme.warningAmber
        }
        if deliveryPresentation.isVisible {
            return deliveryPresentation.statusTint
        }
        return CSMTheme.secureGreen
    }
}

struct ChatStatusDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsTechnicalDetails = false

    var deliveryPresentation: ChatDeliveryPresentation
    var encryptionRecoveryStatus: MatrixEncryptionRecoveryStatus?
    var onSync: () -> Void
    var onDiscardPending: (() -> Void)?
    var onOpenEncryptionRecovery: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: systemImage)
                            .foregroundStyle(tint)
                    }

                    if deliveryPresentation.canSync {
                        Button(action: onSync) {
                            Label(CSMLocalization.text("Zkusit odeslat", fallback: "Zkusit odeslat"), systemImage: "arrow.clockwise.circle.fill")
                        }
                        .disabled(deliveryPresentation.syncStatus == "syncing")
                    }

                    if let onDiscardPending, deliveryPresentation.pendingCount > 0 {
                        Button(role: .destructive, action: onDiscardPending) {
                            Label(CSMLocalization.text("Spravovat čekající zprávy", fallback: "Spravovat čekající zprávy"), systemImage: "ellipsis.circle")
                        }
                    }
                }

                if let encryptionRecoveryStatus {
                    Section(CSMLocalization.text("chat.status.recovery.title", fallback: "Obnova šifrování")) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(encryptionRecoveryStatus.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(encryptionRecoveryStatus.userMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: encryptionRecoveryStatus.keyBackupUsable ? "checkmark.seal.fill" : "key.horizontal.fill")
                                .foregroundStyle(recoveryTint(encryptionRecoveryStatus))
                        }

                        if encryptionRecoveryStatus.requiresUserAction {
                            Button {
                                dismiss()
                                onOpenEncryptionRecovery()
                            } label: {
                                Label(encryptionRecoveryStatus.primaryActionTitle, systemImage: "arrow.forward.circle.fill")
                            }
                        }
                    }
                }

                if hasTechnicalDetails {
                    Section {
                        DisclosureGroup(isExpanded: $showsTechnicalDetails) {
                            VStack(alignment: .leading, spacing: 8) {
                                if let syncStatusText = deliveryPresentation.syncStatusText {
                                    Label(syncStatusText, systemImage: "arrow.triangle.2.circlepath")
                                }
                                if let technicalDetail = deliveryPresentation.technicalDetail {
                                    Text(technicalDetail)
                                        .font(.caption2.monospaced())
                                        .textSelection(.enabled)
                                }
                                if let encryptionRecoveryStatus {
                                    Text(encryptionRecoveryStatus.technicalSummary)
                                        .font(.caption2.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                            .foregroundStyle(.secondary)
                        } label: {
                            Label(CSMLocalization.text("Podrobnosti pro správce", fallback: "Podrobnosti pro správce"), systemImage: "wrench.and.screwdriver")
                        }
                    }
                }
            }
            .accessibilityIdentifier("chat.statusDetailSheet")
            .navigationTitle(CSMLocalization.text("chat.status.detail.title", fallback: "Stav chatu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CSMLocalization.text("chat.status.detail.close", fallback: "Hotovo")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        if let encryptionRecoveryStatus, encryptionRecoveryStatus.requiresUserAction || encryptionRecoveryStatus.hasMatrixRustCompatibilityWarning {
            return encryptionRecoveryStatus.title
        }
        return deliveryPresentation.isVisible
            ? deliveryPresentation.title
            : CSMLocalization.text("chat.status.ready.title", fallback: "Bezpečný chat")
    }

    private var subtitle: String {
        if let encryptionRecoveryStatus, encryptionRecoveryStatus.requiresUserAction || encryptionRecoveryStatus.hasMatrixRustCompatibilityWarning {
            return encryptionRecoveryStatus.userMessage
        }
        return deliveryPresentation.isVisible
            ? deliveryPresentation.subtitle
            : CSMLocalization.text("chat.status.ready.subtitle", fallback: "Zprávy jsou připravené k bezpečnému odeslání.")
    }

    private var detail: String {
        if encryptionRecoveryStatus?.hasMatrixRustCompatibilityWarning == true {
            return CSMLocalization.text(
                "chat.status.recovery.compatibility_warning.detail",
                fallback: "Běžné šifrované zprávy zůstávají povolené. Před párováním dalšího nativního zařízení zkontrolujte E2EE obnovu nebo vygenerujte nový recovery cyklus."
            )
        }
        return deliveryPresentation.isVisible
            ? deliveryPresentation.detail
            : CSMLocalization.text("chat.status.ready.detail", fallback: "Chat používá zabezpečený kanál. Stav fronty a technické detaily se zobrazí jen na vyžádání.")
    }

    private var systemImage: String {
        if let encryptionRecoveryStatus, encryptionRecoveryStatus.requiresUserAction || encryptionRecoveryStatus.hasMatrixRustCompatibilityWarning {
            return encryptionRecoveryStatus.keyBackupUsable ? "checkmark.seal.fill" : "key.horizontal.fill"
        }
        return deliveryPresentation.isVisible ? deliveryPresentation.systemImage : "lock.shield.fill"
    }

    private var tint: Color {
        if encryptionRecoveryStatus?.requiresUserAction == true || encryptionRecoveryStatus?.hasMatrixRustCompatibilityWarning == true {
            return CSMTheme.warningAmber
        }
        return deliveryPresentation.isVisible ? deliveryPresentation.statusTint : CSMTheme.secureGreen
    }

    private var hasTechnicalDetails: Bool {
        deliveryPresentation.syncStatusText != nil ||
            deliveryPresentation.technicalDetail != nil ||
            encryptionRecoveryStatus != nil
    }

    private func recoveryTint(_ status: MatrixEncryptionRecoveryStatus) -> Color {
        if status.hasMatrixRustCompatibilityWarning { return CSMTheme.warningAmber }
        return status.keyBackupUsable ? CSMTheme.secureGreen : CSMTheme.warningAmber
    }
}

private extension ChatDeliveryPresentation {
    var statusTint: Color {
        switch severity {
        case .waiting:
            return CSMTheme.warningAmber
        case .warning:
            return CSMTheme.signalBlue
        case .blocked:
            return CSMTheme.warningAmber
        }
    }
}

private struct ChatNavigationTitle: View {
    @State private var showsConversationDetail = false

    var conversation: Conversation
    var avatarDataUrl: String?
    var avatarRemoteUrl: String?
    var messagingTrust: MessagingTrustPresentation
    var deliveryPresentation: ChatDeliveryPresentation
    var encryptionRecoveryStatus: MatrixEncryptionRecoveryStatus?
    var isPinned: Bool
    var isSearchVisible: Bool
    var onToggleSearch: () -> Void
    var onShowStatusDetail: () -> Void
    var onTogglePin: () -> Void
    var onHideConversation: () -> Void
    var onLeaveGroup: (() -> Void)?
    var onOpenCOP: () -> Void

    var body: some View {
        Menu {
            Button {
                showsConversationDetail = true
            } label: {
                Label(CSMLocalization.text("Detail konverzace", fallback: "Detail konverzace"), systemImage: "info.circle")
            }
            .accessibilityIdentifier("chat.conversationDetailAction")

            Button(action: onToggleSearch) {
                Label(
                    isSearchVisible
                        ? CSMLocalization.text("Skrýt hledání ve zprávách", fallback: "Skrýt hledání ve zprávách")
                        : CSMLocalization.text("Hledat ve zprávách", fallback: "Hledat ve zprávách"),
                    systemImage: isSearchVisible ? "magnifyingglass.circle.fill" : "magnifyingglass"
                )
            }
            .accessibilityIdentifier("chat.toggleMessageSearchAction")

            Button(action: onShowStatusDetail) {
                Label(CSMLocalization.text("chat.status.detail.title", fallback: "Stav chatu"), systemImage: "lock.shield")
            }
            .accessibilityIdentifier("chat.statusDetailAction")

            if conversation.type == .group {
                Button(action: onTogglePin) {
                    Label(
                        isPinned
                            ? CSMLocalization.text("Odepnout oblíbenou skupinu", fallback: "Odepnout oblíbenou skupinu")
                            : CSMLocalization.text("Připnout oblíbenou skupinu", fallback: "Připnout oblíbenou skupinu"),
                        systemImage: isPinned ? "star.slash.fill" : "star.fill"
                    )
                }
                .accessibilityIdentifier("chat.togglePinnedConversationAction")
            }

            Button(action: onHideConversation) {
                Label(hideActionTitle, systemImage: "archivebox")
            }
            .accessibilityIdentifier("chat.hideConversationAction")

            if conversation.type == .group, let onLeaveGroup {
                Button(role: .destructive, action: onLeaveGroup) {
                    Label(
                        CSMLocalization.text("conversation.action.leave_group", fallback: "Opustit skupinu"),
                        systemImage: "rectangle.portrait.and.arrow.right"
                    )
                }
                .accessibilityIdentifier("chat.leaveGroupAction")
            }

            Button(action: onOpenCOP) {
                Label(
                    CSMLocalization.text("conversation.detail.open_cop", fallback: "Otevřít COP"),
                    systemImage: "safari"
                )
            }
            .accessibilityIdentifier("chat.openCOPAction")
        } label: {
            HStack(spacing: 7) {
                ConversationAvatar(
                    title: conversation.title,
                    type: conversation.type,
                    tint: conversation.type == .group ? CSMTheme.signalBlue : CSMTheme.relayCyan,
                    size: 32,
                    avatarDataUrl: avatarDataUrl,
                    avatarRemoteUrl: avatarRemoteUrl,
                    symbolOverride: conversation.isAIAssistantConversation ? "shield.lefthalf.filled" : nil,
                    showsTypeBadge: false
                )
                .overlay(alignment: .bottomTrailing) {
                    if hasVisibleStatusIssue {
                        Circle()
                            .fill(deliveryPresentation.statusTint)
                            .frame(width: 9, height: 9)
                            .overlay {
                                Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5)
                            }
                    }
                }

                Text(conversation.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.78)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(CSMLocalization.text("chat.header.tools", fallback: "Nástroje konverzace %@", conversation.title))
        .accessibilityIdentifier("chat.conversationTools")
        .sheet(isPresented: $showsConversationDetail) {
            ConversationDetailSheet(
                conversation: conversation,
                messagingTrust: messagingTrust,
                isPinned: isPinned,
                onTogglePin: onTogglePin,
                onOpenCOP: onOpenCOP
            )
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

    private var hasVisibleStatusIssue: Bool {
        deliveryPresentation.isVisible ||
            encryptionRecoveryStatus?.requiresUserAction == true ||
            encryptionRecoveryStatus?.hasMatrixRustCompatibilityWarning == true
    }

}
