// The located install, the settings read from it, and the world data loaded
// from it. Every launch mode builds its game view from one context, so World
// and Asset Browser share one root.

import AppKit
import Metal
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyWorld
import OSLog

final class GameLaunchContext {
    /// What one world load produced. Opening the archives is a load stage too.
    nonisolated struct LoadedWorld {
        let fileSystem: VirtualFileSystem
        let session: CellSession?
    }

    nonisolated private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GameData"
    )

    private(set) var gameDataRoot: GameDataRoot?
    private(set) var virtualFileSystem: VirtualFileSystem?
    /// Built by `load`, handed to the next game view, which owns it from then on.
    private var cellSession: CellSession?
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
        cellSession = nil
        gameDataErrorMessage = nil
        do {
            let root = try GameDataLocator.locate()
            gameDataRoot = root
            let source = String(describing: root.source)
            let path = root.dataURL.path(percentEncoded: false)
            Self.logger.info(
                "Game data located (\(source, privacy: .public)): \(path, privacy: .public)"
            )
        } catch {
            let message = error.localizedDescription
            Self.logger.error("Game data missing: \(message, privacy: .public)")
            gameDataErrorMessage = message
        }
        localizationLanguage = LocalizationLanguageSettings.load(root: gameDataRoot)
        terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: gameDataRoot))
    }

    /// Opens the archives and builds the world data of the resolved root off the
    /// main actor. Without a root there is nothing to load, so `completion` runs at once.
    func load(
        with loader: WorldLoader,
        onUpdate: @escaping (WorldLoadTimeline, Duration) -> Void,
        completion: @escaping () -> Void
    ) {
        guard let root = gameDataRoot else {
            completion()
            return
        }
        let language = localizationLanguage.language
        let configurationStore = terrainLODConfigurationStore
        loader.start(
            work: { progress in
                try await Self.loadWorld(
                    root: root,
                    language: language,
                    configurationStore: configurationStore,
                    progress: progress
                )
            },
            onUpdate: onUpdate,
            completion: { [weak self] world in
                self?.virtualFileSystem = world.fileSystem
                self?.cellSession = world.session
                completion()
            }
        )
    }

    func makeGameViewController() -> GameViewController {
        let controller = GameViewController()
        controller.cellSession = cellSession
        cellSession = nil
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
            // UI text. Records from another plugin read through `scoped(to:)`.
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

    /// A failure logs [ERROR] and loads no session, and the game view falls back
    /// to `DemoScene`. Only a cancel throws.
    @concurrent
    nonisolated private static func loadWorld(
        root: GameDataRoot,
        language: String,
        configurationStore: TerrainLODConfigurationStore,
        progress: WorldLoadProgress
    ) async throws -> sending LoadedWorld {
        let vfs = try progress.measure(.archives) { VirtualFileSystem(root: root) }
        logger.info("VFS ready: \(vfs.archiveCount, privacy: .public) archives in load order")
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) else {
            return LoadedWorld(fileSystem: vfs, session: nil)
        }
        do {
            let session = try await CellProviderIndexes.loadSession(
                root: root,
                fileSystem: vfs,
                device: device,
                localizationLanguage: language,
                terrainLODConfigurationStore: configurationStore,
                progress: progress
            )
            return LoadedWorld(fileSystem: vfs, session: session)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let reason = String(describing: error)
            logger.error(
                "[ERROR] cell provider setup failed, using demo scene: \(reason, privacy: .public)"
            )
            return LoadedWorld(fileSystem: vfs, session: nil)
        }
    }
}
