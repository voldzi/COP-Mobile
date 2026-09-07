import Foundation

enum ChatAIModelPreference: String, Codable, Equatable, Sendable {
    case auto
    case fast
    case reasoning
}

enum ChatAICommandID: String, Codable, Equatable, Sendable {
    case ai
    case summary
    case risks
    case map
    case report
    case tasks
    case translate
    case fast
    case reasoning
}

struct ChatAIInvocation: Equatable, Sendable {
    enum Trigger: String, Equatable, Sendable {
        case directAIChat
        case mention
        case slash
    }

    var commandID: ChatAICommandID?
    var modelPreference: ChatAIModelPreference
    var question: String
    var trigger: Trigger
}

struct ChatInteractionSuggestion: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case ai
        case command
        case person
    }

    var id: String { "\(kind.rawValue):\(value)" }
    var kind: Kind
    var label: String
    var detail: String
    var value: String
    var systemImage: String
}

enum ChatInteractionRegistry {
    static let contractVersion = "cop-chat-interactions-v1"

    private struct Command: Sendable {
        var aliases: [String]
        var detail: String
        var id: ChatAICommandID
        var label: String
        var modelPreference: ChatAIModelPreference
        var promptPrefix: String?
        var visible: Bool
    }

    private static let commands: [Command] = [
        Command(
            aliases: ["ai", "cop-ai", "copai"],
            detail: "Zeptat se COP AI s automatickou volbou postupu",
            id: .ai,
            label: "/ai",
            modelPreference: .auto,
            visible: true
        ),
        Command(
            aliases: ["souhrn", "summary"],
            detail: "Shrnout důležité body, rozhodnutí a nejasnosti",
            id: .summary,
            label: "/souhrn",
            modelPreference: .auto,
            promptPrefix: "Shrň relevantní konverzaci a COP kontext. Odděl fakta, rozhodnutí, nejasnosti a další kroky.",
            visible: true
        ),
        Command(
            aliases: ["rizika", "risks"],
            detail: "Vyhodnotit rizika, nejistoty a chybějící informace",
            id: .risks,
            label: "/rizika",
            modelPreference: .reasoning,
            promptPrefix: "Vyhodnoť civilní situační rizika. Odděl ověřená fakta, nejistoty a chybějící informace.",
            visible: true
        ),
        Command(
            aliases: ["mapa", "map"],
            detail: "Najít místo nebo objekt v COP mapě",
            id: .map,
            label: "/mapa",
            modelPreference: .auto,
            promptPrefix: "Najdi v COP mapě odpovídající místo nebo objekt a uveď konkrétní výsledek, vzdálenost a zdroj.",
            visible: true
        ),
        Command(
            aliases: ["hlaseni", "hlášení", "report"],
            detail: "Připravit návrh situačního hlášení k ověření",
            id: .report,
            label: "/hlášení",
            modelPreference: .reasoning,
            promptPrefix: "Připrav návrh civilního situačního hlášení k lidské kontrole. Nic automaticky neodesílej.",
            visible: true
        ),
        Command(
            aliases: ["ukoly", "úkoly", "tasks"],
            detail: "Vypsat rozhodnutí, vlastníky a otevřené kroky",
            id: .tasks,
            label: "/úkoly",
            modelPreference: .auto,
            promptPrefix: "Vypiš z konverzace rozhodnutí, otevřené kroky, případné vlastníky a termíny. Nejasné údaje označ.",
            visible: true
        ),
        Command(
            aliases: ["prelozit", "přeložit", "translate"],
            detail: "Přeložit text se zachováním významu a nejistot",
            id: .translate,
            label: "/přeložit",
            modelPreference: .auto,
            promptPrefix: "Přelož následující text. Zachovej věcný význam, názvy a výstražné formulace.",
            visible: true
        ),
        Command(
            aliases: ["fast"],
            detail: "Kompatibilní alias pro krátkou odpověď",
            id: .fast,
            label: "/fast",
            modelPreference: .fast,
            visible: false
        ),
        Command(
            aliases: ["reasoning", "reason"],
            detail: "Kompatibilní alias pro důkladnou analýzu",
            id: .reasoning,
            label: "/reasoning",
            modelPreference: .reasoning,
            visible: false
        )
    ]

    static func suggestions(
        for text: String,
        aiAgentAvailable: Bool,
        members: [ConversationMember]
    ) -> [ChatInteractionSuggestion] {
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty, !draft.contains(where: \.isWhitespace) else { return [] }

        if draft.hasPrefix("/") {
            let token = normalized(draft)
            return commands
                .filter { $0.visible && normalized($0.label).hasPrefix(token) }
                .map { command in
                    ChatInteractionSuggestion(
                        kind: .command,
                        label: command.label,
                        detail: command.detail,
                        value: "\(command.label) ",
                        systemImage: commandSymbol(command.id)
                    )
                }
        }

        guard draft.hasPrefix("@") else { return [] }
        let token = normalized(String(draft.dropFirst()))
        var suggestions: [ChatInteractionSuggestion] = []
        if aiAgentAvailable {
            suggestions.append(
                ChatInteractionSuggestion(
                    kind: .ai,
                    label: "@COP AI",
                    detail: "Oslovit COP AI asistenta v této konverzaci",
                    value: "@COP AI ",
                    systemImage: "shield.lefthalf.filled"
                )
            )
        }
        let people = members
            .filter { member in
                token.isEmpty || normalized(member.displayName ?? member.userId).hasPrefix(token) || normalized(member.userId).hasPrefix(token)
            }
            .prefix(6)
            .map { member in
                let displayName = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = displayName?.isEmpty == false ? displayName! : member.userId
                return ChatInteractionSuggestion(
                    kind: .person,
                    label: "@\(label)",
                    detail: member.role ?? "Člen konverzace",
                    value: "@\(label) ",
                    systemImage: "person.crop.circle"
                )
            }
        suggestions.append(contentsOf: people)
        return suggestions.filter { suggestion in
            token.isEmpty || normalized(String(suggestion.label.dropFirst())).hasPrefix(token)
        }
    }

    static func aiInvocation(
        for text: String,
        directAIChat: Bool,
        groupAIAssistantEnabled: Bool
    ) -> ChatAIInvocation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let slash = slashInvocation(trimmed) {
            return slash
        }
        if groupAIAssistantEnabled, let question = aiMentionQuestion(trimmed) {
            return ChatAIInvocation(modelPreference: .auto, question: question, trigger: .mention)
        }
        if directAIChat {
            let normalizedQuestion = modelOverride(trimmed, fallback: .auto)
            return ChatAIInvocation(
                modelPreference: normalizedQuestion.preference,
                question: normalizedQuestion.question,
                trigger: .directAIChat
            )
        }
        return nil
    }

    private static func slashInvocation(_ text: String) -> ChatAIInvocation? {
        guard text.hasPrefix("/") else { return nil }
        let content = String(text.dropFirst())
        let split = content.firstIndex(where: { $0.isWhitespace || $0 == ":" || $0 == "," })
        let alias = normalized(split.map { String(content[..<$0]) } ?? content)
        guard let command = commands.first(where: { item in
            item.aliases.contains { normalized($0) == alias }
        }) else { return nil }
        let rawQuestion = split.map { String(content[$0...]) } ?? ""
        let strippedQuestion = rawQuestion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
        let normalizedQuestion = modelOverride(strippedQuestion, fallback: command.modelPreference)
        let question = [command.promptPrefix, normalizedQuestion.question]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: command.promptPrefix == nil ? "" : " Kontext nebo zadání: ")
        return ChatAIInvocation(
            commandID: command.id,
            modelPreference: normalizedQuestion.preference,
            question: question,
            trigger: .slash
        )
    }

    private static func aiMentionQuestion(_ text: String) -> String? {
        let lowered = normalized(text)
        for prefix in ["@cop ai", "@cop-ai", "@cop_ai", "@cop.ai", "@ai"] where consumes(prefix, from: lowered) {
            let boundary = text.index(text.startIndex, offsetBy: min(prefix.count, text.count))
            let remainder = String(text[boundary...])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
            return remainder
        }
        return nil
    }

    private static func modelOverride(
        _ text: String,
        fallback: ChatAIModelPreference
    ) -> (preference: ChatAIModelPreference, question: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (prefix, preference) in [
            ("/reasoning", ChatAIModelPreference.reasoning),
            ("/reason", ChatAIModelPreference.reasoning),
            ("/fast", ChatAIModelPreference.fast),
            ("/auto", ChatAIModelPreference.auto)
        ] where consumes(prefix, from: normalized(trimmed)) {
            let boundary = trimmed.index(trimmed.startIndex, offsetBy: min(prefix.count, trimmed.count))
            return (
                preference,
                String(trimmed[boundary...])
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,-")))
            )
        }
        return (fallback, trimmed)
    }

    private static func commandSymbol(_ id: ChatAICommandID) -> String {
        switch id {
        case .ai: return "sparkles"
        case .summary: return "text.alignleft"
        case .risks: return "exclamationmark.triangle"
        case .map: return "map"
        case .report: return "doc.text"
        case .tasks: return "checklist"
        case .translate: return "character.bubble"
        case .fast: return "bolt"
        case .reasoning: return "brain"
        }
    }

    private static func consumes(_ prefix: String, from value: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        guard value.count > prefix.count else { return true }
        let boundary = value.index(value.startIndex, offsetBy: prefix.count)
        let next = value[boundary]
        return next.isWhitespace || ":,-".contains(next)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "cs_CZ"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
