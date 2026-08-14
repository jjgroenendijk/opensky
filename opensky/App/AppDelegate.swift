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
    private var shellViewController: AppShellViewController?
    private var settingsController: SettingsWindowController?
    private var gameDataErrorMessage: String?
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

    /// Located install, nil when locating failed. Consumers (VFS, loaders) read this.
    private(set) var gameDataRoot: GameDataRoot?

    /// Resource lookup over the located install; nil when locating failed.
    private(set) var virtualFileSystem: VirtualFileSystem?

    func applicationDidFinishLaunching(_: Notification) {
        // The shell is a committed dark design (Theme.swift): forcing dark
        // appearance keeps every system control on the charcoal palette
        // regardless of the user's system setting.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.mainMenu = makeMainMenu()

        // Unit-test host never reaches here (OpenSkyApp.main skips the
        // delegate under XCTest), so the probe runs unconditionally.
        // Located before window content: every destination needs state
        // before its view loads.
        resolveGameData()

        let shell = AppShellViewController(
            gameViewController: makeWorldViewController(),
            fullContentContext: makeFullContentContext()
        )
        shellViewController = shell

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSky"
        window.contentViewController = shell
        window.toolbarStyle = .unifiedCompact
        window.toolbar = shell.makeToolbar()
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Theme.windowBackground
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
                return indexes.makeProvider()
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
        // UI Lab localized-strings readout (M8.1.4): merged translation counts
        // over the located install. Loaded lazily on first readout, not here.
        if let vfs = virtualFileSystem {
            let language = localizationLanguage.language
            controller.localizedLabelsLoader = { LocalizedLabels.load(vfs: vfs) }
            // UI Lab SWF movie selector (M8.2.5): enumerates and decodes
            // Interface movies. Built on first use, not here.
            controller.swfMovieLoaderFactory = { SWFMovieLoader(fileSystem: vfs) }
            // World > Audio picker + playback source (M9.1.3).
            controller.audioFileSystem = vfs
            // Journal quest, objective and log text (issue #184). Skyrim.esm is
            // the only plugin the session indexes quests from, so its tables
            // are the ones the journal resolves through.
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
    private func makeFullContentContext() -> FullContentContext {
        FullContentContext(
            gameDataRoot: gameDataRoot,
            startupErrorMessage: gameDataErrorMessage
        )
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
        localizationLanguage = LocalizationLanguageSettings.load(root: gameDataRoot)
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

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        viewMenuItem.submenu = Self.makeViewMenu()

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

    /// Shell chrome belongs in discoverable, listed menu commands rather than
    /// unadvertised keystrokes (docs/tools/app-ui.md). Every action here
    /// resolves on the responder chain to the shell's split-view controller,
    /// which also validates them.
    static func makeViewMenu() -> NSMenu {
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(viewMenuItem(
            title: "Hide Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.control, .command]
        ))
        viewMenu.addItem(viewMenuItem(
            title: "Show Frame HUD",
            action: #selector(AppShellViewController.toggleFrameHUD(_:)),
            keyEquivalent: "h",
            modifiers: [.option, .command]
        ))
        viewMenu.addItem(viewMenuItem(
            title: "Hide Inspector",
            action: #selector(AppShellViewController.toggleInspectorColumn(_:)),
            keyEquivalent: "i",
            modifiers: [.option, .command]
        ))
        viewMenu.addItem(.separator())
        let resetItem = NSMenuItem(
            title: "Reset all overrides",
            action: #selector(AppShellViewController.resetAllOverrides(_:)),
            keyEquivalent: ""
        )
        resetItem.identifier = NSUserInterfaceItemIdentifier("ResetAllOverridesCommand")
        viewMenu.addItem(resetItem)
        return viewMenu
    }

    private static func viewMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc private func openSettings() {
        let controller = settingsController ?? SettingsWindowController()
        settingsController = controller
        controller.onSettingsChanged = { [weak self] in self?.reloadDataRoot() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private func reloadDataRoot() {
        resolveGameData()
        shellViewController?.reload(
            gameViewController: makeWorldViewController(),
            fullContentContext: makeFullContentContext()
        )
    }
}
