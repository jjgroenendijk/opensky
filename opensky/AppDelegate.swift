// App lifecycle: builds the main window and menu in code (no storyboard).
// Game data is located before the window content exists so the cell scene
// factory can be wired into GameViewController ahead of its view loading.

import AppKit
import Metal
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GameData"
    )

    private var windowController: NSWindowController?

    /// Located install, nil when locating failed. Consumers (VFS, loaders) read this.
    private(set) var gameDataRoot: GameDataRoot?

    /// Resource lookup over the located install; nil when locating failed.
    private(set) var virtualFileSystem: VirtualFileSystem?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.mainMenu = Self.makeMainMenu()

        // Unit-test host never reaches here (OpenSkyApp.main skips the
        // delegate under XCTest), so the probe runs unconditionally.
        // Located before window content: the scene factory must be in
        // place when GameViewController's view loads.
        locateGameData()

        let gameViewController = GameViewController()
        gameViewController.cellProviderFactory = makeCellProviderFactory()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSky"
        window.contentViewController = gameViewController
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
    /// controller falls back to DemoScene -- the missing-data alert already
    /// covered the configuration case, so this path never crashes or re-alerts.
    private func makeCellProviderFactory() -> ((MTLDevice) -> (any CellSceneProvider)?)? {
        guard let root = gameDataRoot, let vfs = virtualFileSystem else { return nil }
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        return { device in
            do {
                let file = try ESMFile(url: esmURL)
                let textures = TextureLibrary(fileSystem: vfs, device: device)
                let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
                let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)
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

    /// Fail-loud game data probe (AGENTS.md "Loading game data"): missing or
    /// invalid install -> log + alert. No bundled fallback exists by design.
    private func locateGameData() {
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

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Skyrim Special Edition data not found"
            alert.informativeText = message
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit OpenSky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        return mainMenu
    }
}
