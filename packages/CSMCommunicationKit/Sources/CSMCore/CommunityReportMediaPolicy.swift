import Foundation

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

enum CommunityReportMediaWarning: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case imageMetadataStripped = "image_metadata_stripped"
    case imageMetadataCouldNotBeStripped = "image_metadata_could_not_be_stripped"
    case payloadLooksTooSmall = "payload_looks_too_small"
    case retentionLimited = "retention_limited"

    var userMessage: String {
        switch self {
        case .imageMetadataStripped:
            return CSMLocalization.text(
                "media.warning.image.stripped",
                fallback: "Metadata obrázku byla před uložením odstraněna."
            )
        case .imageMetadataCouldNotBeStripped:
            return CSMLocalization.text(
                "media.warning.image.strip.failed",
                fallback: "Metadata obrázku se nepodařilo odstranit; zvažte soukromý přístup."
            )
        case .payloadLooksTooSmall:
            return CSMLocalization.text(
                "media.warning.payload.small",
                fallback: "Příloha je neobvykle malá, zkontrolujte kvalitu důkazu."
            )
        case .retentionLimited:
            return CSMLocalization.text(
                "media.warning.retention",
                fallback: "Příloha zůstane v telefonu jen po omezenou dobu."
            )
        }
    }
}

struct CommunityReportSanitizedMediaPayload: Equatable, Sendable {
    var payload: Data
    var contentType: String
    var preferredFileExtension: String?
    var warnings: [CommunityReportMediaWarning]
}

enum CommunityReportMediaSanitizer {
    static func sanitize(
        payload: Data,
        contentType: String,
        kind: CommunityAttachmentKind
    ) -> CommunityReportSanitizedMediaPayload {
        guard kind == .photo else {
            return CommunityReportSanitizedMediaPayload(
                payload: payload,
                contentType: contentType,
                preferredFileExtension: nil,
                warnings: []
            )
        }

        #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return CommunityReportSanitizedMediaPayload(
                payload: payload,
                contentType: contentType,
                preferredFileExtension: nil,
                warnings: [.imageMetadataCouldNotBeStripped]
            )
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return CommunityReportSanitizedMediaPayload(
                payload: payload,
                contentType: contentType,
                preferredFileExtension: nil,
                warnings: [.imageMetadataCouldNotBeStripped]
            )
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return CommunityReportSanitizedMediaPayload(
                payload: payload,
                contentType: contentType,
                preferredFileExtension: nil,
                warnings: [.imageMetadataCouldNotBeStripped]
            )
        }

        return CommunityReportSanitizedMediaPayload(
            payload: output as Data,
            contentType: "image/jpeg",
            preferredFileExtension: "jpg",
            warnings: [.imageMetadataStripped]
        )
        #else
        return CommunityReportSanitizedMediaPayload(
            payload: payload,
            contentType: contentType,
            preferredFileExtension: nil,
            warnings: [.imageMetadataCouldNotBeStripped]
        )
        #endif
    }
}

struct CommunityReportMediaRetentionResult: Equatable, Sendable {
    var retainedDrafts: [CommunityReportDraft]
    var removedDrafts: [CommunityReportDraft]
}

struct CommunityReportMediaPolicy: Equatable, Sendable {
    var maxAttachmentCount: Int
    var maxPhotoBytes: Int
    var maxVideoBytes: Int
    var maxDocumentBytes: Int
    var maxDraftBytes: Int
    var maxOutboxBytes: Int
    var retentionSeconds: TimeInterval
    var minimumUsefulBytes: Int

    static let standard = CommunityReportMediaPolicy()

    init(
        maxAttachmentCount: Int = 8,
        maxPhotoBytes: Int = 20 * 1024 * 1024,
        maxVideoBytes: Int = 100 * 1024 * 1024,
        maxDocumentBytes: Int = 15 * 1024 * 1024,
        maxDraftBytes: Int = 150 * 1024 * 1024,
        maxOutboxBytes: Int = 500 * 1024 * 1024,
        retentionSeconds: TimeInterval = 72 * 60 * 60,
        minimumUsefulBytes: Int = 512
    ) {
        self.maxAttachmentCount = maxAttachmentCount
        self.maxPhotoBytes = maxPhotoBytes
        self.maxVideoBytes = maxVideoBytes
        self.maxDocumentBytes = maxDocumentBytes
        self.maxDraftBytes = maxDraftBytes
        self.maxOutboxBytes = maxOutboxBytes
        self.retentionSeconds = retentionSeconds
        self.minimumUsefulBytes = minimumUsefulBytes
    }

    func validateAttachment(
        kind: CommunityAttachmentKind,
        contentType: String,
        byteSize: Int,
        currentAttachments: [CommunityReportAttachmentDraft] = []
    ) throws -> [CommunityReportMediaWarning] {
        guard currentAttachments.count < maxAttachmentCount else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.max_attachments", fallback: "Maximální počet příloh je %d.", maxAttachmentCount)
            )
        }
        try validateAttachmentPayload(kind: kind, contentType: contentType, byteSize: byteSize)

        let draftBytes = currentAttachments.reduce(byteSize) { $0 + $1.byteSize }
        guard draftBytes <= maxDraftBytes else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.draft_limit", fallback: "Přílohy v jednom hlášení překročily mobilní limit.")
            )
        }

        return warnings(kind: kind, byteSize: byteSize)
    }

    func validateDraft(
        _ draft: CommunityReportDraft,
        existingDrafts: [CommunityReportDraft] = []
    ) throws {
        guard draft.attachments.count <= maxAttachmentCount else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.max_attachments", fallback: "Maximální počet příloh je %d.", maxAttachmentCount)
            )
        }

        for attachment in draft.attachments {
            try validateAttachmentPayload(
                kind: attachment.kind,
                contentType: attachment.contentType,
                byteSize: attachment.byteSize
            )
            guard attachment.byteSize == attachment.payload.count else {
                throw CSMServiceError.invalidState(
                    CSMLocalization.text("media.error.size_mismatch", fallback: "Velikost přílohy neodpovídá uloženému obsahu.")
                )
            }
        }

        let draftBytes = byteCount(for: draft)
        guard draftBytes <= maxDraftBytes else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.draft_limit", fallback: "Přílohy v jednom hlášení překročily mobilní limit.")
            )
        }

        let existingBytes = existingDrafts
            .filter { $0.id != draft.id }
            .reduce(0) { $0 + byteCount(for: $1) }
        guard existingBytes + draftBytes <= maxOutboxBytes else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.outbox_limit", fallback: "Přílohy uložené v telefonu překročily mobilní limit.")
            )
        }
    }

    func retentionResult(
        for drafts: [CommunityReportDraft],
        now: Date = .now
    ) -> CommunityReportMediaRetentionResult {
        var retained: [CommunityReportDraft] = []
        var removed: [CommunityReportDraft] = []

        for draft in drafts {
            if isExpired(draft, now: now) {
                removed.append(draft)
            } else {
                retained.append(draft)
            }
        }

        return CommunityReportMediaRetentionResult(retainedDrafts: retained, removedDrafts: removed)
    }

    func retentionExpiresAt(for draft: CommunityReportDraft) -> Date {
        draft.createdAt.addingTimeInterval(retentionSeconds)
    }

    func retentionExpiresAt(for attachment: CommunityReportAttachmentDraft) -> Date {
        attachment.createdAt.addingTimeInterval(retentionSeconds)
    }

    func byteCount(for draft: CommunityReportDraft) -> Int {
        draft.attachments.reduce(0) { $0 + $1.byteSize }
    }

    private func validateAttachmentPayload(
        kind: CommunityAttachmentKind,
        contentType: String,
        byteSize: Int
    ) throws {
        guard byteSize > 0 else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.empty_attachment", fallback: "Příloha je prázdná.")
            )
        }
        guard allowedContentTypes(for: kind).contains(contentType.lowercased()) else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.unsupported_type", fallback: "Tento typ přílohy není podporovaný.")
            )
        }
        guard byteSize <= maxBytes(for: kind) else {
            throw CSMServiceError.invalidState(
                CSMLocalization.text("media.error.too_large_phone", fallback: "Příloha je pro telefon příliš velká.")
            )
        }
    }

    private func warnings(kind: CommunityAttachmentKind, byteSize: Int) -> [CommunityReportMediaWarning] {
        var result: [CommunityReportMediaWarning] = [.retentionLimited]
        if byteSize < minimumUsefulBytes {
            result.append(.payloadLooksTooSmall)
        }
        return result
    }

    private func isExpired(_ draft: CommunityReportDraft, now: Date) -> Bool {
        retentionExpiresAt(for: draft) <= now
    }

    private func maxBytes(for kind: CommunityAttachmentKind) -> Int {
        switch kind {
        case .photo:
            return maxPhotoBytes
        case .video:
            return maxVideoBytes
        case .document:
            return maxDocumentBytes
        }
    }

    private func allowedContentTypes(for kind: CommunityAttachmentKind) -> Set<String> {
        switch kind {
        case .photo:
            return ["image/jpeg", "image/png", "image/heic", "image/heif", "image/webp"]
        case .video:
            return ["video/mp4", "video/quicktime"]
        case .document:
            return ["application/pdf"]
        }
    }
}
