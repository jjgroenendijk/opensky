// Typed [TerrainManager] settings consumed by distant terrain/object/tree LOD.
// Skyrim files stay read-only.

import Foundation
import Synchronization

nonisolated public struct TerrainLODConfiguration: Equatable, Sendable {
    public static let fallback = TerrainLODConfiguration(
        level0Distance: 35000,
        level1Distance: 70000,
        maximumDistance: 250_000,
        treeLoadDistance: 75000
    )

    /// The game's default `uGridsToLoad` (CK wiki "UGridsToLoad").
    public static let defaultGridsToLoad: Float = 5
    /// An OpenSky limit, so a typo cannot ask for thousands of full-detail cells.
    public static let maximumLoadedGridRadius: Int32 = 10

    public let level0Distance: Float
    public let level1Distance: Float
    public let maximumDistance: Float
    public let treeLoadDistance: Float
    /// Rings of full-detail cells around the centre cell; distant LOD starts past them.
    public let loadedGridRadius: Int32

    public var isValid: Bool {
        level0Distance.isFinite && level0Distance > 0
            && level1Distance.isFinite && level1Distance >= level0Distance
            && maximumDistance.isFinite && maximumDistance >= level1Distance
            && treeLoadDistance.isFinite && treeLoadDistance > 0
    }

    public init(
        level0Distance: Float,
        level1Distance: Float,
        maximumDistance: Float,
        treeLoadDistance: Float,
        loadedGridRadius: Int32 = 2
    ) {
        self.level0Distance = level0Distance
        self.level1Distance = level1Distance
        self.maximumDistance = maximumDistance
        self.treeLoadDistance = treeLoadDistance
        self.loadedGridRadius = loadedGridRadius
    }

    /// `uGridsToLoad` is the grid's full side, always odd in the game: 5 gives 2 rings.
    public static func loadedGridRadius(gridsToLoad: Float) -> Int32 {
        guard gridsToLoad.isFinite, gridsToLoad >= 1 else { return 0 }
        let side = min(gridsToLoad, Float(maximumLoadedGridRadius * 2 + 1))
        return Int32((side - 1) / 2)
    }
}

nonisolated public struct TerrainLODConfigurationSnapshot: Equatable, Sendable {
    public let configuration: TerrainLODConfiguration
    public let source: String

    public init(configuration: TerrainLODConfiguration, source: String) {
        self.configuration = configuration
        self.source = source
    }
}

nonisolated public enum TerrainLODSettings: Sendable {
    private static let section = "TerrainManager"

    /// Skyrim files OpenSky can locate from one configured install. Order is
    /// explicit: shipped defaults < root prefs < launcher-profile prefs <
    /// Skyrim.ini < SkyrimCustom.ini. Missing files are skipped.
    public static func iniCandidates(installURL: URL) -> [(name: String, url: URL)] {
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

    /// `settings`, the player settings file's bytes, adds the Graphics page's view
    /// distances over the INI files.
    public static func load(
        root: GameDataRoot?,
        settings: Data? = nil,
        fileManager: FileManager = .default
    ) -> TerrainLODConfigurationSnapshot {
        root.map {
            let ini = INISettings.load(
                candidates: iniCandidates(installURL: $0.installURL),
                fileManager: fileManager
            )
            return applyingGraphics(resolve(ini), ini: ini, settings: settings)
        } ?? TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    }

    /// The store's defaults come from the same INI files, so an unchanged store keeps them.
    static func applyingGraphics(
        _ snapshot: TerrainLODConfigurationSnapshot, ini: INISettings,
        settings: Data?
    ) -> TerrainLODConfigurationSnapshot {
        let catalog = PlayerSettingsCatalog.vanilla.applyingINIDefaults(ini)
        guard
            let settings, let model = try? PlayerSettingsModel(
                decoding: settings,
                catalog: catalog
            )
        else { return snapshot }
        func distance(_ key: String) -> Float {
            Float(model.value(PlayerSettingID("graphics.\(key)"), in: catalog))
        }
        let configuration = TerrainLODConfiguration(
            level0Distance: distance("fBlockLevel0Distance"),
            level1Distance: distance("fBlockLevel1Distance"),
            maximumDistance: distance("fBlockMaximumDistance"),
            treeLoadDistance: distance("fTreeLoadDistance"),
            loadedGridRadius: TerrainLODConfiguration.loadedGridRadius(
                gridsToLoad: distance("uGridsToLoad")
            )
        )
        guard
            configuration != snapshot.configuration,
            configuration.isValid else { return snapshot }
        return TerrainLODConfigurationSnapshot(
            configuration: configuration,
            source: "OpenSky Graphics page"
        )
    }

    public static func resolve(_ ini: INISettings) -> TerrainLODConfigurationSnapshot {
        let fallback = TerrainLODConfiguration.fallback
        let level0 = ini.float(section: section, key: "fBlockLevel0Distance")
        let level1 = ini.float(section: section, key: "fBlockLevel1Distance")
        let maximum = ini.float(section: section, key: "fBlockMaximumDistance")
        let tree = ini.float(section: section, key: "fTreeLoadDistance")
        let grids = ini.float(section: "General", key: "uGridsToLoad")
        let configuration = TerrainLODConfiguration(
            level0Distance: level0?.value ?? fallback.level0Distance,
            level1Distance: level1?.value ?? fallback.level1Distance,
            maximumDistance: maximum?.value ?? fallback.maximumDistance,
            treeLoadDistance: tree?.value ?? fallback.treeLoadDistance,
            loadedGridRadius: TerrainLODConfiguration.loadedGridRadius(
                gridsToLoad: grids?.value ?? TerrainLODConfiguration.defaultGridsToLoad
            )
        )
        guard configuration.isValid else {
            return TerrainLODConfigurationSnapshot(
                configuration: fallback,
                source: "safe defaults"
            )
        }
        let source = [level0?.source, level1?.source, maximum?.source, tree?.source, grids?.source]
            .compactMap(\.self)
            .last ?? "safe defaults"
        return TerrainLODConfigurationSnapshot(configuration: configuration, source: source)
    }
}

nonisolated public final class TerrainLODConfigurationStore: Sendable {
    private let state: Mutex<TerrainLODConfigurationSnapshot>

    public init(snapshot: TerrainLODConfigurationSnapshot) {
        state = Mutex(snapshot)
    }

    public static func fallback() -> TerrainLODConfigurationStore {
        TerrainLODConfigurationStore(snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        ))
    }

    public func snapshot() -> TerrainLODConfigurationSnapshot {
        state.withLock { $0 }
    }

    public func replace(with snapshot: TerrainLODConfigurationSnapshot) {
        state.withLock { $0 = snapshot }
    }
}
