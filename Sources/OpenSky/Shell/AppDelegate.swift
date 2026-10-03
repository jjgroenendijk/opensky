// App lifecycle. The app opens on the launcher, where the user picks the game
// folder and a launch mode. Closing a mode's window returns to the launcher.

import AppKit
import MetalKit
import OpenSkyLaunch

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gameContext = GameLaunchContext()
    private var launcher: LauncherViewController?
    private var launcherWindow: NSWindow?
    private var modeWindow: NSWindow?
    private var shellViewController: AppShellViewController?
    private var settingsController: SettingsWindowController?
    private var agentControl: AgentControlHost?

    /// The running mode, or nil while the launcher is up.
    private(set) var activeMode: LaunchMode?

    func applicationDidFinishLaunching(_: Notification) {
        // The shell is a committed dark design (Theme.swift): forcing dark
        // appearance keeps every system control on the charcoal palette.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        NSApplication.shared.mainMenu = MainMenu.make(target: self)
        agentControl = AgentControlHost()

        if let mode = LaunchPreferences.forcedMode() {
            start(mode)
        } else {
            showLauncher()
        }
        NSApplication.shared.activate()
    }

    func applicationWillTerminate(_: Notification) {
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

    private func makeModeWindow(for mode: LaunchMode) -> NSWindow {
        let game = makeGame(for: mode)
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
    private func reloadRunningMode() {
        guard let activeMode else { return }
        gameContext.resolve()
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
        guard GameFolderStatus().canStart(mode) else {
            showLauncher()
            return
        }
        LaunchPreferences.remember(mode)
        gameContext.resolve()
        let window = makeModeWindow(for: mode)
        window.delegate = self
        modeWindow = window
        activeMode = mode
        window.makeKeyAndOrderFront(nil)
        launcherWindow?.orderOut(nil)
    }

    func gameFolderDidChange() {
        launcher?.refreshGameFolder()
        reloadRunningMode()
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
