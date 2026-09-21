import Foundation

enum CSMLocalization {
    static func text(_ key: String, fallback: String) -> String {
        let hostLocalized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        if hostLocalized != key {
            return hostLocalized
        }

        let packageLocalized = Bundle.module.localizedString(forKey: key, value: nil, table: nil)
        return packageLocalized == key ? fallback : packageLocalized
    }

    static func text(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        let format = text(key, fallback: fallback)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
