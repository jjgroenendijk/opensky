// App lifecycle. The app opens on the launcher, where the user picks the game
// folder and a launch mode. The launcher shows the world load, then the mode's
// window opens. Closing a mode's window returns to the launcher.

import AppKit
import MetalKit
import OpenSkyGameData
import OpenSkyLaunch

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gameContext = GameLaunchContext()
    private let worldLoader = WorldLoader()
    private var launcher: LauncherViewController?
    private var launcherWindow: NSWindow?
    private var modeWindow: NSWindow?
    private var shellViewController: AppShellViewController?
    private var settingsController: SettingsWindowController?
    private var agentControl: AgentControlHost?

    /// The running mode, or nil while the launcher is up.
    private(set) var activeMode: LaunchMode?
    /// Where the next Play window starts: a launcher start option or a save to continue.
    private var pendingStart = LaunchStart.normal
    private var pendingContinueSlot: String?

    func applicationDidFinishLaunching(_: Notification) {
        // The shell is a committed dark design (Theme.swift): forcing dark
        // appearance keeps every system control on the charcoal palette.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.mainMenu = MainMenu.make(target: self)
        agentControl = AgentControlHost()

        if let mode = LaunchPreferences.forcedMode() {
            begin(
                mode,
                atTitleScreen: LaunchPreferences.forcedTitleScreen(),
                showingLauncher: false
            )
        } else {
            showLauncher()
        }
        NSApplication.shared.activate()
    }

    func applicationWillTerminate(_: Notification) {
        worldLoader.cancel()
        agentControl?.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    // MARK: - Launcher

    private func showLauncher() {
        let controller = launcher ?? LauncherViewController(actions: self)
        launcher = controller
        let window = launcherWindow ?? AppWindows.makeLauncher(content: controller)
        launcherWindow = window
        controller.refreshGameFolder()
        window.makeKeyAndOrderFront(nil)
    }

    @objc func returnToLauncher(_: Any?) {
        modeWindow?.close()
    }

    // MARK: - Modes

    private func makeModeWindow(for mode: LaunchMode, atTitleScreen: Bool) -> NSWindow {
        let game = makeGame(for: mode)
        game.startsAtTitleScreen = atTitleScreen
        if mode == .play {
            game.launchStart = pendingStart
            game.continueSlot = pendingContinueSlot
        }
        pendingStart = .normal
        pendingContinueSlot = nil
        switch mode {
        case .play:
            shellViewController = nil
            return AppWindows.makePlay(game: game)
        case .developer:
            let shell = AppShellViewController(
                gameViewController: game,
                fullContentContext: gameContext.makeFullContentContext()
            )
            shellViewController = shell
            return AppWindows.makeDeveloper(shell: shell)
        }
    }

    private func makeGame(for mode: LaunchMode) -> GameViewController {
        let game = gameContext.makeGameViewController()
        agentControl?.attach(game: game, mode: mode, root: gameContext.gameDataRoot)
        return game
    }

    /// Ends the running mode. The window is already closing, so this only
    /// stops the draw loop and drops the game graph.
    private func endMode() {
        cancelLoad()
        pauseRendering(
            shellViewController?.gameViewController
                ?? modeWindow?.contentViewController as? GameViewController
        )
        modeWindow?.delegate = nil
        modeWindow = nil
        shellViewController = nil
        activeMode = nil
    }

    /// Stops the draw loop of a game view that is leaving its window.
    private func pauseRendering(_ game: GameViewController?) {
        (game?.viewIfLoaded as? MTKView)?.isPaused = true
    }

    // MARK: - Settings

    @objc func openSettings(_: Any?) {
        let controller = settingsController ?? SettingsWindowController()
        settingsController = controller
        controller.onSettingsChanged = { [weak self] in self?.gameFolderDidChange() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// A settings change applies without a relaunch, to whatever is running.
    /// The launcher shows the load, and the new game view swaps in after it.
    private func reloadRunningMode() {
        guard activeMode != nil else { return }
        gameContext.resolve()
        showLauncher()
        loadWorld { [weak self] in self?.swapRunningGame() }
    }

    private func swapRunningGame() {
        guard let activeMode else { return }
        launcherWindow?.orderOut(nil)
        let game = makeGame(for: activeMode)
        switch activeMode {
        case .developer:
            shellViewController?.reload(
                gameViewController: game,
                fullContentContext: gameContext.makeFullContentContext()
            )
        case .play:
            pauseRendering(modeWindow?.contentViewController as? GameViewController)
            modeWindow?.contentViewController = game
        }
    }
}

extension AppDelegate: LauncherActions {
    func start(_ mode: LaunchMode) {
        pendingStart = mode == .play ? LaunchPreferences.savedStart() : .normal
        pendingContinueSlot = nil
        begin(mode, atTitleScreen: mode.opensAtTitleScreen && pendingStart == .normal)
    }

    func continueGame(slot: String) {
        pendingStart = .normal
        pendingContinueSlot = slot
        begin(.play, atTitleScreen: false)
    }

    func gameFolderDidChange() {
        // A load in the launcher reads the old folder, so it stops.
        if activeMode == nil {
            cancelLoad()
        }
        launcher?.refreshGameFolder()
        reloadRunningMode()
    }

    func cancelLoad() {
        worldLoader.cancel()
        launcher?.endLoad()
    }

    /// A forced mode skips the launcher, so its load shows no panel.
    private func begin(_ mode: LaunchMode, atTitleScreen: Bool, showingLauncher: Bool = true) {
        guard GameFolderStatus().canStart(mode) else {
            showLauncher()
            return
        }
        LaunchPreferences.remember(mode)
        gameContext.resolve()
        if showingLauncher {
            showLauncher()
        }
        loadWorld { [weak self] in self?.open(mode, atTitleScreen: atTitleScreen) }
    }

    /// The load runs off the main actor, so the launcher stays responsive and
    /// draws each stage as it starts and finishes.
    private func loadWorld(then finish: @escaping () -> Void) {
        launcher?.beginLoad()
        gameContext.load(
            with: worldLoader,
            onUpdate: { [weak self] timeline, elapsed in
                self?.launcher?.showLoad(timeline, elapsed: elapsed)
            },
            completion: { [weak self] in
                self?.launcher?.endLoad()
                finish()
            }
        )
    }

    private func open(_ mode: LaunchMode, atTitleScreen: Bool) {
        let window = makeModeWindow(for: mode, atTitleScreen: atTitleScreen)
        window.delegate = self
        modeWindow = window
        activeMode = mode
        window.makeKeyAndOrderFront(nil)
        launcherWindow?.orderOut(nil)
        if
            mode == .play, Self.savedSettings().bool(.fullScreen),
            !window.styleMask.contains(.fullScreen)
        {
            window.toggleFullScreen(nil)
        }
    }

    private static func savedSettings() -> PlayerSettingsStore {
        PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === modeWindow else { return }
        endMode()
        showLauncher()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(returnToLauncher(_:)) ? activeMode != nil : true
    }
}
