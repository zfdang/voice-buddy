import Foundation
import Observation
import VoiceBuddyCore

/// Owns persisted user preferences and live localization helpers.
@MainActor
@Observable
final class PreferencesStore {
    private let defaultsKey: String
    private let defaults: UserDefaults

    @ObservationIgnored var onPreferencesChanged: ((Preferences, Preferences) -> Void)?

    var preferences: Preferences {
        didSet {
            save()
            onPreferencesChanged?(oldValue, preferences)
        }
    }

    init(defaults: UserDefaults = .standard, defaultsKey: String = "VoiceBuddy.preferences") {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        self.preferences = defaults.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
            ?? Preferences()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    func t(_ key: String) -> String {
        AppLocalizer.string(key, interfaceLanguage: preferences.interfaceLanguage)
    }

    func formatted(_ key: String, _ args: CVarArg...) -> String {
        let template = AppLocalizer.string(key, interfaceLanguage: preferences.interfaceLanguage)
        return String(format: template, arguments: args)
    }

    func label(_ en: String, _ zh: String) -> String {
        AppLocalizer.choose(en: en, zh: zh, interfaceLanguage: preferences.interfaceLanguage)
    }
}
