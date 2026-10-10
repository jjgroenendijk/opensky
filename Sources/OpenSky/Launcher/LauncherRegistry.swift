// What the launcher shows: one button per launch mode and one sidebar row per
// page. A new page (mods) is one descriptor in `LauncherRegistry`.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyWorld

/// What a launcher page may ask of the app.
protocol LauncherActions: AnyObject {
    func start(_ mode: LaunchMode)
    /// Starts Play and loads `slot`, the newest save.
    func continueGame(slot: String)
    func cancelLoad()
    func gameFolderDidChange()
}

struct LaunchModeDescriptor {
    let mode: LaunchMode
    let title: String
    let symbolName: String
    let toolTip: String
    /// The one line under the button on what the mode starts.
    let summary: String
    let controlIdentifier: String
}

/// What the pages share: the app's actions and one asset optimisation coordinator,
/// so the Launch page's status and the Asset Optimisation page never disagree.
@MainActor
final class LauncherContext {
    weak var actions: (any LauncherActions)?
    var showPage: (String) -> Void = { _ in }
    lazy var assetOptimisation = AssetCacheCoordinator(
        store: AssetOptimisationPageViewController.savedSettings()
    )

    init(actions: (any LauncherActions)?) {
        self.actions = actions
    }
}

struct LauncherPageDescriptor {
    let id: String
    let title: String
    let symbolName: String
    let makeController: (LauncherContext) -> NSViewController

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
            summary: "The game alone, from the start you choose",
            controlIdentifier: "LaunchPlayControl"
        ),
        LaunchModeDescriptor(
            mode: .developer,
            title: "Developer Mode",
            symbolName: "hammer.fill",
            toolTip: "Start the game with the sidebar and inspector panels",
            summary: "The game with tool panels beside it",
            controlIdentifier: "LaunchDeveloperControl"
        )
    ]

    static let pages: [LauncherPageDescriptor] = [
        LauncherPageDescriptor(
            id: "launch",
            title: "Launch",
            symbolName: "play.circle",
            makeController: { LaunchPageViewController(context: $0) }
        ),
        LauncherPageDescriptor(
            id: "assetOptimisation",
            title: "Asset Optimisation",
            symbolName: "internaldrive",
            makeController: {
                AssetOptimisationPageViewController(coordinator: $0.assetOptimisation)
            }
        ),
        LauncherPageDescriptor(
            id: "graphics",
            title: "Graphics",
            symbolName: "cpu",
            makeController: { _ in
                GraphicsPageViewController(reloadStore: GraphicsPageViewController.installSettings)
            }
        ),
        LauncherPageDescriptor(
            id: "diagnostics",
            title: "Diagnostics",
            symbolName: "stethoscope",
            makeController: { _ in DiagnosticsPageViewController() }
        ),
        LauncherPageDescriptor(
            id: "settings",
            title: "Settings",
            symbolName: "gearshape",
            makeController: { context in
                let settings = SettingsViewController()
                settings
                    .onSettingsChanged = { [weak context] in
                        context?.actions?.gameFolderDidChange()
                    }
                return settings
            }
        )
    ]

    static let defaultPageID = "launch"

    static func page(id: String) -> LauncherPageDescriptor? {
        pages.first { $0.id == id }
    }
}
