// Resolves the language segment used by localized plugin string-table paths.
// Skyrim INI files remain read-only; an explicit OpenSky Settings choice lives
// in the shared defaults domain and takes precedence.

import Foundation

nonisolated public struct LocalizationLanguageSnapshot: Equatable, Sendable {
    public let language: String
    public let source: String

    public init(language: String, source: String) {
        self.language = language
        self.source = source
    }
}

nonisolated public enum LocalizationLanguageError: Error, Equatable, Sendable {
    case invalidLanguage(String)
}

nonisolated extension LocalizationLanguageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidLanguage(value):
            "Invalid string-table language \"\(value)\". Use letters, numbers, hyphens, "
                + "or underscores."
        }
    }
}

nonisolated public enum LocalizationLanguageSettings: Sendable {
    public static let fallback = "english"
    public static let overrideKey = "LocalizationLanguage"

    private static let section = "General"
    private static let iniKey = "sLanguage"

    /// Skyrim.ini is the game's source of truth. SkyrimCustom.ini is layered
    /// afterward because the game applies it as the user override file.
    public static func iniCandidates(installURL: URL) -> [(name: String, url: URL)] {
        let profile = installURL.appending(path: "Skyrim", directoryHint: .isDirectory)
        return [
            ("Skyrim.ini", installURL.appending(path: "Skyrim.ini")),
            ("Skyrim/Skyrim.ini", profile.appending(path: "Skyrim.ini")),
            ("SkyrimCustom.ini", installURL.appending(path: "SkyrimCustom.ini")),
            ("Skyrim/SkyrimCustom.ini", profile.appending(path: "SkyrimCustom.ini"))
        ]
    }

    public static func load(
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

    public static func resolve(_ ini: INISettings) -> LocalizationLanguageSnapshot {
        for source in ini.sources.reversed() {
            guard let raw = source.file.string(section: section, key: iniKey) else { continue }
            guard let language = normalized(raw) else { continue }
            return LocalizationLanguageSnapshot(language: language, source: source.name)
        }
        return LocalizationLanguageSnapshot(language: fallback, source: "English fallback")
    }

    public static func store(
        _ value: String,
        to defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) throws {
        guard let language = normalized(value) else {
            throw LocalizationLanguageError.invalidLanguage(value)
        }
        defaults.set(language, forKey: overrideKey)
    }

    public static func clearOverride(
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
