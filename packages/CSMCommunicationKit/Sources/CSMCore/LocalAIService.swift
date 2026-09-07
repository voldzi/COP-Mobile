import Foundation

enum LocalAIAvailability: String, Codable, Sendable {
    case available
    case deterministicFallback
    case disabledByPolicy
    case unavailable
}

struct LocalAIReportDraftSuggestion: Codable, Equatable, Sendable {
    var title: String
    var description: String
    var category: ReportCategory
    var severity: AlertSeverity
    var extractedFields: [String: String]
    var missingDetails: [String]
    var privacyFindings: [String]
    var safetyNote: String
}

struct LocalAIConversationSummary: Codable, Equatable, Sendable {
    var title: String
    var bullets: [String]
    var unresolvedItems: [String]
    var safetyNote: String
}

struct LocalAISafetyGuidance: Codable, Equatable, Sendable {
    var title: String
    var priority: AlertSeverity
    var immediateActions: [String]
    var riskNotes: [String]
    var missingContext: [String]
    var safetyNote: String
}

struct LocalAIReplySuggestion: Codable, Equatable, Sendable {
    var title: String
    var body: String
    var priority: AlertSeverity
}

struct LocalAIMessageTranslation: Codable, Equatable, Sendable {
    var originalText: String
    var translatedText: String
    var sourceLanguageCode: String
    var targetLanguageCode: String
    var confidence: Double
    var safetyNote: String
}

protocol LocalAIServiceProtocol: Sendable {
    var availability: LocalAIAvailability { get async }
    func suggestReportDraft(
        title: String,
        description: String,
        category: ReportCategory,
        severity: AlertSeverity
    ) async throws -> LocalAIReportDraftSuggestion
    func summarize(messages: [ChatMessage]) async throws -> LocalAIConversationSummary
    func suggestReplies(messages: [ChatMessage], conversation: Conversation) async throws -> [LocalAIReplySuggestion]
    func translateMessage(_ text: String, preferredLanguageCode: String) async throws -> LocalAIMessageTranslation
    func safetyGuidance(snapshot: MobileOfflineSnapshot?, reports: [CommunityReport]) async throws -> LocalAISafetyGuidance
}

actor DeterministicLocalAIService: LocalAIServiceProtocol {
    var availability: LocalAIAvailability {
        .deterministicFallback
    }

    func suggestReportDraft(
        title: String,
        description: String,
        category: ReportCategory,
        severity: AlertSeverity
    ) async throws -> LocalAIReportDraftSuggestion {
        let normalizedDescription = normalize(description)
        let redaction = redactSensitiveContent(in: normalizedDescription)
        let resolvedCategory = inferCategory(from: redaction.text, fallback: category)
        let resolvedSeverity = inferSeverity(from: redaction.text, fallback: severity)
        let resolvedTitle = normalize(title).isEmpty ? resolvedCategory.fallbackTitle : normalize(title)
        let missingDetails = missingReportDetails(description: redaction.text)
        let extractedFields = extractReportFields(from: redaction.text, category: resolvedCategory, severity: resolvedSeverity)

        return LocalAIReportDraftSuggestion(
            title: resolvedTitle,
            description: redaction.text,
            category: resolvedCategory,
            severity: resolvedSeverity,
            extractedFields: extractedFields,
            missingDetails: missingDetails,
            privacyFindings: redaction.findings,
            safetyNote: redaction.findings.isEmpty
                ? CSMLocalization.text("localai.report.note.clean", fallback: "Návrh vznikl lokálně v zařízení. Před odesláním ho ověřte.")
                : CSMLocalization.text("localai.report.note.redacted", fallback: "Návrh vznikl lokálně v zařízení. Citlivé údaje byly navrženy ke skrytí; před odesláním text ověřte.")
        )
    }

    func summarize(messages: [ChatMessage]) async throws -> LocalAIConversationSummary {
        let recentMessages = Array(messages.suffix(20))
        var bullets: [String] = []

        if let lastMessage = recentMessages.last {
            bullets.append(CSMLocalization.text(
                "localai.summary.last_message",
                fallback: "Poslední zpráva: %@: %@",
                senderLabel(for: lastMessage),
                summaryPreview(for: lastMessage, maxLength: 104)
            ))
        }

        let senderCount = Set(recentMessages.map(\.senderId)).count
        if recentMessages.count > 1 {
            let senderLabel = senderCount == 1
                ? CSMLocalization.text("localai.summary.sender.one", fallback: "člověka")
                : CSMLocalization.text("localai.summary.sender.many", fallback: "lidí")
            bullets.append(CSMLocalization.text(
                "localai.summary.messages",
                fallback: "%d zpráv v posledním přehledu od %d %@.",
                recentMessages.count,
                senderCount,
                senderLabel
            ))
        }

        if let statusSummary = safetyStatusSummary(from: recentMessages) {
            bullets.append(statusSummary)
        }

        if let attachmentSummary = attachmentSummary(from: recentMessages) {
            bullets.append(attachmentSummary)
        }

        let unresolvedItems = recentMessages
            .filter(messageNeedsFollowUp)
            .prefix(3)
            .map { summaryPreview(for: $0, maxLength: 96) }

        return LocalAIConversationSummary(
            title: messages.isEmpty
                ? CSMLocalization.text("localai.summary.title.empty", fallback: "Žádné lokální zprávy")
                : CSMLocalization.text("localai.summary.title.recent", fallback: "Souhrn posledních zpráv"),
            bullets: bullets.isEmpty ? [CSMLocalization.text("localai.summary.empty", fallback: "Zatím není co shrnout.")] : bullets,
            unresolvedItems: Array(unresolvedItems),
            safetyNote: CSMLocalization.text("localai.summary.safety_note", fallback: "Souhrn je lokální pomůcka a nenahrazuje potvrzené instrukce operátora.")
        )
    }

    func suggestReplies(messages: [ChatMessage], conversation: Conversation) async throws -> [LocalAIReplySuggestion] {
        let recentText = messages.suffix(8)
            .map { normalize($0.body) }
            .joined(separator: " ")
        let key = searchKey(recentText)
        var suggestions: [LocalAIReplySuggestion] = [
            LocalAIReplySuggestion(
                title: CSMLocalization.text("watch.reply.ok", fallback: "OK"),
                body: CSMLocalization.text("watch.reply.ok.body", fallback: "OK, potvrzuji."),
                priority: .info
            ),
            LocalAIReplySuggestion(
                title: CSMLocalization.text("watch.reply.enroute", fallback: "Na cestě"),
                body: CrisisQuickStatus.enRoute.messageBody(source: CSMLocalization.text("quick.status.watch.source", fallback: "Status z Apple Watch")),
                priority: .info
            ),
            LocalAIReplySuggestion(
                title: CSMLocalization.text("watch.reply.need_help", fallback: "Potřebuji pomoc"),
                body: CrisisQuickStatus.needsHelp.messageBody(source: CSMLocalization.text("quick.status.watch.source", fallback: "Status z Apple Watch")),
                priority: .critical
            )
        ]

        if containsAny(key, keywords: ["potvrdit", "potvrzeni", "potrebuji", "potřebuji", "cekam", "čekám"]) {
            suggestions.insert(
                LocalAIReplySuggestion(
                    title: CSMLocalization.text("watch.reply.confirm", fallback: "Potvrzuji"),
                    body: CSMLocalization.text("watch.reply.confirm.body", fallback: "Potvrzuji, řeším."),
                    priority: .warning
                ),
                at: 1
            )
        }
        if containsAny(key, keywords: ["kde", "poloha", "polohu", "lokace", "misto", "místo", "mapa"]) {
            suggestions.insert(
                LocalAIReplySuggestion(
                    title: CSMLocalization.text("watch.reply.send_location", fallback: "Pošlu polohu"),
                    body: CSMLocalization.text("watch.reply.send_location.body", fallback: "Pošlu polohu z iPhonu."),
                    priority: .warning
                ),
                at: 1
            )
        }

        return Array(uniqueReplySuggestions(suggestions).prefix(4))
    }

    func translateMessage(_ text: String, preferredLanguageCode: String) async throws -> LocalAIMessageTranslation {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else {
            throw CSMServiceError.invalidState(CSMLocalization.text("localai.translation.empty", fallback: "Zpráva neobsahuje text k překladu."))
        }

        let sourceLanguage = detectedLanguageCode(for: normalizedText)
        let preferredLanguage = normalizedLanguageCode(preferredLanguageCode)
        let targetLanguage = sourceLanguage == preferredLanguage
            ? alternateTranslationLanguage(for: preferredLanguage)
            : preferredLanguage
        let translation = translate(normalizedText, from: sourceLanguage, to: targetLanguage)

        return LocalAIMessageTranslation(
            originalText: normalizedText,
            translatedText: translation.text,
            sourceLanguageCode: sourceLanguage,
            targetLanguageCode: targetLanguage,
            confidence: translation.confidence,
            safetyNote: CSMLocalization.text(
                "localai.translation.safety_note",
                fallback: "Překlad vznikl lokálně v zařízení. U kritických instrukcí ověřte význam u odesílatele."
            )
        )
    }

    func safetyGuidance(snapshot: MobileOfflineSnapshot?, reports: [CommunityReport]) async throws -> LocalAISafetyGuidance {
        let activeAlerts = snapshot?.activePublicAlerts ?? []
        let priority = highestSeverity(alerts: activeAlerts, reports: reports)
        let topAlerts = activeAlerts.sorted(by: sortByPriority).prefix(3)
        let topReports = reports.sorted { $0.observedAt > $1.observedAt }.prefix(3)
        let riskNotes = Array(topAlerts.map { "\(severityLabel($0.severity)): \($0.title)" })
            + topReports.map { CSMLocalization.text("localai.safety.report_prefix", fallback: "Hlášení: %@", $0.title) }
        let missingContext = missingSafetyContext(snapshot: snapshot, activeAlerts: activeAlerts, reports: reports)

        return LocalAISafetyGuidance(
            title: guidanceTitle(priority: priority, activeAlerts: activeAlerts, reports: reports),
            priority: priority,
            immediateActions: guidanceActions(priority: priority, activeAlerts: activeAlerts, reports: reports),
            riskNotes: riskNotes.isEmpty ? [CSMLocalization.text("localai.safety.no_active_risk", fallback: "Z posledního offline snapshotu nevyplývá aktivní riziko.")] : Array(riskNotes.prefix(5)),
            missingContext: missingContext,
            safetyNote: CSMLocalization.text("localai.safety.note", fallback: "Doporučení vzniklo lokálně z posledních dostupných dat. Ověřte aktuální pokyny operátora a stav spojení.")
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func searchKey(_ text: String) -> String {
        normalize(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "cs_CZ"))
            .lowercased(with: Locale(identifier: "cs_CZ"))
    }

    private func senderLabel(for message: ChatMessage) -> String {
        let displayName = normalize(message.senderDisplayName)
        let currentUser = CSMLocalization.text("localai.sender.you", fallback: "vy")
        guard !displayName.isEmpty else {
            return message.isOwnMessage ? currentUser : CSMLocalization.text("localai.sender.participant", fallback: "účastník")
        }
        return message.isOwnMessage ? currentUser : displayName
    }

    private func summaryPreview(for message: ChatMessage, maxLength: Int) -> String {
        let body = normalize(message.body)
        let value: String
        if !body.isEmpty {
            value = body
        } else if !message.attachments.isEmpty {
            value = message.attachments.map(\.title).joined(separator: ", ")
        } else {
            value = CSMLocalization.text("localai.message.no_text", fallback: "bez textu")
        }
        return truncated(value, maxLength: maxLength)
    }

    private func safetyStatusSummary(from messages: [ChatMessage]) -> String? {
        let statuses = uniqueValues(
            messages.flatMap(\.attachments)
                .filter { $0.kind == .safetyStatus }
                .map(\.title)
        )
        guard !statuses.isEmpty else { return nil }
        return CSMLocalization.text("localai.summary.quick_statuses", fallback: "Rychlé stavy: %@.", statuses.prefix(3).joined(separator: ", "))
    }

    private func attachmentSummary(from messages: [ChatMessage]) -> String? {
        let attachments = messages.flatMap(\.attachments).filter { $0.kind != .safetyStatus }
        guard !attachments.isEmpty else { return nil }

        let imagesAndVideos = attachments.filter { $0.kind == .image || $0.kind == .video }.count
        let documents = attachments.filter { $0.kind == .document }.count
        let voiceNotes = attachments.filter { $0.kind == .voiceNote }.count
        let locations = attachments.filter { $0.kind == .location }.count
        let stickers = attachments.filter { $0.kind == .sticker }.count

        var parts: [String] = []
        if stickers > 0 {
            parts.append(stickers == 1
                ? CSMLocalization.text("localai.attachment.sticker.one", fallback: "1 nálepka")
                : CSMLocalization.text("localai.attachment.sticker.many", fallback: "%d nálepky", stickers))
        }
        if imagesAndVideos > 0 {
            parts.append(imagesAndVideos == 1
                ? CSMLocalization.text("localai.attachment.image_video.one", fallback: "1 fotka/video")
                : CSMLocalization.text("localai.attachment.image_video.many", fallback: "%d fotky/videa", imagesAndVideos))
        }
        if documents > 0 {
            parts.append(documents == 1
                ? CSMLocalization.text("localai.attachment.document.one", fallback: "1 soubor")
                : CSMLocalization.text("localai.attachment.document.many", fallback: "%d soubory", documents))
        }
        if voiceNotes > 0 {
            parts.append(voiceNotes == 1
                ? CSMLocalization.text("localai.attachment.voice.one", fallback: "1 hlasová poznámka")
                : CSMLocalization.text("localai.attachment.voice.many", fallback: "%d hlasové poznámky", voiceNotes))
        }
        if locations > 0 {
            parts.append(locations == 1
                ? CSMLocalization.text("localai.attachment.location.one", fallback: "1 poloha")
                : CSMLocalization.text("localai.attachment.location.many", fallback: "%d polohy", locations))
        }

        return parts.isEmpty ? nil : CSMLocalization.text("localai.attachment.shared", fallback: "Sdíleno: %@.", parts.joined(separator: ", "))
    }

    private func messageNeedsFollowUp(_ message: ChatMessage) -> Bool {
        let searchable = ([message.body] + message.attachments.map(\.title)).joined(separator: " ")
        return containsAny(
            searchable,
            keywords: [
                "cekam", "čekám", "potrebuji", "potřebuji", "nejasne", "nejasné",
                "problem", "problém", "selhalo", "chybi", "chybí", "pomoc", "uvizl"
            ]
        )
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = normalize(value)
            guard !normalized.isEmpty else { return nil }
            let key = searchKey(normalized)
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return normalized
        }
    }

    private func uniqueReplySuggestions(_ values: [LocalAIReplySuggestion]) -> [LocalAIReplySuggestion] {
        var seen = Set<String>()
        return values.filter { suggestion in
            let key = searchKey(suggestion.body)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(max(0, maxLength - 3))) + "..."
    }

    private func normalizedLanguageCode(_ value: String) -> String {
        let lowercased = value.lowercased()
        if lowercased.hasPrefix("cs") { return "cs" }
        if lowercased.hasPrefix("sk") { return "cs" }
        return "en"
    }

    private func alternateTranslationLanguage(for languageCode: String) -> String {
        languageCode == "cs" ? "en" : "cs"
    }

    private func detectedLanguageCode(for text: String) -> String {
        let key = searchKey(text)
        if text.range(of: #"[áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]"#, options: .regularExpression) != nil {
            return "cs"
        }
        if containsAny(key, keywords: [
            "potrebuji", "potvrzuji", "jsem", "ceste", "cesta", "poloha", "pomoc", "neprujezd", "pozar", "voda", "most", "cekam", "dorazim"
        ]) {
            return "cs"
        }
        if containsAny(key, keywords: [
            "need", "help", "confirm", "on my way", "location", "road", "bridge", "fire", "water", "waiting", "arrive", "safe"
        ]) {
            return "en"
        }
        return "en"
    }

    private func translate(_ text: String, from sourceLanguage: String, to targetLanguage: String) -> (text: String, confidence: Double) {
        guard sourceLanguage != targetLanguage else {
            return (text, 0.35)
        }
        let phraseKey = searchKey(text)
        if let phrase = phraseTranslation(phraseKey, from: sourceLanguage, to: targetLanguage) {
            return (phrase, 0.92)
        }

        let words = wordTranslations(from: sourceLanguage, to: targetLanguage)
        var translatedWordCount = 0
        var sourceWordCount = 0
        var output = ""
        var currentWord = ""

        func flushWord() {
            guard !currentWord.isEmpty else { return }
            sourceWordCount += 1
            let key = searchKey(currentWord)
            if let translated = words[key] {
                translatedWordCount += 1
                output += applyCapitalization(of: currentWord, to: translated)
            } else {
                output += currentWord
            }
            currentWord = ""
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.letters.union(.decimalDigits).contains(scalar) {
                currentWord.append(Character(scalar))
            } else {
                flushWord()
                output.append(Character(scalar))
            }
        }
        flushWord()

        let confidence = sourceWordCount == 0 ? 0.35 : max(0.38, min(0.86, Double(translatedWordCount) / Double(sourceWordCount)))
        return (output, confidence)
    }

    private func phraseTranslation(_ key: String, from sourceLanguage: String, to targetLanguage: String) -> String? {
        let csToEn: [String: String] = [
            "ok potvrzuji": "OK, I confirm.",
            "potrebuji pomoc": "I need help.",
            "jsem na ceste": "I am on my way.",
            "poslu polohu": "I will send my location.",
            "cekam na pokyny": "I am waiting for instructions.",
            "jsem v poradku": "I am safe.",
            "na miste": "On scene.",
            "dorazim za 10 minut": "I will arrive in 10 minutes."
        ]
        let enToCs: [String: String] = [
            "ok i confirm": "OK, potvrzuji.",
            "i need help": "Potřebuji pomoc.",
            "i am on my way": "Jsem na cestě.",
            "i will send my location": "Pošlu polohu.",
            "i am waiting for instructions": "Čekám na pokyny.",
            "i am safe": "Jsem v pořádku.",
            "on scene": "Na místě.",
            "i will arrive in 10 minutes": "Dorazím za 10 minut."
        ]
        if sourceLanguage == "cs", targetLanguage == "en" { return csToEn[key] }
        if sourceLanguage == "en", targetLanguage == "cs" { return enToCs[key] }
        return nil
    }

    private func wordTranslations(from sourceLanguage: String, to targetLanguage: String) -> [String: String] {
        let csToEn: [String: String] = [
            "ahoj": "hello",
            "ano": "yes",
            "ne": "no",
            "ok": "OK",
            "potrebuji": "need",
            "potřebuji": "need",
            "pomoc": "help",
            "potvrzuji": "confirm",
            "cekam": "waiting",
            "čekám": "waiting",
            "jsem": "am",
            "na": "on",
            "ceste": "way",
            "cestě": "way",
            "miste": "scene",
            "místě": "scene",
            "poloha": "location",
            "polohu": "location",
            "poslu": "will send",
            "pošlu": "will send",
            "dorazim": "will arrive",
            "dorazím": "will arrive",
            "minut": "minutes",
            "pozar": "fire",
            "požár": "fire",
            "voda": "water",
            "most": "bridge",
            "cesta": "road",
            "neprujezdna": "blocked",
            "neprůjezdná": "blocked",
            "bezpeci": "safe",
            "bezpečí": "safe",
            "poradku": "safe",
            "pořádku": "safe",
            "pokyny": "instructions"
        ]
        let enToCs: [String: String] = [
            "hello": "ahoj",
            "yes": "ano",
            "no": "ne",
            "ok": "OK",
            "need": "potřebuji",
            "help": "pomoc",
            "confirm": "potvrzuji",
            "waiting": "čekám",
            "am": "jsem",
            "on": "na",
            "way": "cestě",
            "scene": "místě",
            "location": "poloha",
            "send": "poslat",
            "arrive": "dorazím",
            "minutes": "minut",
            "fire": "požár",
            "water": "voda",
            "bridge": "most",
            "road": "cesta",
            "blocked": "neprůjezdná",
            "safe": "v pořádku",
            "instructions": "pokyny"
        ]
        if sourceLanguage == "cs", targetLanguage == "en" { return csToEn }
        if sourceLanguage == "en", targetLanguage == "cs" { return enToCs }
        return [:]
    }

    private func applyCapitalization(of source: String, to translated: String) -> String {
        guard let first = source.first, first.isUppercase else { return translated }
        return translated.prefix(1).uppercased() + translated.dropFirst()
    }

    private func inferCategory(from text: String, fallback: ReportCategory) -> ReportCategory {
        let lowercased = text.lowercased()
        if containsAny(lowercased, keywords: ["pozar", "kour", "plamen", "hori"]) { return .fire }
        if containsAny(lowercased, keywords: ["voda", "povoden", "zaplava", "zatop"]) { return .flood }
        if containsAny(lowercased, keywords: ["most", "lavka"]) { return .bridgeDamage }
        if containsAny(lowercased, keywords: ["silnice", "cesta", "blok", "neprujezd"]) { return .roadBlockage }
        if containsAny(lowercased, keywords: ["elektr", "plyn", "vodovod", "kanalizace"]) { return .utilityOutage }
        if containsAny(lowercased, keywords: ["zranen", "sanit", "lekars", "bezvedomi"]) { return .medical }
        return fallback
    }

    private func inferSeverity(from text: String, fallback: AlertSeverity) -> AlertSeverity {
        let lowercased = text.lowercased()
        if containsAny(lowercased, keywords: ["ohrozeni zivota", "bezvedomi", "uvizl", "vybuch", "rychle se siri"]) {
            return .critical
        }
        if containsAny(lowercased, keywords: ["nebezpec", "zranen", "silny", "neprujezd", "unik"]) {
            return .warning
        }
        return fallback
    }

    private func missingReportDetails(description: String) -> [String] {
        var missing: [String] = []
        let lowercased = description.lowercased()
        if !containsAny(lowercased, keywords: ["u ", "ulice", "silnice", "most", "obec", "km", "gps"]) {
            missing.append(CSMLocalization.text("localai.missing.location", fallback: "upřesnit místo"))
        }
        if !containsAny(lowercased, keywords: ["ted", "nyni", "pred", "minut", "hodin", "dnes"]) {
            missing.append(CSMLocalization.text("localai.missing.time", fallback: "doplnit čas pozorování"))
        }
        if description.count < 40 {
            missing.append(CSMLocalization.text("localai.missing.description", fallback: "doplnit popis situace"))
        }
        return missing
    }

    private func extractReportFields(from text: String, category: ReportCategory, severity: AlertSeverity) -> [String: String] {
        var fields: [String: String] = [
            "hazard": category.rawValue,
            "severity": severity.rawValue
        ]
        if let observedTime = firstMatch(in: text, pattern: #"\b(?:ted|nyni|dnes|pred\s+\d+\s*(?:minut(?:ami)?|hodin(?:ami)?))\b"#) {
            fields["observedTime"] = observedTime
        }
        if let locationHint = firstMatch(in: text, pattern: #"\b(?:u|v|na)\s+([A-Za-zÁ-ž0-9 ._-]{3,42}?)(?:,|\.|\s+(?:je|jsou|hlasi|videl|videt|hori|hoří)|$)"#, group: 1) {
            fields["locationHint"] = normalize(locationHint)
        }
        if let people = firstMatch(in: text, pattern: #"\b\d+\s*(?:osob|lidi|zranenych|zraneni|uvizlych)\b"#) {
            fields["peopleHint"] = people
        }
        return fields
    }

    private func firstMatch(in text: String, pattern: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              group < match.numberOfRanges,
              let swiftRange = Range(match.range(at: group), in: text)
        else {
            return nil
        }
        return String(text[swiftRange])
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        let textKey = searchKey(text)
        return keywords.contains { textKey.contains(searchKey($0)) }
    }

    private func highestSeverity(alerts: [CopAlert], reports: [CommunityReport]) -> AlertSeverity {
        if alerts.contains(where: { $0.severity == .critical }) || reports.contains(where: { $0.severity == .critical }) {
            return .critical
        }
        if alerts.contains(where: { $0.severity == .warning }) || reports.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        return .info
    }

    private func sortByPriority(_ lhs: CopAlert, _ rhs: CopAlert) -> Bool {
        if lhs.severity.priority != rhs.severity.priority {
            return lhs.severity.priority > rhs.severity.priority
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func guidanceTitle(priority: AlertSeverity, activeAlerts: [CopAlert], reports: [CommunityReport]) -> String {
        if activeAlerts.isEmpty && reports.isEmpty {
            return CSMLocalization.text("localai.guidance.no_active_data", fallback: "Lokální situace bez aktivních dat")
        }
        switch priority {
        case .critical:
            return CSMLocalization.text("localai.guidance.critical", fallback: "Kritický lokální kontext")
        case .warning:
            return CSMLocalization.text("localai.guidance.warning", fallback: "Zvýšená pozornost v okolí")
        case .info:
            return CSMLocalization.text("localai.guidance.info", fallback: "Lokální přehled")
        }
    }

    private func guidanceActions(priority: AlertSeverity, activeAlerts: [CopAlert], reports: [CommunityReport]) -> [String] {
        var actions: [String] = []
        if priority == .critical {
            actions.append(CSMLocalization.text("localai.guidance.action.own_safety", fallback: "Nejprve ověřte vlastní bezpečí a dostupnost spojení."))
        }
        if activeAlerts.contains(where: { $0.map != nil }) || reports.contains(where: { $0.location.accuracyM != nil }) {
            actions.append(CSMLocalization.text("localai.guidance.action.map_compare", fallback: "Porovnejte riziko s mapou a poslední známou polohou."))
        }
        if activeAlerts.contains(where: { $0.severity == .critical || $0.severity == .warning }) {
            actions.append(CSMLocalization.text("localai.guidance.action.open_alert", fallback: "Otevřete detail aktivní výstrahy a potvrzujte jen ověřené informace."))
        }
        if reports.contains(where: { $0.category == .fire }) || activeAlerts.contains(where: { containsAny($0.title.lowercased(), keywords: ["pozar", "kour", "plamen"]) }) {
            actions.append(CSMLocalization.text("localai.guidance.action.avoid_smoke", fallback: "Vyhýbejte se kouři a neověřeným průjezdům v okolí události."))
        }
        if reports.contains(where: { $0.category == .flood }) || activeAlerts.contains(where: { containsAny($0.title.lowercased(), keywords: ["povoden", "voda", "zaplava"]) }) {
            actions.append(CSMLocalization.text("localai.guidance.action.avoid_water", fallback: "Nevstupujte do proudící vody a sledujte únikové trasy."))
        }
        if actions.isEmpty {
            actions.append(CSMLocalization.text("localai.guidance.action.offline_context", fallback: "Pracujte s posledním offline snapshotem jako s kontextem, ne jako s aktuální pravdou."))
        }
        return Array(actions.prefix(4))
    }

    private func severityLabel(_ severity: AlertSeverity) -> String {
        switch severity {
        case .info:
            return CSMLocalization.text("alert.severity.info", fallback: "Informace")
        case .warning:
            return CSMLocalization.text("alert.severity.warning", fallback: "Varování")
        case .critical:
            return CSMLocalization.text("alert.severity.critical", fallback: "Kritické")
        }
    }

    private func missingSafetyContext(
        snapshot: MobileOfflineSnapshot?,
        activeAlerts: [CopAlert],
        reports: [CommunityReport]
    ) -> [String] {
        var missing: [String] = []
        if snapshot == nil {
            missing.append(CSMLocalization.text("localai.missing.snapshot", fallback: "chybí offline snapshot"))
        }
        if activeAlerts.contains(where: { $0.map == nil }) {
            missing.append(CSMLocalization.text("localai.missing.alert_location", fallback: "některé výstrahy nemají mapovou polohu"))
        }
        if reports.isEmpty {
            missing.append(CSMLocalization.text("localai.missing.community_reports", fallback: "žádná lokální komunitní hlášení"))
        }
        let degradedSources = snapshot?.sourceHealth.filter { !$0.status.localizedCaseInsensitiveContains("ok") } ?? []
        if !degradedSources.isEmpty {
            missing.append(CSMLocalization.text("localai.missing.degraded_sources", fallback: "některé zdroje jsou degradované"))
        }
        return missing
    }

    private func redactSensitiveContent(in text: String) -> (text: String, findings: [String]) {
        var redacted = text
        var findings: [String] = []
        applyRedaction(
            pattern: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            replacement: CSMLocalization.text("localai.redaction.email.replacement", fallback: "[email skryt]"),
            finding: CSMLocalization.text("localai.redaction.email.finding", fallback: "skrýt e-mail"),
            text: &redacted,
            findings: &findings
        )
        applyRedaction(
            pattern: #"\b(?:\+420\s*)?(?:\d[\s.-]?){9}\b"#,
            replacement: CSMLocalization.text("localai.redaction.phone.replacement", fallback: "[telefon skryt]"),
            finding: CSMLocalization.text("localai.redaction.phone.finding", fallback: "skrýt telefon"),
            text: &redacted,
            findings: &findings
        )
        applyRedaction(
            pattern: #"\b\d{6}/?\d{3,4}\b"#,
            replacement: CSMLocalization.text("localai.redaction.national_id.replacement", fallback: "[rodné číslo skryto]"),
            finding: CSMLocalization.text("localai.redaction.national_id.finding", fallback: "skrýt rodné číslo"),
            text: &redacted,
            findings: &findings
        )
        return (normalize(redacted), findings)
    }

    private func applyRedaction(
        pattern: String,
        replacement: String,
        finding: String,
        text: inout String,
        findings: inout [String]
    ) {
        let updated = text.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
        if updated != text {
            text = updated
            findings.append(finding)
        }
    }
}

private extension ReportCategory {
    var fallbackTitle: String {
        switch self {
        case .fire:
            CSMLocalization.text("localai.fallback.fire", fallback: "Pozorovaný požár")
        case .flood:
            CSMLocalization.text("localai.fallback.flood", fallback: "Riziko záplavy")
        case .bridgeDamage:
            CSMLocalization.text("localai.fallback.bridge_damage", fallback: "Poškození mostu")
        case .roadBlockage:
            CSMLocalization.text("localai.fallback.road_blockage", fallback: "Neprůjezdná komunikace")
        case .infrastructureDamage:
            CSMLocalization.text("localai.fallback.infrastructure_damage", fallback: "Poškození infrastruktury")
        case .medical:
            CSMLocalization.text("localai.fallback.medical", fallback: "Zdravotní událost")
        case .utilityOutage:
            CSMLocalization.text("localai.fallback.utility_outage", fallback: "Výpadek služeb")
        case .hazard:
            CSMLocalization.text("localai.fallback.hazard", fallback: "Nebezpečí v okolí")
        case .other:
            CSMLocalization.text("localai.fallback.other", fallback: "Nové hlášení")
        }
    }
}

private extension AlertSeverity {
    var priority: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }
}
