// What the launcher shows: one button per launch mode and one sidebar row per
// page. A new page (mods, asset cache) is one descriptor in `LauncherRegistry`.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyWorld

/// What a launcher page may ask of the app.
protocol LauncherActions: AnyObject {
    func start(_ mode: LaunchMode)
    func cancelLoad()
    func gameFolderDidChange()
}

struct LaunchModeDescriptor {
    let mode: LaunchMode
    let title: String
    let symbolName: String
    let toolTip: String
    let controlIdentifier: String
}

struct LauncherPageDescriptor {
    let id: String
    let title: String
    let symbolName: String
    let makeController: (any LauncherActions) -> NSViewController

    var sidebarIdentifier: String {
        "LauncherPage-\(id)"
    }
}

enum LauncherRegistry {
    static let modes: [LaunchModeDescriptor] = [
        LaunchModeDescriptor(
            mode: .play,
            title: "Play",
            symbolName: "play.fill",
            toolTip: "Start the game without developer tools",
            controlIdentifier: "LaunchPlayControl"
        ),
        LaunchModeDescriptor(
            mode: .developer,
            title: "Developer Mode",
            symbolName: "hammer.fill",
            toolTip: "Start the game with the sidebar and inspector panels",
            controlIdentifier: "LaunchDeveloperControl"
        )
    ]

    static let pages: [LauncherPageDescriptor] = [
        LauncherPageDescriptor(
            id: "launch",
            title: "Launch",
            symbolName: "play.circle",
            makeController: { LaunchPageViewController(actions: $0) }
        ),
        LauncherPageDescriptor(
            id: "assetCache",
            title: "Asset Cache",
            symbolName: "internaldrive",
            makeController: { _ in
                AssetCachePageViewController(coordinator: AssetCacheCoordinator(
                    store: AssetCachePageViewController.savedSettings()
                ))
            }
        ),
        LauncherPageDescriptor(
            id: "settings",
            title: "Settings",
            symbolName: "gearshape",
            makeController: { actions in
                let settings = SettingsViewController()
                settings.onSettingsChanged = { [weak actions] in actions?.gameFolderDidChange() }
                return settings
            }
        )
    ]

    static let defaultPageID = "launch"

    static func page(id: String) -> LauncherPageDescriptor? {
        pages.first { $0.id == id }
    }
}
