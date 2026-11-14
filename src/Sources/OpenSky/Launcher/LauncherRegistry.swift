// What the launcher shows: one sidebar row per page. A new page (mods) is one descriptor in
// `LauncherRegistry`.

import AppKit
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyReference
import OpenSkySession
import OpenSkyWorld
import OpenSkyWorldInterface

/// What a launcher page may ask of the app.
protocol LauncherActions: AnyObject {
    /// Opens the Play window at `start`; `.normal` is the main menu.
    func play(from start: LaunchStart)
    /// Starts Play and loads `slot`, the newest save.
    func continueGame(slot: String)
    func cancelLoad()
    func gameFolderDidChange()
    /// Opens the Play window and runs the benchmark tour in it.
    func runBenchmark(_ request: BenchmarkRequest)
    /// The running game's view for the reference game, or nil with no game open.
    func referenceView() -> ReferenceView?
    /// Moves the running game's player to the Windows game's view; false with no game open.
    func followReference(_ view: ReferenceView) -> Bool
    /// Puts the next Play window's content at `contentRect`, in screen points, not full screen.
    func placeNextGameWindow(contentRect: CGRect)
    /// Renders the running world without the interface into a PNG of this size.
    func captureWorld(to url: URL, width: Int, height: Int) throws
    /// The Windows reference game, shared with the Game menu.
    var referenceSession: ReferenceGameSession { get }
}

extension LauncherActions {
    /// What the Launch page's Play button does for `plan`.
    func start(_ plan: LaunchPlan) {
        switch plan {
        case let .resume(slot): continueGame(slot: slot)
        case .mainMenu: play(from: .normal)
        case let .newGame(start): play(from: start)
        }
    }
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
        store: AssetOptimisationPageViewController.savedSettings(), environment: .live
    )

    /// The places of the install; nil until a load has ended well.
    var startPlaces: StartPlaceList?
    var onStartPlacesChange: () -> Void = {}
    private var placesLoad: Task<Void, Never>?
    private var placesFolder: String?
    nonisolated private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky", category: "Launcher"
    )

    var isLoadingStartPlaces: Bool {
        placesLoad != nil
    }

    init(actions: (any LauncherActions)?) {
        self.actions = actions
    }

    /// Reads the places once per game folder, off the main actor. A test host has
    /// no install, so a test sets `startPlaces` itself.
    func loadStartPlaces() {
        guard
            !GameDataLocator.isRunningInTestHost, let root = try? GameDataLocator.locate()
        else { return }
        let folder = root.installURL.path(percentEncoded: false)
        guard folder != placesFolder else { return }
        placesFolder = folder
        placesLoad?.cancel()
        startPlaces = nil
        placesLoad = Task { [weak self] in
            let list = await Self.readStartPlaces(root: root)
            guard !Task.isCancelled, let self else { return }
            startPlaces = list
            placesLoad = nil
            onStartPlacesChange()
        }
        onStartPlacesChange()
    }

    @concurrent
    nonisolated private static func readStartPlaces(root: GameDataRoot) async -> StartPlaceList? {
        do {
            return try StartPlaceList.load(root: root)
        } catch {
            let reason = String(describing: error)
            logger.error("[ERROR] the place list did not load: \(reason, privacy: .public)")
            return nil
        }
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
            id: "reference",
            title: "Reference Game",
            symbolName: "rectangle.split.2x1",
            makeController: { ReferencePageViewController(context: $0) }
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
