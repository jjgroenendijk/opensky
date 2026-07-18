// Preview app lifecycle: window + menu in code (no storyboard). Game data is
// located here and handed to the browser controller; a missing install shows
// an in-window message instead of an alert — the app always launches so the
// data root can be fixed in Settings without a crash loop (AGENTS.md
// "Loading game data").

import AppKit

final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var browser: PreviewViewController?
    private var settingsController: PreviewSettingsWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.mainMenu = makeMainMenu()

        let browser = PreviewViewController()
        do {
            browser.gameDataRoot = try GameDataLocator.locate()
        } catch {
            browser.startupErrorMessage = error.localizedDescription
        }
        self.browser = browser

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

    // MARK: - Menu

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
            withTitle: "Quit OpenSky Asset Preview",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        // Standard Edit menu so copy/paste works in the filter field and the
        // settings path label; actions resolve through the responder chain.
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
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
        let controller = settingsController ?? PreviewSettingsWindowController()
        settingsController = controller
        controller.onDataRootChanged = { [weak self] in self?.reloadBrowser() }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// Re-resolves the data root after a Settings change and reloads the
    /// browser — no relaunch needed to pick up a new install path.
    private func reloadBrowser() {
        guard let browser else { return }
        do {
            try browser.reload(root: GameDataLocator.locate())
        } catch {
            browser.reload(root: nil, errorMessage: error.localizedDescription)
        }
    }
}
