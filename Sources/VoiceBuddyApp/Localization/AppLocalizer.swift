import Foundation

/// Resolves localized strings from `Localizable.xcstrings` (or compiled `.lproj` bundles)
/// while supporting live in-app switching between `"system"`, `"en"`, and `"zh"`.
enum AppLocalizer {
    private struct XCStringsCatalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct StringUnit: Decodable {
                    let value: String
                }
                let stringUnit: StringUnit?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    private static let catalogStrings: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(XCStringsCatalog.self, from: data) else {
            return [:]
        }
        var table: [String: [String: String]] = [:]
        for (key, entry) in decoded.strings {
            guard let localizations = entry.localizations else { continue }
            var langMap: [String: String] = [:]
            for (lang, loc) in localizations {
                if let val = loc.stringUnit?.value {
                    langMap[lang] = val
                }
            }
            table[key] = langMap
        }
        return table
    }()

    static func isChinese(interfaceLanguage: String, preferredLanguages: [String] = Locale.preferredLanguages) -> Bool {
        interfaceLanguage == "zh" || (interfaceLanguage == "system" && preferredLanguages.first?.hasPrefix("zh") == true)
    }

    static func string(_ key: String, interfaceLanguage: String, bundle: Bundle = Bundle.module) -> String {
        let useChinese = isChinese(interfaceLanguage: interfaceLanguage)
        let targetLang = useChinese ? "zh-Hans" : "en"

        // 1. Prefer compiled `.lproj` when built via Xcode IDE.
        if let lprojPath = bundle.path(forResource: targetLang, ofType: "lproj"),
           let lprojBundle = Bundle(path: lprojPath) {
            let localized = lprojBundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key || !useChinese {
                return localized
            }
        }

        // 2. Use parsed `Localizable.xcstrings` catalog (standard SwiftPM CLI resource bundle).
        if bundle === Bundle.module,
           let value = catalogStrings[key]?[targetLang] {
            return value
        }
        return key
    }

    static func formatted(_ key: String, interfaceLanguage: String, _ args: CVarArg...) -> String {
        let format = string(key, interfaceLanguage: interfaceLanguage)
        return String(format: format, arguments: args)
    }

    static func choose(en: String, zh: String, interfaceLanguage: String) -> String {
        isChinese(interfaceLanguage: interfaceLanguage) ? zh : en
    }

    static var catalogCountForTesting: Int {
        catalogStrings.count
    }
}
