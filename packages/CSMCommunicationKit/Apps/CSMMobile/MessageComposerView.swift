import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageComposer: View {
    @Binding var text: String
    var onSend: () -> Void
    var onSendDraft: (OutgoingMessageDraft) -> Void
    var onAssist: () -> Void
    var aiAgentAvailable = false
    var mentionCandidates: [ConversationMember] = []
    var locationShareProvider:
        (@MainActor @Sendable () async throws -> CSMCommunicationLocation)?
    var sendBlockedMessage: String?
    var sendBlockedActionTitle: String?
    var onSendBlockedAction: (() -> Void)?
    @Binding var replyTo: MessageReplyReference?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var showingDocumentImporter = false
    @State private var isPreparingAttachment = false
    @State private var isResolvingLocation = false
    @State private var composerErrorTitle = ""
    @State private var attachmentErrorMessage: String?
    @State private var isEmojiBarVisible = false
    @StateObject private var voiceRecorder = VoiceNoteRecorder()

    private let quickEmoji = ["👍", "❤️", "😂", "🙏", "✅", "👀", "😮", "😢", "🔥", "⚠️", "📍", "🚒"]

    var body: some View {
        VStack(spacing: 6) {
            if let sendBlockedMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark")
                        .foregroundStyle(CSMTheme.warningAmber)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sendBlockedMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let sendBlockedActionTitle, let onSendBlockedAction {
                            Button(action: onSendBlockedAction) {
                                Label(sendBlockedActionTitle, systemImage: "key.horizontal.fill")
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(CSMTheme.warningAmber)
                            .accessibilityIdentifier("chat.messageComposerBlockedAction")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(CSMTheme.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
                .accessibilityIdentifier("chat.messageComposerBlocked")
            }

            if let replyTo {
                HStack(spacing: 8) {
                    ReplyReferenceView(reply: replyTo)
                    Button {
                        self.replyTo = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(CSMLocalization.text("composer.reply.cancel", fallback: "Zrušit odpověď"))
                }
            }

            if let recorderError = voiceRecorder.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(CSMTheme.warningAmber)
                    Text(recorderError)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(CSMTheme.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
            }

            if isEmojiBarVisible {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickEmoji, id: \.self) { emoji in
                            Button {
                                insertEmoji(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.title3)
                                    .frame(width: 38, height: 38)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat.emoji.\(emoji)")
                            .accessibilityLabel(CSMLocalization.text("composer.emoji.insert", fallback: "Vložit %@", emoji))
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .accessibilityIdentifier("chat.emojiBar")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if !interactionSuggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(interactionSuggestions.prefix(6)) { suggestion in
                        Button {
                            text = suggestion.value
                        } label: {
                            ChatInteractionSuggestionRow(suggestion: suggestion)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.composerSuggestion.\(suggestion.kind.rawValue)")

                        if suggestion.id != interactionSuggestions.prefix(6).last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityIdentifier("chat.composerSuggestions")
            }

            HStack(spacing: 10) {
                Menu {
                    Button {
                        showingCamera = true
                    } label: {
                        Label(CSMLocalization.text("composer.attachment.camera", fallback: "Vyfotit"), systemImage: "camera.fill")
                    }
                    .disabled(isSendBlocked || isPreparingAttachment)

                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label(CSMLocalization.text("composer.attachment.photo_video", fallback: "Foto nebo video"), systemImage: "photo.on.rectangle")
                    }
                    .disabled(isSendBlocked || isPreparingAttachment)

                    Button {
                        showingDocumentImporter = true
                    } label: {
                        Label(CSMLocalization.text("composer.attachment.document", fallback: "Dokument"), systemImage: "doc.fill")
                    }
                    .disabled(isSendBlocked)

                    Button {
                        Task {
                            await sendCurrentLocation()
                        }
                    } label: {
                        Label(
                            CSMLocalization.text(
                                "composer.attachment.location",
                                fallback: "Sdílet aktuální polohu"
                            ),
                            systemImage: "location.fill"
                        )
                    }
                    .disabled(
                        isSendBlocked
                            || isResolvingLocation
                            || locationShareProvider == nil
                    )

                    Button {
                        onAssist()
                    } label: {
                        Label(
                            CSMLocalization.text("composer.action.local_summary", fallback: "Shrnout v telefonu"),
                            systemImage: "text.alignleft"
                        )
                    }

                    Button {
                        withAnimation(.snappy) {
                            isEmojiBarVisible.toggle()
                        }
                    } label: {
                        Label(CSMLocalization.text("composer.action.emoji", fallback: "Emotikony"), systemImage: "face.smiling")
                    }
                    .disabled(isSendBlocked)

                    Section(CSMLocalization.text("composer.quick_status.section", fallback: "Rychlý status")) {
                        ForEach(CrisisQuickStatus.allCases) { status in
                            Button {
                                sendQuickStatus(status)
                            } label: {
                                Label(status.label, systemImage: status.systemImage)
                            }
                            .disabled(isSendBlocked)
                        }
                    }
                } label: {
                    if isPreparingAttachment || isResolvingLocation {
                        ProgressView()
                            .frame(width: 38, height: 38)
                            .accessibilityLabel(
                                isResolvingLocation
                                    ? CSMLocalization.text(
                                        "composer.location.resolving",
                                        fallback: "Zjišťuji polohu"
                                    )
                                    : CSMLocalization.text(
                                        "composer.attachment.preparing",
                                        fallback: "Připravuji přílohu"
                                    )
                            )
                    } else {
                        ComposerIconButton(systemImage: "plus", tint: .primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(CSMLocalization.text("composer.action.add_attachment", fallback: "Přidat přílohu"))
                .accessibilityIdentifier("chat.composerActions")

                HStack(spacing: 6) {
                    if voiceRecorder.isRecording {
                        VoiceRecordingControls(
                            elapsedSeconds: voiceRecorder.elapsedSeconds,
                            onCancel: {
                                voiceRecorder.cancel()
                            },
                            onStop: {
                                stopVoiceRecording()
                            }
                        )
                        .frame(maxWidth: .infinity)
                    } else {
                        TextField(CSMLocalization.text("composer.message.placeholder", fallback: "Zpráva"), text: $text, axis: .vertical)
                            .lineLimit(1...5)
                            .disabled(isSendBlocked)
                            .accessibilityLabel(CSMLocalization.text("composer.message.placeholder", fallback: "Zpráva"))
                            .accessibilityIdentifier("chat.messageComposer")

                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                Task {
                                    await voiceRecorder.start()
                                }
                            } label: {
                                Image(systemName: "mic.fill")
                                    .font(.title3.weight(.medium))
                                    .foregroundStyle(CSMTheme.signalBlue)
                                    .frame(width: 38, height: 38)
                            }
                            .buttonStyle(.plain)
                            .disabled(isSendBlocked)
                            .accessibilityLabel(CSMLocalization.text("composer.action.record_voice", fallback: "Nahrát hlasovou poznámku"))
                        } else {
                            Button(action: onSend) {
                                Image(systemName: "arrow.up")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(CSMTheme.signalBlue, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isSendBlocked)
                            .accessibilityLabel(CSMLocalization.text("composer.action.send_message", fallback: "Odeslat zprávu"))
                        }
                    }
                }
                .padding(.leading, 16)
                .padding(.trailing, 4)
                .padding(.vertical, 4)
                .frame(minHeight: 46)
                .glassEffect(.regular.tint(CSMTheme.signalBlue.opacity(0.04)).interactive(), in: .capsule)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { result in
                showingCamera = false
                switch result {
                case let .success(url):
                    Task {
                        defer { try? FileManager.default.removeItem(at: url) }
                        do {
                            try await prepareAndSendMedia(
                                sourceURL: url,
                                kind: .image,
                                title: CSMLocalization.text("composer.attachment.photo_title", fallback: "Fotografie"),
                                mimeType: "image/jpeg"
                            )
                        } catch {
                            presentAttachmentError(error)
                        }
                    }
                case let .failure(error):
                    if !(error is CancellationError) {
                        presentAttachmentError(error)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                await sendPhotoOrVideo(item)
                selectedPhotoItem = nil
            }
        }
        .fileImporter(
            isPresented: $showingDocumentImporter,
            allowedContentTypes: MessageAttachmentImportTypes.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleDocumentImport(result)
        }
        .alert(
            composerErrorTitle.isEmpty
                ? CSMLocalization.text("composer.attachment.error_title", fallback: "Přílohu nelze přidat")
                : composerErrorTitle,
            isPresented: Binding(
                get: { attachmentErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        attachmentErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(attachmentErrorMessage ?? "")
        }
    }

    private var interactionSuggestions: [ChatInteractionSuggestion] {
        guard !isSendBlocked else { return [] }
        return ChatInteractionRegistry.suggestions(
            for: text,
            aiAgentAvailable: aiAgentAvailable,
            members: mentionCandidates
        )
    }

    private var isSendBlocked: Bool {
        sendBlockedMessage != nil
    }

    private func sendPhotoOrVideo(_ item: PhotosPickerItem) async {
        guard !isSendBlocked else { return }
        isPreparingAttachment = true
        defer { isPreparingAttachment = false }
        let contentType = item.supportedContentTypes.first
        let kind: MessageAttachmentKind = contentType?.conforms(to: .movie) == true ? .video : .image
        let title = kind == .video
            ? CSMLocalization.text("composer.attachment.video_title", fallback: "Video")
            : CSMLocalization.text("composer.attachment.photo_title", fallback: "Fotografie")
        do {
            let sourceURL: URL?
            if kind == .video {
                sourceURL = try await item.loadTransferable(type: PickedMovieFile.self)?.url
            } else {
                sourceURL = try await item.loadTransferable(type: PickedImageFile.self)?.url
            }
            guard let sourceURL else {
                throw MessageAttachmentImportError.unreadableSelection
            }
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            try await prepareAndSendMedia(
                sourceURL: sourceURL,
                kind: kind,
                title: title,
                mimeType: contentType?.preferredMIMEType
            )
        } catch {
            presentAttachmentError(error)
        }
    }

    private func prepareAndSendMedia(
        sourceURL: URL,
        kind: MessageAttachmentKind,
        title: String,
        mimeType: String?
    ) async throws {
        guard !isSendBlocked else { return }
        isPreparingAttachment = true
        defer { isPreparingAttachment = false }
        let attachment = try await MediaPipelineActor.shared.prepare(
            sourceURL: sourceURL,
            kind: kind,
            title: title,
            mimeType: mimeType
        )
        let draft = OutgoingMessageDraft(
            body: attachment.title,
            attachments: [attachment],
            replyTo: replyTo
        )
        if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
            await MediaPipelineActor.shared.removeOwnedFile(for: attachment)
            throw CSMServiceError.invalidState(validationError)
        }
        onSendDraft(
            draft
        )
    }

    private func handleDocumentImport(_ result: Result<[URL], any Error>) {
        guard !isSendBlocked else { return }
        guard case let .success(urls) = result else {
            if case let .failure(error) = result {
                presentAttachmentError(error)
            }
            return
        }
        Task {
            isPreparingAttachment = true
            defer { isPreparingAttachment = false }
            var attachments: [MessageAttachment] = []
            for url in urls.prefix(MessageAttachmentPolicy.maxAttachmentCount) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let contentType = MessageAttachmentImportTypes.contentType(for: url)
                let kind: MessageAttachmentKind = contentType?.conforms(to: .image) == true
                    ? .image
                    : (contentType?.conforms(to: .movie) == true ? .video : .document)
                do {
                    let attachment = try await MediaPipelineActor.shared.prepare(
                        sourceURL: url,
                        kind: kind,
                        title: url.lastPathComponent,
                        mimeType: contentType?.preferredMIMEType
                    )
                    attachments.append(attachment)
                } catch {
                    presentAttachmentError(error)
                }
            }
            guard !attachments.isEmpty else { return }
            let draft = OutgoingMessageDraft(
                body: documentDraftBody(for: attachments),
                attachments: attachments,
                replyTo: replyTo
            )
            if let validationError = MessageAttachmentPolicy.validationError(for: draft) {
                for attachment in attachments {
                    await MediaPipelineActor.shared.removeOwnedFile(for: attachment)
                }
                presentAttachmentError(CSMServiceError.invalidState(validationError))
                return
            }
            onSendDraft(draft)
        }
    }

    private func presentAttachmentError(_ error: any Error) {
        composerErrorTitle = CSMLocalization.text(
            "composer.attachment.error_title",
            fallback: "Přílohu nelze přidat"
        )
        attachmentErrorMessage = (error as? LocalizedError)?.errorDescription
            ?? CSMLocalization.text(
                "composer.attachment.error_message",
                fallback: "Vybraný soubor se nepodařilo připravit. Zkuste jinou fotografii nebo soubor."
            )
    }

    @MainActor
    private func sendCurrentLocation() async {
        guard !isSendBlocked else { return }
        guard let locationShareProvider else { return }
        isResolvingLocation = true
        defer { isResolvingLocation = false }

        do {
            let location = try await locationShareProvider()
            guard
                location.latitude.isFinite,
                location.longitude.isFinite,
                (-90...90).contains(location.latitude),
                (-180...180).contains(location.longitude)
            else {
                throw CSMCommunicationLocationShareError.unavailable
            }
            let title = location.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let attachment = MessageAttachment(
                kind: .location,
                title: title?.isEmpty == false
                    ? title!
                    : CSMLocalization.text("composer.location.my_location", fallback: "Moje poloha"),
                location: GeoPoint(
                    lat: location.latitude,
                    lon: location.longitude,
                    accuracyM: location.accuracyMeters,
                    source: "device"
                ),
                localOnly: false
            )
            onSendDraft(OutgoingMessageDraft(
                body: CSMLocalization.text(
                    "composer.location.shared_body",
                    fallback: "Moje poloha"
                ),
                attachments: [attachment],
                replyTo: replyTo
            ))
        } catch {
            composerErrorTitle = CSMLocalization.text(
                "composer.location.error_title",
                fallback: "Polohu nelze sdílet"
            )
            attachmentErrorMessage = (error as? LocalizedError)?.errorDescription
                ?? CSMLocalization.text(
                    "composer.location.error_message",
                    fallback: "Aktuální polohu se nepodařilo zjistit. Zkuste to znovu."
                )
        }
    }

    private func sendQuickStatus(_ status: CrisisQuickStatus) {
        guard !isSendBlocked else { return }
        onSendDraft(
            OutgoingMessageDraft(
                body: status.messageBody(),
                attachments: [status.messageAttachment(localOnly: false)],
                replyTo: replyTo
            )
        )
    }

    private func stopVoiceRecording() {
        Task {
            guard let attachment = await voiceRecorder.stop() else { return }
            guard !isSendBlocked else { return }
            onSendDraft(OutgoingMessageDraft(
                body: CSMLocalization.text("composer.voice_note.title", fallback: "Hlasová poznámka"),
                attachments: [attachment],
                replyTo: replyTo
            ))
        }
    }

    private func insertEmoji(_ emoji: String) {
        guard !isSendBlocked else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = emoji
        } else if text.last?.isWhitespace == true {
            text += emoji
        } else {
            text += " \(emoji)"
        }
    }

    private func documentDraftBody(for attachments: [MessageAttachment]) -> String {
        if attachments.count == 1, let attachment = attachments.first {
            return attachment.title
        }
        return CSMLocalization.text("composer.attachment.multiple_body", fallback: "%d příloh", attachments.count)
    }
}

private enum MessageAttachmentImportError: LocalizedError {
    case cameraUnavailable
    case captureFailed
    case unreadableSelection

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return CSMLocalization.text(
                "composer.attachment.camera_unavailable",
                fallback: "Fotoaparát není na tomto zařízení dostupný."
            )
        case .captureFailed:
            return CSMLocalization.text(
                "composer.attachment.capture_failed",
                fallback: "Fotografii se nepodařilo uložit. Zkuste ji pořídit znovu."
            )
        case .unreadableSelection:
            return CSMLocalization.text(
                "composer.attachment.selection_unreadable",
                fallback: "Vybranou položku se nepodařilo načíst. Zkuste jinou fotografii nebo video."
            )
        }
    }
}

private struct CameraCaptureView: UIViewControllerRepresentable {
    var onCompletion: (Result<URL, any Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.async {
                onCompletion(.failure(MessageAttachmentImportError.cameraUnavailable))
            }
            return UIViewController()
        }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCompletion: (Result<URL, any Error>) -> Void
        private var didComplete = false

        init(onCompletion: @escaping (Result<URL, any Error>) -> Void) {
            self.onCompletion = onCompletion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            complete(.failure(CancellationError()))
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.86) else {
                complete(.failure(MessageAttachmentImportError.captureFailed))
                return
            }

            do {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("csm-camera-\(UUID().uuidString)")
                    .appendingPathExtension("jpg")
                try data.write(to: url, options: [.atomic])
                complete(.success(url))
            } catch {
                complete(.failure(error))
            }
        }

        private func complete(_ result: Result<URL, any Error>) {
            guard !didComplete else { return }
            didComplete = true
            onCompletion(result)
        }
    }
}

private protocol PickedMediaFile: Transferable {
    var url: URL { get }
    init(url: URL)
}

private extension PickedMediaFile {
    static func importedCopy(of sourceURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-photo-picker", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(sourceURL.pathExtension)
        try FileManager.default.copyItem(at: sourceURL, to: target)
        return target
    }
}

private struct PickedImageFile: PickedMediaFile {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .image) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            Self(url: try importedCopy(of: received.file))
        }
    }
}

private struct PickedMovieFile: PickedMediaFile {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { value in
            SentTransferredFile(value.url)
        } importing: { received in
            Self(url: try importedCopy(of: received.file))
        }
    }
}

private struct ChatInteractionSuggestionRow: View {
    var suggestion: ChatInteractionSuggestion

    private var tint: Color {
        suggestion.kind == .ai ? CSMTheme.secureGreen : CSMTheme.signalBlue
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: suggestion.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(suggestion.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private enum MessageAttachmentImportTypes {
    static let allowedContentTypes: [UTType] = [
        .pdf,
        .plainText,
        .image,
        .movie,
        .data,
        type(extension: "doc", identifier: "com.microsoft.word.doc"),
        type(extension: "docx", identifier: "org.openxmlformats.wordprocessingml.document"),
        type(extension: "xls", identifier: "com.microsoft.excel.xls"),
        type(extension: "xlsx", identifier: "org.openxmlformats.spreadsheetml.sheet"),
        type(extension: "ppt", identifier: "com.microsoft.powerpoint.ppt"),
        type(extension: "pptx", identifier: "org.openxmlformats.presentationml.presentation"),
        type(extension: "csv", identifier: "public.comma-separated-values-text"),
        type(extension: "zip", identifier: "public.zip-archive"),
        type(extension: "7z", identifier: "org.7-zip.7-zip-archive"),
        type(extension: "rar", identifier: "com.rarlab.rar-archive"),
        type(extension: "dwg", identifier: "com.autodesk.dwg"),
        type(extension: "dxf", identifier: "com.autodesk.dxf"),
        type(extension: "ifc", identifier: "org.buildingsmart.ifc"),
        type(extension: "pln", identifier: "com.graphisoft.archicad.project"),
        type(extension: "rvt", identifier: "com.autodesk.revit.project"),
        type(extension: "skp", identifier: "com.sketchup.skp"),
        type(extension: "geojson", identifier: "public.geojson"),
        type(extension: "kml", identifier: "com.google.earth.kml"),
        type(extension: "kmz", identifier: "com.google.earth.kmz")
    ]

    static func contentType(for url: URL) -> UTType? {
        UTType(filenameExtension: url.pathExtension)
    }

    private static func type(extension fileExtension: String, identifier: String) -> UTType {
        UTType(filenameExtension: fileExtension) ?? UTType(importedAs: identifier)
    }
}

private struct ComposerIconButton: View {
    var systemImage: String
    var tint: Color
    var prominent = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(prominent ? .white : tint)
            .frame(width: 38, height: 38)
            .background(
                prominent ? tint : tint.opacity(0.10),
                in: Circle()
            )
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(prominent ? 0 : 0.16), lineWidth: 1)
            }
            .csmGlassSurface(tint: tint, cornerRadius: 19, interactive: true)
    }
}

struct VoiceRecordingControls: View {
    var elapsedSeconds: TimeInterval
    var onCancel: () -> Void
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(elapsedText, systemImage: "record.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CSMTheme.criticalRed)
                .monospacedDigit()

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(CSMLocalization.text("composer.voice.cancel", fallback: "Zrušit nahrávku"))

            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.glassProminent)
            .accessibilityLabel(CSMLocalization.text("composer.voice.send", fallback: "Odeslat hlasovou poznámku"))
        }
        .frame(minWidth: 126)
    }

    private var elapsedText: String {
        let total = max(0, Int(elapsedSeconds.rounded(.down)))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

@MainActor
final class VoiceNoteRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var lastError: String?

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var timer: Timer?

    func start() async {
        guard !isRecording else { return }

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            lastError = CSMLocalization.text("composer.voice.microphone_denied", fallback: "Přístup k mikrofonu nebyl povolen.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("csm-voice-\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 24_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw CSMServiceError.unavailable(CSMLocalization.text("composer.voice.start_failed", fallback: "Nahrávání hlasové poznámky se nepodařilo spustit."))
            }

            self.recorder = recorder
            recordingURL = url
            recordingStartedAt = .now
            elapsedSeconds = 0
            lastError = nil
            isRecording = true
            startTimer()
        } catch {
            cleanupRecordingFile()
            lastError = error.localizedDescription
            isRecording = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func stop() async -> MessageAttachment? {
        guard isRecording, let recorder, let recordingStartedAt else { return nil }
        let url = recorder.url
        recorder.stop()
        stopTimer()
        isRecording = false
        elapsedSeconds = Date().timeIntervalSince(recordingStartedAt)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        defer { cleanupRecordingFile(at: url) }

        guard elapsedSeconds >= 0.8 else {
            lastError = CSMLocalization.text("composer.voice.too_short", fallback: "Hlasová poznámka je příliš krátká.")
            return nil
        }

        do {
            let attachment = try await MediaPipelineActor.shared.prepare(
                sourceURL: url,
                kind: .voiceNote,
                title: CSMLocalization.text("composer.voice_note.title", fallback: "Hlasová poznámka"),
                mimeType: "audio/mp4",
                durationSeconds: elapsedSeconds
            )
            lastError = nil
            return attachment
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func cancel() {
        recorder?.stop()
        stopTimer()
        cleanupRecordingFile()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        elapsedSeconds = 0
        lastError = nil
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription ?? CSMLocalization.text("composer.voice.failed", fallback: "Nahrávání hlasové poznámky selhalo.")
            self.cancel()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recordingStartedAt = self.recordingStartedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(recordingStartedAt)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func cleanupRecordingFile() {
        if let recordingURL {
            cleanupRecordingFile(at: recordingURL)
        }
        recorder = nil
        recordingURL = nil
        recordingStartedAt = nil
    }

    private func cleanupRecordingFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
