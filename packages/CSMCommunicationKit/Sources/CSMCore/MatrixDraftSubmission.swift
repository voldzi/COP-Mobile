import Foundation

/// Stored inside the encrypted outbox. The application draft ID is deliberately
/// separate from the complete SDK transaction ID and confirmed Matrix event ID.
struct MatrixDraftSubmission: Codable, Equatable, Hashable, Sendable {
    enum State: String, Codable, Sendable { case notStarted, queuing, queued, confirmed }
    struct Part: Codable, Equatable, Hashable, Sendable {
        var state: State = .notStarted
        var transactionID: String?
        var eventID: String?
    }
    enum Failure: String, Codable, Sendable {
        case untrustedDevices, identityChanged, verificationRequired, missingAttachment, invalidAttachmentType, serviceUnavailable, awaitingAcknowledgement
        var message: String {
            switch self {
            case .untrustedDevices: "Zařízení příjemce vyžaduje výslovné ověření důvěry. Zpráva zůstává ve frontě Matrix a není potvrzena."
            case .identityChanged: "Změnila se ověřená identita příjemce. Nejprve ji ověřte; aplikace důvěru automaticky neruší."
            case .verificationRequired: "Šifrovaný chat vyžaduje ověření zařízení. Dokončete ověření před pokračováním."
            case .missingAttachment: "Matrix nemá dostupnou původní přílohu. Odeslání čeká na bezpečné vyřešení existující transakce."
            case .invalidAttachmentType: "Matrix odmítl typ přílohy. Existující transakce se automaticky neopakuje."
            case .serviceUnavailable: "Matrix nemohl požadavek dokončit. Existující transakce se kontroluje, nevytváří se nové odeslání."
            case .awaitingAcknowledgement: "Matrix zatím nepotvrdil odeslání této zprávy. Neodesílá se znovu."
            }
        }
    }
    var scope: MatrixLocalStoreScope
    var roomID: String
    var failure: Failure? = nil
    var parts: [Part]

    init(scope: MatrixLocalStoreScope, draft: OutgoingMessageDraft, roomID: String) {
        self.scope = scope
        self.roomID = roomID
        let oneSafetyEvent = !draft.attachments.isEmpty && draft.attachments.allSatisfy { $0.kind == .safetyStatus }
        self.parts = Array(repeating: Part(), count: oneSafetyEvent ? 1 : max(1, draft.attachments.count))
    }
    var isConfirmed: Bool { !parts.isEmpty && parts.allSatisfy { $0.state == .confirmed && $0.eventID?.hasPrefix("$") == true } }
    var canResume: Bool { parts.allSatisfy { $0.state == .confirmed || $0.state == .notStarted } }
    var hasUncertainPart: Bool { parts.contains { $0.state == .queuing || $0.state == .queued } }

    func canFollow(_ previous: MatrixDraftSubmission) -> Bool {
        guard scope == previous.scope, roomID == previous.roomID, parts.count == previous.parts.count else { return false }
        let rank: [State: Int] = [.notStarted: 0, .queuing: 1, .queued: 2, .confirmed: 3]
        return zip(previous.parts, parts).allSatisfy { old, new in
            rank[new.state, default: -1] >= rank[old.state, default: -1] &&
            (old.transactionID == nil || old.transactionID == new.transactionID) &&
            (old.eventID == nil || old.eventID == new.eventID)
        }
    }

    mutating func confirm(transactionID: String, eventID: String) {
        guard !transactionID.isEmpty, eventID.hasPrefix("$") else { return }
        for i in parts.indices where parts[i].transactionID == transactionID {
            parts[i].state = .confirmed
            parts[i].eventID = eventID
        }
        if isConfirmed { failure = nil }
    }
}

protocol MatrixDraftSending: Sendable {
    func submitMatrixDraft(_ draft: OutgoingMessageDraft, to conversation: Conversation,
                           submission: MatrixDraftSubmission,
                           persist: @escaping @Sendable (MatrixDraftSubmission) async throws -> Void) async throws -> MatrixDraftSubmission
    func reconcileMatrixDraft(_ submission: MatrixDraftSubmission, in conversation: Conversation) async throws -> MatrixDraftSubmission
}
