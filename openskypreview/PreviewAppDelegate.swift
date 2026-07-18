// Preview app lifecycle: window + menu in code (no storyboard). Game data is
// located here and handed to the browser controller; a missing install shows
// an in-window message instead of an alert — the app always launches so the
// data root can be fixed without a crash loop (AGENTS.md "Loading game data").

import AppKit

final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.mainMenu = Self.makeMainMenu()

        let browser = PreviewViewController()
        do {
            browser.gameDataRoot = try GameDataLocator.locate()
        } catch {
            browser.startupErrorMessage = error.localizedDescription
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenSky Asset Preview"
        window.contentViewController = browser
        window.center()

        let controller = NSWindowController(window: window)
        controller.showWindow(nil)
        windowController = controller

        NSApplication.shared.activate()
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
            withTitle: "Quit OpenSky Asset Preview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        return mainMenu
    }
}
