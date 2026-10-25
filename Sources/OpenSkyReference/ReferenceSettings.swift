// Where the reference game lives: a Wine prefix with Windows Steam and its own copy of
// Skyrim SE, and the Wine that runs it. Both are settings, never constants.
// See docs/tools/reference-game.md.

import Foundation
import OpenSkyGameData

nonisolated public enum ReferenceSettings {
    public static let prefixEnvironmentKey = "OPENSKY_REFERENCE_PREFIX"
    public static let prefixDefaultsKey = "OpenSkyReferencePrefix"
    public static let wineEnvironmentKey = "OPENSKY_REFERENCE_WINE"
    public static let wineDefaultsKey = "OpenSkyReferenceWine"
    /// The newest comparison run, so the launcher page shows it without a terminal.
    public static let latestRunDefaultsKey = "OpenSkyReferenceLatestRun"

    public static func prefix(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = GameDataLocator.persistedRootDefaults
    ) -> URL? {
        setting(prefixEnvironmentKey, prefixDefaultsKey, environment, userDefaults)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// A setting wins; otherwise the private Wine that setup put inside the prefix.
    public static func wine(
        prefix: URL?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults? = GameDataLocator.persistedRootDefaults,
        exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let path = setting(wineEnvironmentKey, wineDefaultsKey, environment, userDefaults) {
            return URL(filePath: path)
        }
        let bundled = prefix.map { ReferencePrefix(root: $0).wine }
        return bundled.flatMap { exists($0.path(percentEncoded: false)) ? $0 : nil }
    }

    public static func latestRun(
        userDefaults: UserDefaults? = GameDataLocator.persistedRootDefaults
    ) -> URL? {
        setting("", latestRunDefaultsKey, [:], userDefaults)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    public static func storePrefix(
        _ folder: URL, in defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        defaults.set(folder.path(percentEncoded: false), forKey: prefixDefaultsKey)
    }

    public static func clearPrefix(in defaults: UserDefaults = GameDataLocator.settingsDefaults) {
        defaults.removeObject(forKey: prefixDefaultsKey)
    }

    public static func storeLatestRun(
        _ folder: URL, in defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        defaults.set(folder.path(percentEncoded: false), forKey: latestRunDefaultsKey)
    }

    private static func setting(
        _ environmentKey: String, _ defaultsKey: String,
        _ environment: [String: String], _ userDefaults: UserDefaults?
    ) -> String? {
        let path = environment[environmentKey].flatMap { $0.isEmpty ? nil : $0 }
            ?? userDefaults?.string(forKey: defaultsKey)
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}
