// App lifecycle: builds the main window and menu in code (no storyboard).

import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GameData"
    )

    private var windowController: NSWindowController?

    /// Located install, nil when locating failed. Consumers (VFS, loaders) read this.
    private(set) var gameDataRoot: GameDataRoot?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.mainMenu = Self.makeMainMenu()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSky"
        window.contentViewController = GameViewController()
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        windowController = controller

        NSApplication.shared.activate()

        // Unit-test host runs this lifecycle too; skip the probe there so tests
        // never depend on machine state or block on the alert. UI-tested app
        // instances lack this variable and still exercise the probe.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            locateGameData()
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
