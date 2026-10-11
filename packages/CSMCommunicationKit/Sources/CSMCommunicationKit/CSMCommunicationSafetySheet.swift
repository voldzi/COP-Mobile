import SwiftUI

/// The owned conversation surface supplies canonical COP members, never inferred Matrix IDs.
struct CSMCommunicationSafetySheet: View {
    let runtime: CSMCommunicationRuntime
    let conversation: Conversation
    let expectedScope: String
    let actorSubjectID: String
    let onBlocked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var capabilities: CSMAccountSafetyCapabilities?
    @State private var peer = ""
    @State private var reason = CSMCommunicationReportReason.harassment
    @State private var excerpt = ""
    @State private var includeExcerpt = false
    @State private var operationID = UUID()
    @State private var pendingReport: CSMCommunicationReportDraft?
    @State private var reportAccepted = false
    @State private var blocked: Bool?
    @State private var busy = false
    @State private var confirmation: String?
    @State private var status = ""
    private var members: [ConversationMember] { conversation.members.filter { $0.userId != actorSubjectID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Bezpečnost komunikace") {
                    Picker("Uživatel", selection: $peer) {
                        ForEach(members) { member in Text(member.displayName ?? member.userId).tag(member.userId) }
                    }.disabled(busy || pendingReport != nil || reportAccepted)
                    Text("Hlášení vyřizuje správce COP. Obsah chatu se nepřikládá automaticky.")
                }
                Section("Hlášení") {
                    Picker("Důvod", selection: $reason) {
                        Text("Obtěžování").tag(CSMCommunicationReportReason.harassment)
                        Text("Výhrůžky").tag(CSMCommunicationReportReason.threats)
                        Text("Spam").tag(CSMCommunicationReportReason.spam)
                        Text("Sexuální obsah").tag(CSMCommunicationReportReason.sexualContent)
                        Text("Jiné").tag(CSMCommunicationReportReason.other)
                    }.disabled(busy || pendingReport != nil || reportAccepted)
                    Toggle("Přiložit mnou vybraný výňatek", isOn: $includeExcerpt).disabled(busy || pendingReport != nil || reportAccepted)
                    if includeExcerpt { TextEditor(text: $excerpt).frame(minHeight: 90).disabled(busy || pendingReport != nil || reportAccepted) }
                    Button(pendingReport == nil ? "Předat hlášení správci COP" : "Zopakovat stejné hlášení") { confirmation = "report" }
                        .disabled(busy || peer.isEmpty || !CSMCommunicationSafetyActionPolicy.permitsReport(reporting: capabilities?.reporting, pending: pendingReport != nil) || reportAccepted)
                }
                if conversation.type == .direct {
                    Section("Blokování") {
                        Button(blocked == true ? "Odblokovat uživatele" : "Zablokovat uživatele", role: blocked == true ? nil : .destructive) { confirmation = "block" }
                            .disabled(busy || !CSMCommunicationSafetyActionPolicy.permitsBlock(blocking: capabilities?.blocking, currentlyBlocked: blocked))
                    }
                }
                if !status.isEmpty { Text(status).accessibilityIdentifier("chat.safety.status") }
                if capabilities == nil || (capabilities?.reporting != true && capabilities?.blocking != true) {
                    Text("Tato funkce zatím není dostupná.")
                }
                if let contact = CSMCommunicationSafetyActionPolicy.contactURL(email: capabilities?.reportContactEmail) {
                    Link("Kontaktovat správce COP", destination: contact)
                }
            }
            .navigationTitle("Bezpečnost komunikace")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Zavřít") { dismiss() } } }
            .disabled(busy)
            .task {
                peer = members.first?.userId ?? ""
                do { capabilities = try await runtime.copAccountSafetyCapabilities(expectedScope: expectedScope) }
                catch { status = "Služba je nyní nedostupná. Požadavek nebyl potvrzen." }
            }
            .task(id: peer) {
                guard !peer.isEmpty, conversation.type == .direct else { return }
                let selectedPeer = peer
                let generation = runtime.copSessionGeneration()
                do {
                    let state = try await runtime.copCommunicationBlockState(peerSubjectId: selectedPeer, expectedScope: expectedScope)
                    guard peer == selectedPeer, sessionIsCurrent(generation) else { return }
                    blocked = state.blocked
                    await runtime.model.confirmDirectCommunicationBlock(peerSubjectID: selectedPeer, blocked: state.blocked, expectedSubjectID: actorSubjectID)
                    guard peer == selectedPeer, sessionIsCurrent(generation) else { return }
                    if state.blocked { onBlocked() }
                }
                catch { blocked = nil }
            }
            .confirmationDialog(confirmation == "report" ? "Předat hlášení správci COP?" : (blocked == true ? "Odblokovat uživatele?" : "Zablokovat uživatele?"), isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
                Button("Potvrdit", role: confirmation == "block" && blocked != true ? .destructive : nil) {
                    let action = confirmation; confirmation = nil
                    Task { await perform(action) }
                }
                Button("Zrušit", role: .cancel) { confirmation = nil }
            } message: {
                Text(confirmation == "report" ? (includeExcerpt ? "Správce obdrží zvolený cíl, důvod a text, který jste vybrali a potvrdili." : "Správce obdrží zvolený cíl a důvod. Text zpráv se neposílá.") : "Blokování mění doručování zpráv a nových hovorů. Při zablokování se odstraní čekající zprávy pro tento soukromý chat.")
            }
        }
    }
    @MainActor private func perform(_ action: String?) async {
        let generation = runtime.copSessionGeneration()
        guard !busy, sessionIsCurrent(generation) else { status = "Účet se změnil. Otevřete akci znovu."; return }
        busy = true; defer { busy = false }
        do {
            if action == "report" {
                guard CSMCommunicationSafetyActionPolicy.permitsReport(reporting: capabilities?.reporting, pending: pendingReport != nil) else { return }
                if pendingReport == nil {
                    let evidence = includeExcerpt ? try CSMCommunicationReportEvidence(selectedText: excerpt, explicitlyConfirmed: true) : nil
                    pendingReport = CSMCommunicationReportDraft(target: .user(peerSubjectId: peer, conversationId: conversation.conversationId), reason: reason, evidence: evidence)
                }
                guard let draft = pendingReport else { return }
                _ = try await runtime.copCommunicationReport(draft, operationId: operationID, expectedScope: expectedScope)
                guard sessionIsCurrent(generation) else { return }
                reportAccepted = true; status = "Hlášení bylo předáno správci COP k posouzení."
            } else if action == "block" {
                guard CSMCommunicationSafetyActionPolicy.permitsBlock(blocking: capabilities?.blocking, currentlyBlocked: blocked) else { return }
                let state = try await runtime.copCommunicationSetBlocked(blocked != true, peerSubjectId: peer, expectedScope: expectedScope)
                guard sessionIsCurrent(generation) else { return }
                blocked = state.blocked
                await runtime.model.confirmDirectCommunicationBlock(peerSubjectID: peer, blocked: state.blocked, expectedSubjectID: actorSubjectID)
                guard sessionIsCurrent(generation) else { return }
                if state.blocked { onBlocked() }
                status = state.blocked ? "Uživatel je zablokován." : "Uživatel je odblokován."
            }
        } catch { status = "Operaci se nepodařilo potvrdit. Stav blokování nebyl změněn v telefonu." }
    }
    @MainActor private func sessionIsCurrent(_ generation: UUID) -> Bool {
        runtime.copSessionGeneration() == generation && runtime.mobilitySessionScope() == expectedScope &&
            runtime.model.actor?.subjectId == actorSubjectID
    }
}

enum CSMCommunicationSafetyActionPolicy {
    static func permitsReport(reporting: Bool?, pending: Bool) -> Bool { pending || reporting == true }
    static func permitsBlock(blocking: Bool?, currentlyBlocked: Bool?) -> Bool {
        currentlyBlocked == true || (currentlyBlocked == false && blocking == true)
    }
    static func contactURL(email: String?) -> URL? {
        email == "podpora@zeleznalady.cz" ? URL(string: "mailto:podpora@zeleznalady.cz") : nil
    }
}
