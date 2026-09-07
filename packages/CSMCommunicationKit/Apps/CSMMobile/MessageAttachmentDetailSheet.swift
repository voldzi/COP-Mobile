import MapKit
import QuickLook
import SwiftUI
import UIKit

struct MessageAttachmentDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var attachment: MessageAttachment
    var canManageLiveLocation = false
    var activeLiveLocationShare: ActiveLiveLocationShare?
    var onStartLiveLocationShare: ((TimeInterval) async throws -> Void)?
    var onStopLiveLocationShare: (() async throws -> Void)?
    @State private var previewURL: URL?
    @State private var previewIsTemporary = false
    @State private var selectedLiveLocationDuration: TimeInterval = 60 * 60
    @State private var isUpdatingLiveLocation = false
    @State private var liveLocationErrorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    MessageAttachmentDetailHeader(attachment: attachment)
                }

                if attachment.kind == .location {
                    locationDetail
                } else {
                    Section {
                        previewContent
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    } header: {
                        Text(CSMLocalization.text("attachment.detail.preview", fallback: "Náhled"))
                    }

                    Section {
                        DetailLabelRow(
                            title: CSMLocalization.text("attachment.detail.type", fallback: "Typ"),
                            value: attachment.chatKindLabel,
                            systemImage: attachment.chatSystemImageName,
                            tint: attachment.chatTint
                        )
                        if let mimeType = attachment.mimeType, !mimeType.isEmpty {
                            DetailLabelRow(
                                title: CSMLocalization.text("attachment.detail.mime", fallback: "Formát"),
                                value: mimeType,
                                systemImage: "tag.fill",
                                tint: CSMTheme.signalBlue
                            )
                        }
                        DetailLabelRow(
                            title: CSMLocalization.text("attachment.detail.size", fallback: "Velikost"),
                            value: attachment.chatSizeText,
                            systemImage: "externaldrive.fill",
                            tint: CSMTheme.relayCyan
                        )
                        DetailLabelRow(
                            title: CSMLocalization.text("attachment.detail.availability", fallback: "Dostupnost"),
                            value: availabilityText,
                            systemImage: hasLocalContent ? "iphone" : "icloud.and.arrow.down",
                            tint: hasLocalContent ? CSMTheme.secureGreen : CSMTheme.warningAmber
                        )
                        DetailLabelRow(
                            title: CSMLocalization.text("attachment.detail.sent_at", fallback: "Přidáno"),
                            value: attachment.createdAt.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "clock.fill",
                            tint: CSMTheme.signalBlue
                        )
                    } header: {
                        Text(CSMLocalization.text("attachment.detail.metadata", fallback: "Detaily souboru"))
                    }
                }
            }
            .navigationTitle(
                attachment.kind == .location
                    ? CSMLocalization.text("location.detail.title", fallback: "Detail polohy")
                    : CSMLocalization.text("attachment.detail.title", fallback: "Detail přílohy")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(CSMLocalization.text("conversation.detail.done", fallback: "Hotovo")) {
                        dismiss()
                    }
                }
                if let previewURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: previewURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(CSMLocalization.text("attachment.detail.share", fallback: "Sdílet přílohu"))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: preparePreviewFileIfNeeded)
        .onDisappear(perform: cleanupPreviewFile)
    }

    @ViewBuilder
    private var locationDetail: some View {
        if let location = attachment.location {
            Section {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(
                                latitude: location.lat,
                                longitude: location.lon
                            ),
                            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                        )
                    ),
                    interactionModes: [.pan, .zoom]
                ) {
                    Marker(
                        attachment.title,
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.lat,
                            longitude: location.lon
                        )
                    )
                    .tint(CSMTheme.secureGreen)
                }
                .mapStyle(.standard(elevation: .realistic))
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                Button {
                    openLocationInMaps(location)
                } label: {
                    Label(
                        CSMLocalization.text("location.detail.open_maps", fallback: "Otevřít v Mapách"),
                        systemImage: "map.fill"
                    )
                }
            } header: {
                Text(CSMLocalization.text("location.detail.map", fallback: "Mapa"))
            }
        } else {
            Section {
                ContentUnavailableView(
                    CSMLocalization.text("location.detail.unavailable", fallback: "Poloha není dostupná"),
                    systemImage: "location.slash.fill",
                    description: Text(
                        CSMLocalization.text(
                            "location.detail.unavailable.description",
                            fallback: "Tato zpráva zatím neobsahuje použitelný bod v mapě."
                        )
                    )
                )
            }
        }

        Section {
            if let share = effectiveLiveLocationShare, share.isActive {
                LabeledContent(
                    CSMLocalization.text("location.live.status", fallback: "Stav"),
                    value: CSMLocalization.text("location.live.active", fallback: "Sdílení je aktivní")
                )
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent(
                        CSMLocalization.text("location.live.remaining", fallback: "Zbývá")
                    ) {
                        Text(
                            timerInterval: context.date...max(context.date, share.expiresAt),
                            countsDown: true
                        )
                        .monospacedDigit()
                    }
                }
            } else if attachment.liveLocationShare != nil {
                LabeledContent(
                    CSMLocalization.text("location.live.status", fallback: "Stav"),
                    value: CSMLocalization.text("location.live.ended", fallback: "Sdílení skončilo")
                )
            }

            if canManageLiveLocation, onStartLiveLocationShare != nil {
                Text(
                    CSMLocalization.text(
                        "location.live.explanation",
                        fallback: "Po zvolenou dobu budou lidé v tomto chatu dostávat vaši průběžně aktualizovanou polohu. Sdílení můžete kdykoli ukončit."
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Picker(
                    CSMLocalization.text("location.live.duration", fallback: "Délka sdílení"),
                    selection: $selectedLiveLocationDuration
                ) {
                    ForEach(LiveLocationDurationOption.all) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    startOrExtendLiveLocation()
                } label: {
                    Label(
                        effectiveLiveLocationShare?.isActive == true
                            ? CSMLocalization.text("location.live.extend", fallback: "Nastavit novou délku")
                            : CSMLocalization.text("location.live.start", fallback: "Sdílet živou polohu"),
                        systemImage: "location.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isUpdatingLiveLocation)

                if effectiveLiveLocationShare?.isActive == true, onStopLiveLocationShare != nil {
                    Button(role: .destructive) {
                        stopLiveLocation()
                    } label: {
                        Label(
                            CSMLocalization.text("location.live.stop", fallback: "Ukončit živé sdílení"),
                            systemImage: "stop.circle.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isUpdatingLiveLocation)
                }
            }

            if isUpdatingLiveLocation {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(CSMLocalization.text("location.live.updating", fallback: "Aktualizuji sdílení…"))
                        .foregroundStyle(.secondary)
                }
            }

            if let liveLocationErrorText {
                Label(liveLocationErrorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(CSMTheme.warningAmber)
            }
        } header: {
            Text(CSMLocalization.text("location.live.title", fallback: "Živá poloha"))
        }

        Section {
            DetailLabelRow(
                title: CSMLocalization.text("location.detail.shared_at", fallback: "Sdíleno"),
                value: attachment.createdAt.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock.fill",
                tint: CSMTheme.signalBlue
            )
            if let accuracy = attachment.location?.accuracyM, accuracy.isFinite {
                DetailLabelRow(
                    title: CSMLocalization.text("location.detail.accuracy", fallback: "Přesnost"),
                    value: "± \(Int(accuracy.rounded())) m",
                    systemImage: "scope",
                    tint: CSMTheme.secureGreen
                )
            }
        } header: {
            Text(CSMLocalization.text("location.detail.information", fallback: "Informace"))
        }
    }

    private var effectiveLiveLocationShare: ActiveLiveLocationShare? {
        if let activeLiveLocationShare {
            return activeLiveLocationShare
        }
        guard let metadata = attachment.liveLocationShare, metadata.isLive else { return nil }
        return ActiveLiveLocationShare(
            conversationId: "",
            startedAt: metadata.startedAt,
            expiresAt: metadata.expiresAt
        )
    }

    private func startOrExtendLiveLocation() {
        guard let onStartLiveLocationShare else { return }
        isUpdatingLiveLocation = true
        liveLocationErrorText = nil
        Task {
            do {
                try await onStartLiveLocationShare(selectedLiveLocationDuration)
            } catch {
                liveLocationErrorText = userFacingLiveLocationError(error)
            }
            isUpdatingLiveLocation = false
        }
    }

    private func stopLiveLocation() {
        guard let onStopLiveLocationShare else { return }
        isUpdatingLiveLocation = true
        liveLocationErrorText = nil
        Task {
            do {
                try await onStopLiveLocationShare()
            } catch {
                liveLocationErrorText = userFacingLiveLocationError(error)
            }
            isUpdatingLiveLocation = false
        }
    }

    private func userFacingLiveLocationError(_ error: Error) -> String {
        let technicalMessage = error.localizedDescription.lowercased()
        if technicalMessage.contains("forbidden") ||
            technicalMessage.contains("permission") ||
            technicalMessage.contains("send_level") {
            return CSMLocalization.text(
                "location.live.error.permission",
                fallback: "V této konverzaci nyní nelze živou polohu sdílet."
            )
        }
        return CSMLocalization.text(
            "location.live.error.retry",
            fallback: "Živou polohu se nepodařilo sdílet. Zkontrolujte připojení a zkuste to znovu."
        )
    }

    private func openLocationInMaps(_ location: GeoPoint) {
        let latitude = String(location.lat)
        let longitude = String(location.lon)
        guard let url = URL(
            string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(attachment.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Poloha")"
        ) else { return }
        openURL(url)
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image = attachment.chatPreviewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
                .accessibilityLabel(attachment.title)
        } else if let previewURL, QLPreviewController.canPreview(previewURL as NSURL) {
            AttachmentQuickLookPreview(url: previewURL)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))
        } else {
            ContentUnavailableView(
                unavailableTitle,
                systemImage: attachment.chatSystemImageName,
                description: Text(unavailableDescription)
            )
            .frame(minHeight: 220)
        }
    }

    private var availabilityText: String {
        if hasLocalContent {
            return CSMLocalization.text("attachment.detail.available_local", fallback: "Dostupné v tomto telefonu")
        }
        return CSMLocalization.text("attachment.detail.metadata_only", fallback: "Metadata jsou dostupná, obsah se načítá ze zabezpečeného chatu")
    }

    private var unavailableTitle: String {
        !hasLocalContent
            ? CSMLocalization.text("attachment.preview.remote_title", fallback: "Soubor není uložen v telefonu")
            : CSMLocalization.text("attachment.preview.unsupported_title", fallback: "Náhled není k dispozici")
    }

    private var unavailableDescription: String {
        // Remote Matrix media can be represented by safe metadata before the E2EE file flow downloads the payload.
        !hasLocalContent
            ? CSMLocalization.text("attachment.preview.remote_description", fallback: "Zobrazuji bezpečná metadata. Obsah souboru zůstává v E2EE chatu a stáhne se až přes podporovaný souborový tok.")
            : CSMLocalization.text("attachment.preview.unsupported_description", fallback: "Soubor je připravený k odeslání nebo sdílení, ale iOS pro tento formát neposkytl lokální náhled.")
    }

    private var hasLocalContent: Bool {
        if attachment.payloadData != nil {
            return true
        }
        guard let localFileURL = attachment.localFileURL else { return false }
        return FileManager.default.fileExists(atPath: localFileURL.path)
    }

    private func preparePreviewFileIfNeeded() {
        guard previewURL == nil else { return }
        if let localFileURL = attachment.localFileURL,
           FileManager.default.fileExists(atPath: localFileURL.path) {
            previewURL = localFileURL
            previewIsTemporary = false
            return
        }
        guard let payloadData = attachment.payloadData else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("csm-attachment-\(UUID().uuidString)")
            .appendingPathExtension(attachment.chatPreferredFilenameExtension)
        do {
            try payloadData.write(to: url, options: [.atomic])
            previewURL = url
            previewIsTemporary = true
        } catch {
            previewURL = nil
        }
    }

    private func cleanupPreviewFile() {
        guard let previewURL else { return }
        if previewIsTemporary {
            try? FileManager.default.removeItem(at: previewURL)
        }
        self.previewURL = nil
        previewIsTemporary = false
    }
}

private struct MessageAttachmentDetailHeader: View {
    var attachment: MessageAttachment

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: attachment.chatSystemImageName)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(attachment.chatTint, in: RoundedRectangle(cornerRadius: CSMTheme.cardRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(attachment.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(3)
                Text(attachment.chatKindLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if attachment.kind != .location {
                    Text(attachment.chatDetailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LiveLocationDurationOption: Identifiable {
    var label: String
    var seconds: TimeInterval

    var id: TimeInterval { seconds }

    static let all = [
        LiveLocationDurationOption(label: "15 min", seconds: 15 * 60),
        LiveLocationDurationOption(label: "1 h", seconds: 60 * 60),
        LiveLocationDurationOption(label: "8 h", seconds: 8 * 60 * 60)
    ]
}

private struct AttachmentQuickLookPreview: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

extension MessageAttachment {
    var chatSystemImageName: String {
        switch chatFileCategory {
        case .sticker:
            return "face.smiling.fill"
        case .image:
            return "photo.fill"
        case .video:
            return "video.fill"
        case .voice:
            return "waveform"
        case .location:
            return "location.fill"
        case .safety:
            return "checkmark.shield.fill"
        case .pdf:
            return "doc.richtext.fill"
        case .word:
            return "doc.text.fill"
        case .spreadsheet:
            return "tablecells.fill"
        case .presentation:
            return "rectangle.on.rectangle.fill"
        case .archive:
            return "archivebox.fill"
        case .cad:
            return "cube.transparent.fill"
        case .text:
            return "doc.plaintext.fill"
        case .document:
            return "doc.fill"
        }
    }

    var chatKindLabel: String {
        switch chatFileCategory {
        case .sticker:
            return CSMLocalization.text("chat.attachment.kind.sticker", fallback: "Nálepka")
        case .image:
            return CSMLocalization.text("chat.attachment.kind.image", fallback: "Obrázek")
        case .video:
            return CSMLocalization.text("chat.attachment.kind.video", fallback: "Video")
        case .voice:
            return CSMLocalization.text("chat.attachment.kind.voice", fallback: "Hlasová poznámka")
        case .location:
            return CSMLocalization.text("chat.attachment.kind.location", fallback: "Poloha")
        case .safety:
            return CSMLocalization.text("chat.attachment.kind.safety", fallback: "Rychlý status")
        case .pdf:
            return "PDF"
        case .word:
            return CSMLocalization.text("chat.attachment.kind.word", fallback: "Word dokument")
        case .spreadsheet:
            return CSMLocalization.text("chat.attachment.kind.spreadsheet", fallback: "Excel tabulka")
        case .presentation:
            return CSMLocalization.text("chat.attachment.kind.presentation", fallback: "PowerPoint prezentace")
        case .archive:
            return CSMLocalization.text("chat.attachment.kind.archive", fallback: "Archiv")
        case .cad:
            return CSMLocalization.text("chat.attachment.kind.cad", fallback: "CAD/BIM výkres")
        case .text:
            return CSMLocalization.text("chat.attachment.kind.text", fallback: "Textový soubor")
        case .document:
            return CSMLocalization.text("chat.attachment.kind.document", fallback: "Dokument")
        }
    }

    var chatTint: Color {
        switch chatFileCategory {
        case .sticker:
            return CSMTheme.relayCyan
        case .location, .safety:
            return CSMTheme.secureGreen
        case .voice, .cad:
            return CSMTheme.relayCyan
        case .pdf, .presentation, .archive:
            return CSMTheme.warningAmber
        default:
            return CSMTheme.signalBlue
        }
    }

    var chatDetailText: String {
        var parts: [String] = [chatKindLabel]
        if let durationSeconds, durationSeconds > 0 {
            parts.append("\(Int(durationSeconds.rounded())) s")
        }
        if let location {
            parts.append(String(format: "%.5f, %.5f", location.lat, location.lon))
        } else if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    var chatSizeText: String {
        guard let byteCount else {
            return CSMLocalization.text("attachment.detail.size_unknown", fallback: "Neznámá")
        }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    var chatPreviewImage: UIImage? {
        guard kind == .image || kind == .sticker else { return nil }
        if let localFileURL {
            return UIImage(contentsOfFile: localFileURL.path)
        }
        guard let payloadData else { return nil }
        return UIImage(data: payloadData)
    }

    var chatPreferredFilenameExtension: String {
        let extensionFromTitle = (title as NSString).pathExtension
        if !extensionFromTitle.isEmpty {
            return extensionFromTitle
        }

        switch chatFileCategory {
        case .sticker:
            return "png"
        case .image:
            return "jpg"
        case .video:
            return "mp4"
        case .voice:
            return "m4a"
        case .pdf:
            return "pdf"
        case .word:
            return mimeType?.lowercased().contains("openxml") == true ? "docx" : "doc"
        case .spreadsheet:
            return mimeType?.lowercased().contains("openxml") == true ? "xlsx" : "xls"
        case .presentation:
            return mimeType?.lowercased().contains("openxml") == true ? "pptx" : "ppt"
        case .archive:
            return "zip"
        case .cad:
            return "ifc"
        case .text:
            return "txt"
        case .location, .safety:
            return "txt"
        case .document:
            return "bin"
        }
    }

    private var chatFileCategory: MessageAttachmentFileCategory {
        switch kind {
        case .sticker:
            return .sticker
        case .image:
            return .image
        case .video:
            return .video
        case .voiceNote:
            return .voice
        case .location:
            return .location
        case .safetyStatus:
            return .safety
        case .document:
            return MessageAttachmentFileCategory(mimeType: mimeType, title: title)
        }
    }
}

private enum MessageAttachmentFileCategory {
    case sticker
    case image
    case video
    case voice
    case location
    case safety
    case pdf
    case word
    case spreadsheet
    case presentation
    case archive
    case cad
    case text
    case document

    init(mimeType: String?, title: String) {
        let mime = mimeType?.lowercased() ?? ""
        let ext = (title as NSString).pathExtension.lowercased()

        if mime == "application/pdf" || ext == "pdf" {
            self = .pdf
        } else if ["doc", "docx"].contains(ext) || mime.contains("word") || mime.contains("wordprocessingml") {
            self = .word
        } else if ["xls", "xlsx", "csv"].contains(ext) || mime.contains("excel") || mime.contains("spreadsheet") || mime.contains("csv") {
            self = .spreadsheet
        } else if ["ppt", "pptx"].contains(ext) || mime.contains("powerpoint") || mime.contains("presentationml") {
            self = .presentation
        } else if ["zip", "7z", "rar", "tar", "gz"].contains(ext) || mime.contains("zip") || mime.contains("archive") || mime.contains("rar") {
            self = .archive
        } else if ["dwg", "dxf", "ifc", "pln", "rvt", "skp"].contains(ext) || mime.contains("cad") || mime.contains("ifc") || mime.contains("revit") {
            self = .cad
        } else if ["txt", "rtf", "md", "json", "xml", "kml", "geojson"].contains(ext) || mime.hasPrefix("text/") {
            self = .text
        } else {
            self = .document
        }
    }
}
