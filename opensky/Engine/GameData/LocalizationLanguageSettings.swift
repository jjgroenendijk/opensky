// Resolves the language segment used by localized plugin string-table paths.
// Skyrim INI files remain read-only; an explicit OpenSky Settings choice lives
// in the shared defaults domain and takes precedence.

import Foundation

nonisolated struct LocalizationLanguageSnapshot: Equatable, Sendable {
    let language: String
    let source: String
}

nonisolated enum LocalizationLanguageError: Error, Equatable {
    case invalidLanguage(String)
}

nonisolated extension LocalizationLanguageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .invalidLanguage(value):
            "Invalid string-table language \"\(value)\". Use letters, numbers, hyphens, "
                + "or underscores."
        }
    }
}

nonisolated enum LocalizationLanguageSettings {
    static let fallback = "english"
    static let overrideKey = "LocalizationLanguage"

    private static let section = "General"
    private static let iniKey = "sLanguage"

    /// Skyrim.ini is the game's source of truth. SkyrimCustom.ini is layered
    /// afterward because the game applies it as the user override file.
    static func iniCandidates(installURL: URL) -> [(name: String, url: URL)] {
        let profile = installURL.appending(path: "Skyrim", directoryHint: .isDirectory)
        return [
            ("Skyrim.ini", installURL.appending(path: "Skyrim.ini")),
            ("Skyrim/Skyrim.ini", profile.appending(path: "Skyrim.ini")),
            ("SkyrimCustom.ini", installURL.appending(path: "SkyrimCustom.ini")),
            ("Skyrim/SkyrimCustom.ini", profile.appending(path: "SkyrimCustom.ini"))
        ]
    }

    static func load(
        root: GameDataRoot?,
        defaults: UserDefaults = GameDataLocator.settingsDefaults,
        fileManager: FileManager = .default
    ) -> LocalizationLanguageSnapshot {
        if
            let stored = defaults.string(forKey: overrideKey),
            let language = normalized(stored)
        {
            return LocalizationLanguageSnapshot(
                language: language,
                source: "OpenSky Settings override"
            )
        }
        guard let root else {
            return LocalizationLanguageSnapshot(language: fallback, source: "English fallback")
        }
        let ini = INISettings.load(
            candidates: iniCandidates(installURL: root.installURL),
            fileManager: fileManager
        )
        return resolve(ini)
    }

    static func resolve(_ ini: INISettings) -> LocalizationLanguageSnapshot {
        for source in ini.sources.reversed() {
            guard let raw = source.file.string(section: section, key: iniKey) else { continue }
            guard let language = normalized(raw) else { continue }
            return LocalizationLanguageSnapshot(language: language, source: source.name)
        }
        return LocalizationLanguageSnapshot(language: fallback, source: "English fallback")
    }

    static func store(
        _ value: String,
        to defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) throws {
        guard let language = normalized(value) else {
            throw LocalizationLanguageError.invalidLanguage(value)
        }
        defaults.set(language, forKey: overrideKey)
    }

    static func clearOverride(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        defaults.removeObject(forKey: overrideKey)
    }

    private static func normalized(_ value: String) -> String? {
        let language = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !language.isEmpty else { return nil }
        let permitted = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard language.unicodeScalars.allSatisfy(permitted.contains) else { return nil }
        return language
    }
}
