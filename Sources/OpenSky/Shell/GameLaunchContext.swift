// The located install and the settings read from it. Every launch mode builds
// its game view from one context, so World and Asset Browser share one root.

import AppKit
import Metal
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyWorld
import OSLog

final class GameLaunchContext {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GameData"
    )

    private(set) var gameDataRoot: GameDataRoot?
    private(set) var virtualFileSystem: VirtualFileSystem?
    private(set) var gameDataErrorMessage: String?
    private var localizationLanguage = LocalizationLanguageSnapshot(
        language: LocalizationLanguageSettings.fallback,
        source: "English fallback"
    )
    private let terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Fail-loud game data probe (AGENTS.md "Loading game data"): missing or
    /// invalid install -> log + in-window message. No bundled fallback exists.
    func resolve() {
        gameDataRoot = nil
        virtualFileSystem = nil
        gameDataErrorMessage = nil
        do {
            let root = try GameDataLocator.locate()
            gameDataRoot = root
            let source = String(describing: root.source)
            let path = root.dataURL.path(percentEncoded: false)
            Self.logger.info(
                "Game data located (\(source, privacy: .public)): \(path, privacy: .public)"
            )

            let vfs = VirtualFileSystem(root: root)
            virtualFileSystem = vfs
            Self.logger.info(
                "VFS ready: \(vfs.archiveCount, privacy: .public) archives in load order"
            )
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Game data missing: \(message, privacy: .public)")
            gameDataErrorMessage = message
        }
        localizationLanguage = LocalizationLanguageSettings.load(root: gameDataRoot)
        terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: gameDataRoot))
    }

    func makeGameViewController() -> GameViewController {
        let controller = GameViewController()
        controller.cellSessionFactory = makeCellSessionFactory()
        controller.startupErrorMessage = gameDataErrorMessage
        controller.terrainLODConfigurationStore = terrainLODConfigurationStore
        controller.settingsCatalog = gameDataRoot.map { root in
            PlayerSettingsCatalog.vanilla.applyingINIDefaults(INISettings.load(
                candidates: PlayerSettingsCatalog.iniCandidates(installURL: root.installURL)
            ))
        } ?? .vanilla
        // Both loaders run on first use, not here, because they walk the VFS.
        if let vfs = virtualFileSystem {
            let language = localizationLanguage.language
            controller.uiLab.localizedLabelsLoader = { LocalizedLabels.load(vfs: vfs) }
            controller.swfMovies.factory = { SWFMovieLoader(fileSystem: vfs) }
            controller.menuTextLoader = { LocalizedLabels.load(vfs: vfs, language: language) }
            controller.controlMapLoader = {
                try ControlMapFile(data: vfs.contents(forPath: ControlMapFile.path))
            }
            // World > Audio picker and playback source.
            controller.audioFileSystem = vfs
            // Journal text. The session indexes quests only from Skyrim.esm,
            // so its string tables are the ones the journal uses.
            controller.localizedStringsLoader = {
                LocalizedStrings(
                    vfs: vfs,
                    pluginName: "Skyrim.esm",
                    language: language
                )
            }
        }
        return controller
    }

    /// Root context handed to full-content destination factories (and reload).
    func makeFullContentContext() -> FullContentContext {
        FullContentContext(
            gameDataRoot: gameDataRoot,
            startupErrorMessage: gameDataErrorMessage
        )
    }

    /// Sets up the off-main cell builder over the located install. No cell is
    /// built here, so launch never waits on a scene. A failure logs [ERROR] and
    /// returns nil, and the controller falls back to `DemoScene`.
    private func makeCellSessionFactory() -> ((MTLDevice) -> CellSession?)? {
        guard let root = gameDataRoot, let vfs = virtualFileSystem else { return nil }
        let configurationStore = terrainLODConfigurationStore
        let language = localizationLanguage.language
        return { device in
            do {
                let indexes = try CellProviderIndexes(
                    root: root,
                    fileSystem: vfs,
                    device: device,
                    localizationLanguage: language,
                    terrainLODConfigurationStore: configurationStore
                )
                return indexes.makeSession()
            } catch {
                let reason = String(describing: error)
                Self.logger.error(
                    """
                    [ERROR] cell provider setup failed, using demo scene: \
                    \(reason, privacy: .public)
                    """
                )
                return nil
            }
        }
    }
}
