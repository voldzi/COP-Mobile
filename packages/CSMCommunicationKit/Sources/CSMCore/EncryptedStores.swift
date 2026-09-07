import CryptoKit
import Foundation
import Security

actor EncryptedFileStore<Value: Codable & Sendable> {
    private let directoryName: String
    private let keyAccount: String
    private let keychain: KeychainCredentialStore
    private let fileManager: FileManager
    private let rootDirectory: URL?
    private let fixedKeyData: Data?

    init(
        directoryName: String,
        keyAccount: String,
        keychain: KeychainCredentialStore,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.directoryName = directoryName
        self.keyAccount = keyAccount
        self.keychain = keychain
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory
        self.fixedKeyData = fixedKeyData
    }

    func save(_ value: Value, id: String) async throws {
        let plaintext = try CSMJSONCoding.encoder.encode(value)
        let key = try await symmetricKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw CSMServiceError.unavailable("Unable to create encrypted payload.")
        }
        let url = try fileURL(for: id)
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
        try excludeFromBackup(url)
    }

    func load(id: String) async throws -> Value? {
        let url = try fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let combined = try Data(contentsOf: url)
        let box = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(box, using: try await symmetricKey())
        return try CSMJSONCoding.decoder.decode(Value.self, from: plaintext)
    }

    func delete(id: String) throws {
        let url = try fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteAll() throws {
        let directory = try directoryURL()
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func symmetricKey() async throws -> SymmetricKey {
        if let fixedKeyData {
            return SymmetricKey(data: fixedKeyData)
        }
        if let data = try await keychain.loadSymmetricKey(account: keyAccount) {
            return SymmetricKey(data: data)
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CSMServiceError.unavailable("Unable to generate encrypted store key.")
        }
        let data = Data(bytes)
        try await keychain.saveSymmetricKey(data, account: keyAccount)
        return SymmetricKey(data: data)
    }

    private func fileURL(for id: String) throws -> URL {
        let directory = try directoryURL()
        return directory.appendingPathComponent(Self.stableFileName(for: id) + ".bin")
    }

    private func directoryURL() throws -> URL {
        let root: URL
        if let rootDirectory {
            root = rootDirectory
        } else {
            root = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try excludeFromBackup(directory)
        return directory
    }

    private func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
    }

    private static func stableFileName(for id: String) -> String {
        let digest = SHA256.hash(data: Data(id.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

actor EncryptedSnapshotStore: SecureSnapshotStoring {
    private let store: EncryptedFileStore<MobileOfflineSnapshot>

    init(keychain: KeychainCredentialStore) {
        self.store = EncryptedFileStore(
            directoryName: "OfflineSnapshots",
            keyAccount: "offline-snapshot",
            keychain: keychain
        )
    }

    func loadSnapshot(for subjectId: String) async throws -> MobileOfflineSnapshot? {
        try await store.load(id: subjectId)
    }

    func saveSnapshot(_ snapshot: MobileOfflineSnapshot, subjectId: String) async throws {
        try await store.save(snapshot, id: subjectId)
    }

    func clear(for subjectId: String) async throws {
        try await store.delete(id: subjectId)
    }
}

actor EncryptedOfflineMapPackStore: OfflineMapPackStoring {
    private let store: EncryptedFileStore<[OfflineMapPack]>

    init(
        keychain: KeychainCredentialStore,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.store = EncryptedFileStore(
            directoryName: "OfflineMapPacks",
            keyAccount: "offline-map-packs",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
    }

    func loadPacks(for subjectId: String) async throws -> [OfflineMapPack] {
        try await store.load(id: subjectId) ?? []
    }

    func savePacks(_ packs: [OfflineMapPack], subjectId: String) async throws {
        try await store.save(packs, id: subjectId)
    }

    func clear(for subjectId: String) async throws {
        try await store.delete(id: subjectId)
    }
}

actor EncryptedMessagingBootstrapStore: MessagingBootstrapStoring {
    private let store: EncryptedFileStore<MessagingBootstrap>

    init(keychain: KeychainCredentialStore) {
        self.store = EncryptedFileStore(
            directoryName: "MessagingBootstrap",
            keyAccount: "messaging-bootstrap",
            keychain: keychain
        )
    }

    func load(subjectId: String, deviceId: String) async throws -> MessagingBootstrap? {
        try await store.load(id: Self.recordId(subjectId: subjectId, deviceId: deviceId))
    }

    func save(_ bootstrap: MessagingBootstrap, subjectId: String, deviceId: String) async throws {
        try await store.save(bootstrap, id: Self.recordId(subjectId: subjectId, deviceId: deviceId))
    }

    func clear(subjectId: String, deviceId: String?) async throws {
        guard let deviceId else {
            try await store.deleteAll()
            return
        }
        try await store.delete(id: Self.recordId(subjectId: subjectId, deviceId: deviceId))
    }

    private static func recordId(subjectId: String, deviceId: String) -> String {
        "\(subjectId)|\(deviceId)"
    }
}

actor EncryptedOfflineMapTileStore: OfflineMapTileStoring {
    private let tileBlobs: EncryptedFileStore<Data>
    private let summaries: EncryptedFileStore<[OfflineMapTileCacheSummary]>

    init(
        keychain: KeychainCredentialStore,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.tileBlobs = EncryptedFileStore(
            directoryName: "OfflineMapTileBlobs",
            keyAccount: "offline-map-tile-blobs",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
        self.summaries = EncryptedFileStore(
            directoryName: "OfflineMapTileSummaries",
            keyAccount: "offline-map-tile-summaries",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
    }

    func saveTile(_ data: Data, coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws {
        try await tileBlobs.save(data, id: Self.tileId(coordinate: coordinate, packId: packId, subjectId: subjectId))
    }

    func loadTile(coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) async throws -> Data? {
        try await tileBlobs.load(id: Self.tileId(coordinate: coordinate, packId: packId, subjectId: subjectId))
    }

    func saveSummary(_ summary: OfflineMapTileCacheSummary, subjectId: String) async throws {
        var allSummaries = try await summaries.load(id: subjectId) ?? []
        allSummaries.removeAll { $0.packId == summary.packId }
        allSummaries.append(summary)
        try await summaries.save(allSummaries, id: subjectId)
    }

    func loadSummary(packId: String, subjectId: String) async throws -> OfflineMapTileCacheSummary? {
        try await summaries.load(id: subjectId)?.first { $0.packId == packId }
    }

    func clear(for subjectId: String) async throws {
        try await summaries.delete(id: subjectId)
        try await tileBlobs.deleteAll()
    }

    private static func tileId(coordinate: OfflineMapTileCoordinate, packId: String, subjectId: String) -> String {
        "\(subjectId):\(packId):\(coordinate.id)"
    }
}

struct URLSessionOfflineMapTileFetcher: OfflineMapTileFetching {
    func data(for url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CSMServiceError.unavailable("Tile server returned HTTP \(httpResponse.statusCode).")
        }
        return data
    }
}

actor OfflineMapTilePackDownloader {
    private let fetcher: any OfflineMapTileFetching
    private let store: any OfflineMapTileStoring

    init(fetcher: any OfflineMapTileFetching, store: any OfflineMapTileStoring) {
        self.fetcher = fetcher
        self.store = store
    }

    func cacheTiles(for plan: OfflineMapTilePlan) async throws -> OfflineMapTileCacheSummary {
        var cached = 0
        var failed = 0
        var byteCount = 0

        for request in plan.requests {
            try Task.checkCancellation()
            if let existing = try await store.loadTile(
                coordinate: request.coordinate,
                packId: plan.packId,
                subjectId: plan.subjectId
            ) {
                cached += 1
                byteCount += existing.count
                continue
            }

            do {
                try Task.checkCancellation()
                let data = try await fetcher.data(for: request.url)
                try Task.checkCancellation()
                try await store.saveTile(
                    data,
                    coordinate: request.coordinate,
                    packId: plan.packId,
                    subjectId: plan.subjectId
                )
                cached += 1
                byteCount += data.count
            } catch {
                try Task.checkCancellation()
                failed += 1
            }
        }

        try Task.checkCancellation()
        let summary = OfflineMapTileCacheSummary(
            packId: plan.packId,
            subjectId: plan.subjectId,
            plannedTileCount: plan.requests.count,
            cachedTileCount: cached,
            failedTileCount: failed,
            byteCount: byteCount,
            minZoom: plan.minZoom,
            maxZoom: plan.maxZoom,
            updatedAt: .now,
            expiresAt: plan.expiresAt
        )
        try await store.saveSummary(summary, subjectId: plan.subjectId)
        return summary
    }
}

actor EncryptedCommunityOutbox: CommunityOutboxStoring {
    private let store: EncryptedFileStore<[CommunityReportDraft]>
    private let attachmentBlobs: EncryptedFileStore<Data>
    private let mediaPolicy: CommunityReportMediaPolicy
    private let outboxId = "community-report-outbox"

    init(
        keychain: KeychainCredentialStore,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil,
        mediaPolicy: CommunityReportMediaPolicy = .standard
    ) {
        self.mediaPolicy = mediaPolicy
        self.store = EncryptedFileStore(
            directoryName: "CommunityOutbox",
            keyAccount: "community-outbox",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
        self.attachmentBlobs = EncryptedFileStore(
            directoryName: "CommunityOutboxAttachmentBlobs",
            keyAccount: "community-outbox-attachment-blobs",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
    }

    func enqueue(_ draft: CommunityReportDraft) async throws {
        var drafts = try await pendingDrafts()
        try mediaPolicy.validateDraft(draft, existingDrafts: drafts)
        drafts.append(draft)
        try await persist(drafts)
    }

    func pendingDrafts() async throws -> [CommunityReportDraft] {
        let drafts = try await store.load(id: outboxId) ?? []
        let hydrated = try await hydrateAttachments(in: drafts)
        let retention = mediaPolicy.retentionResult(for: hydrated)
        if !retention.removedDrafts.isEmpty {
            for draft in retention.removedDrafts {
                for attachment in draft.attachments {
                    try await attachmentBlobs.delete(id: Self.blobId(draftId: draft.id, attachmentId: attachment.id))
                }
            }
        }
        if drafts.contains(where: { draft in draft.attachments.contains { !$0.payload.isEmpty } }) ||
            !retention.removedDrafts.isEmpty {
            try await persist(retention.retainedDrafts)
        }
        return retention.retainedDrafts
    }

    func removeDraft(id: String) async throws {
        var drafts = try await pendingDrafts()
        let removedDrafts = drafts.filter { $0.id == id }
        drafts.removeAll { $0.id == id }
        try await persist(drafts)
        for draft in removedDrafts {
            for attachment in draft.attachments {
                try await attachmentBlobs.delete(id: Self.blobId(draftId: draft.id, attachmentId: attachment.id))
            }
        }
    }

    func clear() async throws {
        try await store.delete(id: outboxId)
        try await attachmentBlobs.deleteAll()
    }

    private func persist(_ drafts: [CommunityReportDraft]) async throws {
        for draft in drafts {
            for attachment in draft.attachments where !attachment.payload.isEmpty {
                try await attachmentBlobs.save(
                    attachment.payload,
                    id: Self.blobId(draftId: draft.id, attachmentId: attachment.id)
                )
            }
        }
        try await store.save(drafts.map(Self.withoutInlineAttachmentPayloads), id: outboxId)
    }

    private func hydrateAttachments(in drafts: [CommunityReportDraft]) async throws -> [CommunityReportDraft] {
        var hydratedDrafts: [CommunityReportDraft] = []
        for draft in drafts {
            var hydratedDraft = draft
            var hydratedAttachments: [CommunityReportAttachmentDraft] = []
            for attachment in draft.attachments {
                if let payload = try await attachmentBlobs.load(id: Self.blobId(draftId: draft.id, attachmentId: attachment.id)) {
                    var hydratedAttachment = attachment
                    hydratedAttachment.payload = payload
                    hydratedAttachments.append(hydratedAttachment)
                    continue
                }
                guard !attachment.payload.isEmpty else {
                    throw CSMServiceError.invalidState("Encrypted attachment blob is missing for report \(draft.id).")
                }
                try await attachmentBlobs.save(
                    attachment.payload,
                    id: Self.blobId(draftId: draft.id, attachmentId: attachment.id)
                )
                hydratedAttachments.append(attachment)
            }
            hydratedDraft.attachments = hydratedAttachments
            hydratedDrafts.append(hydratedDraft)
        }
        return hydratedDrafts
    }

    private static func withoutInlineAttachmentPayloads(_ draft: CommunityReportDraft) -> CommunityReportDraft {
        var sanitizedDraft = draft
        sanitizedDraft.attachments = draft.attachments.map { attachment in
            var sanitizedAttachment = attachment
            sanitizedAttachment.payload = Data()
            return sanitizedAttachment
        }
        return sanitizedDraft
    }

    private static func blobId(draftId: String, attachmentId: String) -> String {
        "\(draftId):\(attachmentId)"
    }
}

actor EncryptedMessageOutbox: MessageOutboxStoring {
    private let store: EncryptedFileStore<[String: [PendingMessageRecord]]>
    private let outboxId = "message-outbox"

    init(
        keychain: KeychainCredentialStore,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.store = EncryptedFileStore(
            directoryName: "MessageOutbox",
            keyAccount: "message-outbox",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
    }

    func enqueue(_ message: ChatMessage, conversation: Conversation) async throws {
        var pending = try await allPendingMessages()
        var roomRecords = pending[conversation.conversationId, default: []]
        roomRecords.removeAll { $0.message.id == message.id }
        roomRecords.append(
            PendingMessageRecord(
                conversationId: conversation.conversationId,
                message: message,
                transactionId: message.id
            )
        )
        pending[conversation.conversationId] = roomRecords.sorted { $0.queuedAt < $1.queuedAt }
        try await store.save(pending, id: outboxId)
    }

    func pendingMessages(for conversationId: String) async throws -> [ChatMessage] {
        try await pendingRecords(for: conversationId).map(\.message)
    }

    func pendingRecords(for conversationId: String) async throws -> [PendingMessageRecord] {
        try await allPendingMessages()[conversationId, default: []]
    }

    func pendingMessageCount() async throws -> Int {
        try await allPendingMessages().values.reduce(0) { $0 + $1.count }
    }

    func recordAttempt(messageId: String, conversationId: String, error: String, retryAfter: TimeInterval) async throws {
        var pending = try await allPendingMessages()
        let now = Date()
        pending[conversationId, default: []] = pending[conversationId, default: []].map { record in
            guard record.message.id == messageId else { return record }
            var updated = record
            updated.attemptCount += 1
            updated.lastAttemptAt = now
            updated.nextRetryAt = now.addingTimeInterval(retryAfter)
            updated.lastError = error
            if updated.attemptCount >= 3 {
                updated.message.deliveryState = .failed
            }
            return updated
        }
        try await store.save(pending, id: outboxId)
    }

    func removeMessage(id: String, conversationId: String) async throws {
        var pending = try await allPendingMessages()
        pending[conversationId, default: []].removeAll { $0.message.id == id }
        if pending[conversationId]?.isEmpty == true {
            pending.removeValue(forKey: conversationId)
        }
        try await store.save(pending, id: outboxId)
    }

    @discardableResult
    func discardPendingMessages(for conversationId: String) async throws -> Int {
        var pending = try await allPendingMessages()
        let removed = pending[conversationId, default: []].count
        guard removed > 0 else { return 0 }
        pending.removeValue(forKey: conversationId)
        try await store.save(pending, id: outboxId)
        return removed
    }

    func clear() async throws {
        try await store.delete(id: outboxId)
    }

    private func allPendingMessages() async throws -> [String: [PendingMessageRecord]] {
        try await store.load(id: outboxId) ?? [:]
    }
}

actor EncryptedMessageHistoryStore: MessageHistoryStoring {
    private struct PageDescriptor: Codable, Equatable, Sendable {
        var id: String
        var firstSentAt: Date
        var lastSentAt: Date
        var count: Int
    }

    private struct Manifest: Codable, Equatable, Sendable {
        var pages: [PageDescriptor] = []
    }

    private let pageStore: EncryptedFileStore<[ChatMessage]>
    private let manifestStore: EncryptedFileStore<Manifest>
    private let conversationIndexStore: EncryptedFileStore<[String]>
    private let conversationIndexID = "message-history-index"
    private let maxMessagesPerConversation: Int
    private let defaultPageSize: Int

    init(
        keychain: KeychainCredentialStore,
        maxMessagesPerConversation: Int = 10_000,
        defaultPageSize: Int = TimelineWindowPolicy.mobile.initialMessageLimit,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.pageStore = EncryptedFileStore(
            directoryName: "MessageHistory",
            keyAccount: "message-history",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
        self.manifestStore = EncryptedFileStore(
            directoryName: "MessageHistory",
            keyAccount: "message-history",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
        self.conversationIndexStore = EncryptedFileStore(
            directoryName: "MessageHistory",
            keyAccount: "message-history",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
        self.maxMessagesPerConversation = maxMessagesPerConversation
        self.defaultPageSize = defaultPageSize
    }

    func messages(for conversationId: String) async throws -> [ChatMessage] {
        try await messagePage(
            for: conversationId,
            before: nil,
            limit: defaultPageSize
        ).messages
    }

    func messagePage(
        for conversationId: String,
        before: Date?,
        limit: Int
    ) async throws -> MessageHistoryPage {
        let boundedLimit = max(1, limit)
        let manifest = try await loadManifest(for: conversationId)
        var collected: [ChatMessage] = []

        for descriptor in manifest.pages.reversed() {
            if let before, descriptor.firstSentAt >= before {
                continue
            }
            let page = try await loadPage(descriptor, conversationId: conversationId)
            let eligible = page.filter { before == nil || $0.sentAt < before! }
            collected.append(contentsOf: eligible)
            if collected.count >= boundedLimit {
                break
            }
        }

        let normalized = normalized(collected)
        let result = Array(normalized.suffix(boundedLimit))
        let hasEarlier = result.first.map { first in
            manifest.pages.contains { descriptor in
                descriptor.firstSentAt < first.sentAt
            }
        } ?? false
        return MessageHistoryPage(
            messages: result,
            hasEarlier: hasEarlier
        )
    }

    func saveMessages(_ messages: [ChatMessage], conversationId: String) async throws {
        try await mergeAndPersist(messages, conversationId: conversationId)
    }

    func appendMessage(_ message: ChatMessage, conversationId: String) async throws {
        try await mergeAndPersist([message], conversationId: conversationId)
    }

    func removeMessages(for conversationId: String) async throws {
        let manifest = try await loadManifest(for: conversationId)
        for page in manifest.pages {
            try await pageStore.delete(id: pageStorageID(page.id, conversationId: conversationId))
        }
        try await manifestStore.delete(id: manifestStorageID(for: conversationId))
        var ids = try await conversationIDs()
        ids.removeAll { $0 == conversationId }
        try await conversationIndexStore.save(ids, id: conversationIndexID)
    }

    func clear() async throws {
        for conversationID in try await conversationIDs() {
            let manifest = try await loadManifest(for: conversationID)
            for page in manifest.pages {
                try await pageStore.delete(id: pageStorageID(page.id, conversationId: conversationID))
            }
            try await manifestStore.delete(id: manifestStorageID(for: conversationID))
        }
        try await conversationIndexStore.delete(id: conversationIndexID)
    }

    private func mergeAndPersist(
        _ incoming: [ChatMessage],
        conversationId: String
    ) async throws {
        let incoming = normalized(incoming)
        guard let firstIncoming = incoming.first,
              let lastIncoming = incoming.last else {
            return
        }

        var manifest = try await loadManifest(for: conversationId)
        var affected = manifest.pages.filter {
            $0.lastSentAt >= firstIncoming.sentAt && $0.firstSentAt <= lastIncoming.sentAt
        }
        if affected.isEmpty,
           let latest = manifest.pages.last,
           firstIncoming.sentAt >= latest.lastSentAt,
           latest.count < defaultPageSize {
            affected = [latest]
        } else if affected.isEmpty,
                  let earliest = manifest.pages.first,
                  lastIncoming.sentAt <= earliest.firstSentAt,
                  earliest.count < defaultPageSize {
            affected = [earliest]
        }
        var mergedMessages = incoming
        for descriptor in affected {
            mergedMessages.append(contentsOf: try await loadPage(descriptor, conversationId: conversationId))
            try await pageStore.delete(
                id: pageStorageID(descriptor.id, conversationId: conversationId)
            )
        }
        manifest.pages.removeAll { descriptor in
            affected.contains { $0.id == descriptor.id }
        }

        for chunk in normalized(mergedMessages).chunked(into: defaultPageSize) {
            guard let first = chunk.first, let last = chunk.last else { continue }
            let id = UUID().uuidString
            try await pageStore.save(
                chunk,
                id: pageStorageID(id, conversationId: conversationId)
            )
            manifest.pages.append(
                PageDescriptor(
                    id: id,
                    firstSentAt: first.sentAt,
                    lastSentAt: last.sentAt,
                    count: chunk.count
                )
            )
        }
        manifest.pages.sort {
            $0.firstSentAt == $1.firstSentAt
                ? $0.id < $1.id
                : $0.firstSentAt < $1.firstSentAt
        }
        try await trim(&manifest, conversationId: conversationId)
        try await manifestStore.save(manifest, id: manifestStorageID(for: conversationId))

        var ids = try await conversationIDs()
        if !ids.contains(conversationId) {
            ids.append(conversationId)
            try await conversationIndexStore.save(ids.sorted(), id: conversationIndexID)
        }
    }

    private func conversationIDs() async throws -> [String] {
        try await conversationIndexStore.load(id: conversationIndexID) ?? []
    }

    private func loadManifest(for conversationID: String) async throws -> Manifest {
        try await manifestStore.load(id: manifestStorageID(for: conversationID)) ?? Manifest()
    }

    private func loadPage(
        _ descriptor: PageDescriptor,
        conversationId: String
    ) async throws -> [ChatMessage] {
        try await pageStore.load(
            id: pageStorageID(descriptor.id, conversationId: conversationId)
        ) ?? []
    }

    private func trim(
        _ manifest: inout Manifest,
        conversationId: String
    ) async throws {
        var total = manifest.pages.reduce(0) { $0 + $1.count }
        while total > maxMessagesPerConversation,
              let oldest = manifest.pages.first {
            manifest.pages.removeFirst()
            total -= oldest.count
            try await pageStore.delete(
                id: pageStorageID(oldest.id, conversationId: conversationId)
            )
        }
    }

    private func manifestStorageID(for conversationID: String) -> String {
        "\(Self.conversationDigest(conversationID))-manifest"
    }

    private func pageStorageID(_ pageID: String, conversationId: String) -> String {
        "\(Self.conversationDigest(conversationId))-page-\(pageID)"
    }

    private static func conversationDigest(_ conversationID: String) -> String {
        let digest = SHA256.hash(data: Data(conversationID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalized(_ messages: [ChatMessage]) -> [ChatMessage] {
        var byId: [String: ChatMessage] = [:]
        byId.reserveCapacity(messages.count)
        for message in messages {
            byId[message.id] = message
        }
        return byId.values.sorted {
            $0.sentAt == $1.sentAt ? $0.id < $1.id : $0.sentAt < $1.sentAt
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}

actor EncryptedCrisisEventLog: CrisisEventLogging {
    private let store: EncryptedFileStore<[CrisisEventLogEntry]>

    init(keychain: KeychainCredentialStore) {
        self.store = EncryptedFileStore(
            directoryName: "CrisisEventLog",
            keyAccount: "crisis-event-log",
            keychain: keychain
        )
    }

    func append(_ entry: CrisisEventLogEntry) async throws {
        var events = try await entries(for: entry.subjectId, limit: Int.max)
        events.append(entry)
        let trimmed = Array(events.suffix(500))
        try await store.save(trimmed, id: entry.subjectId)
    }

    func entries(for subjectId: String, limit: Int) async throws -> [CrisisEventLogEntry] {
        let events = try await store.load(id: subjectId) ?? []
        guard limit < events.count else { return events }
        return Array(events.suffix(max(0, limit)))
    }

    func clear(for subjectId: String) async throws {
        try await store.delete(id: subjectId)
    }
}

private struct SeenRelayEnvelope: Codable, Equatable, Sendable {
    var envelopeId: String
    var expiresAt: Date
}

actor EncryptedCrisisRelayReplayStore: CrisisRelayReplayProtecting {
    private let store: EncryptedFileStore<[SeenRelayEnvelope]>

    init(keychain: KeychainCredentialStore) {
        self.store = EncryptedFileStore(
            directoryName: "CrisisRelayReplay",
            keyAccount: "crisis-relay-replay",
            keychain: keychain
        )
    }

    func hasSeen(envelopeId: String, subjectId: String) async throws -> Bool {
        let now = Date()
        return try await store.load(id: subjectId)?
            .contains { $0.envelopeId == envelopeId && $0.expiresAt > now } ?? false
    }

    func markSeen(envelopeId: String, subjectId: String, expiresAt: Date) async throws {
        var items = try await store.load(id: subjectId) ?? []
        items.removeAll { $0.envelopeId == envelopeId || $0.expiresAt <= Date() }
        items.append(SeenRelayEnvelope(envelopeId: envelopeId, expiresAt: expiresAt))
        try await store.save(Array(items.suffix(1_000)), id: subjectId)
    }

    func clearExpired(subjectId: String, now: Date) async throws {
        let items = try await store.load(id: subjectId) ?? []
        try await store.save(items.filter { $0.expiresAt > now }, id: subjectId)
    }
}

actor EncryptedCrisisRelayQueueStore: CrisisRelayQueueStoring {
    private let store: EncryptedFileStore<[CrisisRelayEnvelope]>

    init(
        keychain: KeychainCredentialStore,
        rootDirectory: URL? = nil,
        fixedKeyData: Data? = nil
    ) {
        self.store = EncryptedFileStore(
            directoryName: "CrisisRelayQueue",
            keyAccount: "crisis-relay-queue",
            keychain: keychain,
            rootDirectory: rootDirectory,
            fixedKeyData: fixedKeyData
        )
    }

    func queuedEnvelopes(subjectId: String, now: Date) async throws -> [CrisisRelayEnvelope] {
        let envelopes = try await store.load(id: subjectId) ?? []
        let retained = Array(envelopes.filter { $0.expiresAt > now }.suffix(256))
        if retained.count != envelopes.count {
            try await store.save(retained, id: subjectId)
        }
        return retained
    }

    func saveQueuedEnvelopes(_ envelopes: [CrisisRelayEnvelope], subjectId: String) async throws {
        try await store.save(Array(envelopes.suffix(256)), id: subjectId)
    }

    func clear(subjectId: String) async throws {
        try await store.delete(id: subjectId)
    }
}
