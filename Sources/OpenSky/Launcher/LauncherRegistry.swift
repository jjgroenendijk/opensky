// What the launcher shows: one sidebar row per page. A new page (mods) is one descriptor in
// `LauncherRegistry`.

import AppKit
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyWorld

/// What a launcher page may ask of the app.
protocol LauncherActions: AnyObject {
    func play()
    /// Starts Play and loads `slot`, the newest save.
    func continueGame(slot: String)
    func cancelLoad()
    func gameFolderDidChange()
    /// Opens the Play window and runs the benchmark tour in it.
    func runBenchmark(_ request: BenchmarkRequest)
}

/// What the pages share: the app's actions and one asset optimisation coordinator,
/// so the Launch page's status and the Asset Optimisation page never disagree.
@MainActor
final class LauncherContext {
    weak var actions: (any LauncherActions)?
    var showPage: (String) -> Void = { _ in }
    /// Read again each time, because the game window may have changed the file.
    var playerSettings: () -> PlayerSettingsStore = {
        PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
    }

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
            id: "benchmark",
            title: "Benchmark",
            symbolName: "speedometer",
            makeController: { BenchmarkPageViewController(context: $0) }
        ),
        LauncherPageDescriptor(
            id: "diagnostics",
            title: "Diagnostics",
            symbolName: "stethoscope",
            makeController: { DiagnosticsPageViewController(context: $0) }
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
