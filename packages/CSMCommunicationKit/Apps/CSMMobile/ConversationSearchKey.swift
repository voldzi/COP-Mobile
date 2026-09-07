import Foundation

extension String {
    var csmSearchKey: String {
        folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "cs_CZ")
        )
        .lowercased(with: Locale(identifier: "cs_CZ"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
