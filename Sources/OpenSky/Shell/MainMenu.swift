// The main menu, built in code. Every shell command is listed here, so no
// behavior hides behind an unadvertised keystroke (docs/tools/app-ui.md).

import AppKit

enum MainMenu {
    static func make(target: AppDelegate) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(makeAppMenu(target: target)))
        mainMenu.addItem(submenuItem(makeGameMenu(target: target)))
        mainMenu.addItem(submenuItem(makeViewMenu()))
        mainMenu.addItem(submenuItem(makeEditMenu()))
        return mainMenu
    }

    /// Every action here resolves on the responder chain to the shell's
    /// split-view controller, which also validates them.
    static func makeViewMenu() -> NSMenu {
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(item(
            title: "Hide Sidebar",
            action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s",
            modifiers: [.control, .command]
        ))
        viewMenu.addItem(item(
            title: "Show Frame HUD",
            action: #selector(AppShellViewController.toggleFrameHUD(_:)),
            keyEquivalent: "h",
            modifiers: [.option, .command]
        ))
        viewMenu.addItem(item(
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

    private static func makeAppMenu(target: AppDelegate) -> NSMenu {
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppDelegate.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit OpenSky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return appMenu
    }

    private static func makeGameMenu(target: AppDelegate) -> NSMenu {
        let gameMenu = NSMenu(title: "Game")
        let launcherItem = item(
            title: "Return to Launcher",
            action: #selector(AppDelegate.returnToLauncher(_:)),
            keyEquivalent: "l",
            modifiers: [.shift, .command]
        )
        launcherItem.target = target
        launcherItem.identifier = NSUserInterfaceItemIdentifier("ReturnToLauncherCommand")
        gameMenu.addItem(launcherItem)
        return gameMenu
    }

    private static func makeEditMenu() -> NSMenu {
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
        return editMenu
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let menuItem = NSMenuItem()
        menuItem.submenu = menu
        return menuItem
    }

    private static func item(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }
}
