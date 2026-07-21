// App lifecycle: builds the main window and menu in code (no storyboard).
// Game data is located before window content exists so both World and Asset
// Browser receive one resolved root. Settings can repeat that wiring live.

import AppKit
import Metal
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GameData"
    )

    private var windowController: NSWindowController?
    private var mainViewController: MainViewController?
    private var settingsController: SettingsWindowController?
    private var gameDataErrorMessage: String?
    private let terrainLODConfigurationStore = TerrainLODConfigurationStore(
        snapshot: TerrainLODConfigurationSnapshot(
            configuration: .fallback,
            source: "safe defaults"
        )
    )

    /// Located install, nil when locating failed. Consumers (VFS, loaders) read this.
    private(set) var gameDataRoot: GameDataRoot?

    /// Resource lookup over the located install; nil when locating failed.
    private(set) var virtualFileSystem: VirtualFileSystem?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.mainMenu = makeMainMenu()

        // Unit-test host never reaches here (OpenSkyApp.main skips the
        // delegate under XCTest), so the probe runs unconditionally.
        // Located before window content: both mode controllers need state
        // before either view loads.
        resolveGameData()

        let mainViewController = MainViewController(
            worldViewController: makeWorldViewController(),
            browserViewController: makeBrowserViewController()
        )
        self.mainViewController = mainViewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSky"
        window.contentViewController = mainViewController
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        windowController = controller

        NSApplication.shared.activate()
    }

    /// Provider factory handed to GameViewController: sets up the off-main
    /// cell builder (VFS -> ESMFile -> Texture/MeshLibrary -> CellSceneBuilder)
    /// over the located install. No cell is built here -- that walk moves to
    /// the streamer's background runner (todo 3.2), so launch never blocks on
    /// a scene build. Only the cheap setup runs on the view's device (asset
    /// libraries bind GPU resources there). Any failure past the located-data
    /// gate (missing esm, ESM parse throw) logs [ERROR] and returns nil so the
    /// controller falls back to DemoScene. Locator failures never reach this
    /// closure: World shows the in-window configuration message instead.
    private func makeCellProviderFactory() -> ((MTLDevice) -> (any CellSceneProvider)?)? {
        guard let root = gameDataRoot, let vfs = virtualFileSystem else { return nil }
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let configurationStore = terrainLODConfigurationStore
        return { device in
            do {
                let file = try ESMFile(url: esmURL)
                let textures = TextureLibrary(fileSystem: vfs, device: device)
                let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
                let builder = CellSceneBuilder(
                    file: file,
                    meshes: meshes,
                    textures: textures,
                    fileSystem: vfs,
                    terrainLODConfigurationStore: configurationStore
                )
                return BuilderCellSceneProvider(
                    builder: builder,
                    worldspaceEditorID: FirstRenderCell.worldspaceEditorID
                )
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

    private func makeWorldViewController() -> GameViewController {
        let controller = GameViewController()
        controller.cellProviderFactory = makeCellProviderFactory()
        controller.startupErrorMessage = gameDataErrorMessage
        controller.terrainLODConfigurationStore = terrainLODConfigurationStore
        return controller
    }

    private func makeBrowserViewController() -> PreviewViewController {
        let controller = PreviewViewController()
        controller.gameDataRoot = gameDataRoot
        controller.startupErrorMessage = gameDataErrorMessage
        return controller
    }

    /// Fail-loud game data probe (AGENTS.md "Loading game data"): missing or
    /// invalid install -> log + in-window message. No bundled fallback exists.
    private func resolveGameData() {
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
        terrainLODConfigurationStore.replace(with: TerrainLODSettings.load(root: gameDataRoot))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit OpenSky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenuItem.submenu = editMenu
        return mainMenu
    }

    @objc private func openSettings() {
        let controller = settingsController ?? SettingsWindowController()
        settingsController = controller
        controller.onDataRootChanged = { [weak self] in self?.reloadDataRoot() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func reloadDataRoot() {
        resolveGameData()
        mainViewController?.reload(
            worldViewController: makeWorldViewController(),
            browserRoot: gameDataRoot,
            errorMessage: gameDataErrorMessage
        )
    }
}
