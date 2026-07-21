// Typed [TerrainManager] settings consumed by distant terrain/object/tree LOD.
// OpenSky overrides live in its defaults domain; Skyrim files stay read-only.

import Foundation
import Synchronization

nonisolated struct TerrainLODConfiguration: Equatable, Sendable {
    static let fallback = TerrainLODConfiguration(
        level0Distance: 35000,
        level1Distance: 70000,
        maximumDistance: 250_000,
        treeLoadDistance: 75000
    )

    let level0Distance: Float
    let level1Distance: Float
    let maximumDistance: Float
    let treeLoadDistance: Float

    var isValid: Bool {
        level0Distance.isFinite && level0Distance > 0
            && level1Distance.isFinite && level1Distance >= level0Distance
            && maximumDistance.isFinite && maximumDistance >= level1Distance
            && treeLoadDistance.isFinite && treeLoadDistance > 0
    }
}

nonisolated struct TerrainLODConfigurationSnapshot: Equatable, Sendable {
    let configuration: TerrainLODConfiguration
    let source: String
}

nonisolated enum TerrainLODSettings {
    static let level0Key = "TerrainLODLevel0Distance"
    static let level1Key = "TerrainLODLevel1Distance"
    static let maximumKey = "TerrainLODMaximumDistance"
    static let treeKey = "TerrainLODTreeLoadDistance"

    private static let section = "TerrainManager"

    /// Skyrim files OpenSky can locate from one configured install. Order is
    /// explicit: shipped defaults < root prefs < launcher-profile prefs <
    /// Skyrim.ini < SkyrimCustom.ini. Missing files are skipped.
    static func iniCandidates(installURL: URL) -> [(name: String, url: URL)] {
        let profile = installURL.appending(path: "Skyrim", directoryHint: .isDirectory)
        return [
            ("Skyrim_Default.ini", installURL.appending(path: "Skyrim_Default.ini")),
            ("SkyrimPrefs.ini", installURL.appending(path: "SkyrimPrefs.ini")),
            ("Skyrim/SkyrimPrefs.ini", profile.appending(path: "SkyrimPrefs.ini")),
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
    ) -> TerrainLODConfigurationSnapshot {
        let base = root.map {
            resolve(
                INISettings.load(
                    candidates: iniCandidates(installURL: $0.installURL),
                    fileManager: fileManager
                )
            )
        } ?? TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
        if let override = loadOverride(from: defaults) {
            return TerrainLODConfigurationSnapshot(
                configuration: override,
                source: "OpenSky sidebar override"
            )
        }
        return base
    }

    static func resolve(_ ini: INISettings) -> TerrainLODConfigurationSnapshot {
        let fallback = TerrainLODConfiguration.fallback
        let level0 = ini.float(section: section, key: "fBlockLevel0Distance")
        let level1 = ini.float(section: section, key: "fBlockLevel1Distance")
        let maximum = ini.float(section: section, key: "fBlockMaximumDistance")
        let tree = ini.float(section: section, key: "fTreeLoadDistance")
        let configuration = TerrainLODConfiguration(
            level0Distance: level0?.value ?? fallback.level0Distance,
            level1Distance: level1?.value ?? fallback.level1Distance,
            maximumDistance: maximum?.value ?? fallback.maximumDistance,
            treeLoadDistance: tree?.value ?? fallback.treeLoadDistance
        )
        guard configuration.isValid else {
            return TerrainLODConfigurationSnapshot(
                configuration: fallback,
                source: "safe defaults"
            )
        }
        let source = [level0?.source, level1?.source, maximum?.source, tree?.source]
            .compactMap(\.self)
            .last ?? "safe defaults"
        return TerrainLODConfigurationSnapshot(configuration: configuration, source: source)
    }

    static func store(
        _ configuration: TerrainLODConfiguration,
        to defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        guard configuration.isValid else { return }
        defaults.set(Double(configuration.level0Distance), forKey: level0Key)
        defaults.set(Double(configuration.level1Distance), forKey: level1Key)
        defaults.set(Double(configuration.maximumDistance), forKey: maximumKey)
        defaults.set(Double(configuration.treeLoadDistance), forKey: treeKey)
    }

    static func clearOverride(
        from defaults: UserDefaults = GameDataLocator.settingsDefaults
    ) {
        [level0Key, level1Key, maximumKey, treeKey].forEach(defaults.removeObject(forKey:))
    }

    private static func loadOverride(from defaults: UserDefaults) -> TerrainLODConfiguration? {
        let keys = [level0Key, level1Key, maximumKey, treeKey]
        guard keys.allSatisfy({ defaults.object(forKey: $0) != nil }) else { return nil }
        let configuration = TerrainLODConfiguration(
            level0Distance: Float(defaults.double(forKey: level0Key)),
            level1Distance: Float(defaults.double(forKey: level1Key)),
            maximumDistance: Float(defaults.double(forKey: maximumKey)),
            treeLoadDistance: Float(defaults.double(forKey: treeKey))
        )
        return configuration.isValid ? configuration : nil
    }
}

nonisolated final class TerrainLODConfigurationStore: Sendable {
    private let state: Mutex<TerrainLODConfigurationSnapshot>

    init(snapshot: TerrainLODConfigurationSnapshot) {
        state = Mutex(snapshot)
    }

    static func fallback() -> TerrainLODConfigurationStore {
        TerrainLODConfigurationStore(snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        ))
    }

    func snapshot() -> TerrainLODConfigurationSnapshot {
        state.withLock { $0 }
    }

    func replace(with snapshot: TerrainLODConfigurationSnapshot) {
        state.withLock { $0 = snapshot }
    }
}
