import Foundation

enum CSMLocalization {
    static func text(_ key: String, fallback: String) -> String {
        let localized = Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
        return localized == key ? fallback : localized
    }

    static func text(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let format = text(key, fallback: fallback)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
