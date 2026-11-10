// App side of `LoadingScreenCoordinator`: door transitions, fast travel, and loads
// start and end it, the renderer draws the cover object, the game's loading movie
// draws the tip, and a menu entry pauses the world. The rules live in the
// coordinator. See docs/engine/loading-screens.md.

public import Foundation
import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
public import OpenSkyLoading
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `LoadingScreenWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol LoadingScreenWorldHost: MenuInputConsumer {
    var loadingScreens: any LoadingScreenPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
}

public final class LoadingScreenWorldAdapter {
    public static let identifier = MenuIdentifier.loadingMenu

    public let game: any LoadingScreenWorldHost
    public let state = LoadingScreenPartState()
    /// When the session-start or travel cover went up; nil once it lifted.
    private var startCoverSince: Double?
    /// Where a fast travel lands; the cover waits until the grid is centered there.
    private var moveTarget: SIMD3<Float>?
    lazy var movie = MenuMovieOverlay(movies: game.swfMovies) { [weak self] in
        self?.game.renderer
    }

    /// A stuck build must not trap the player behind the cover.
    static let startCoverLimitSeconds = 60.0

    public let presentationHost: any LoadingScreenPresentationHost

    public var presentation: LoadingScreenPresentationAdapter {
        LoadingScreenPresentationAdapter(game: presentationHost, state: state, movie: movie)
    }

    public let clock: () -> Date

    public init(
        game: some LoadingScreenWorldHost & LoadingScreenPresentationHost,
        clock: @escaping () -> Date
    ) {
        self.clock = clock
        presentationHost = game
        self.game = game
    }

    public var now: Double {
        clock().timeIntervalSinceReferenceDate
    }

    /// Covers the session start until the near grid and the first distant ring
    /// are in, as the game does, so the world never opens with bare sky.
    public func coverSessionStart() {
        startCoverSince = now
        moveTarget = nil
        game.loadingScreens.beginLoad(at: now)
    }

    /// Fast travel: the view goes dark at once, the screen is picked once the cell
    /// at `feet` is built, and it holds until the area around it is in.
    public func coverMove(to feet: SIMD3<Float>) {
        guard !game.loadingScreens.isCovering else { return }
        startCoverSince = now
        moveTarget = feet
        game.loadingScreens.begin(at: now)
    }

    func liftStartCoverIfReady() {
        let streamer = game.streamer
        guard let since = startCoverSince else { return }
        let timedOut = now - since > Self.startCoverLimitSeconds
        if let target = moveTarget, game.loadingScreens.isWaitingForDestination {
            let scene = streamer.interiorScene
                ?? streamer.composition.cells[CellCoordinate(containing: target)]
            guard scene != nil || timedOut else { return }
            game.loadingScreens.destinationKnown(
                location: scene.flatMap { location(of: $0.locationKey) },
                at: now
            )
        }
        let arrived = moveTarget.map {
            streamer.interiorScene != nil
                || streamer.grid.center == CellCoordinate(containing: $0)
        } ?? true
        guard (arrived && streamer.startAreaReady) || timedOut else { return }
        startCoverSince = nil
        moveTarget = nil
        if timedOut {
            LoadingScreenLog.logger.warning("[WARNING] start area not ready in time; cover lifted")
        }
        let seconds = unsafe String(format: "%.2f", now - since)
        LoadingScreenLog.logger
            .notice("[INFO] start cover lifted after \(seconds, privacy: .public) s")
        game.loadingScreens.loadFinished(at: now)
    }

    /// The destination cell's location, which is where the player stands when the screen is chosen.
    func location(of locationKey: CellLocationKey) -> ResolvedFormID? {
        game.runtimeStateWorld.location(of: locationKey)
    }

    // MARK: - The loading movie

    /// Look and the arrow keys turn the object, as the game lets the player do.
    public func route(_ event: MenuInputEvent) {
        let degrees: Float = switch event {
        case let .pointer(deltaX, _): deltaX * Self.turnDegreesPerPoint
        case .move(.left): -Self.turnDegreesPerKey
        case .move(.right): Self.turnDegreesPerKey
        default: 0
        }
        guard degrees != 0 else { return }
        game.loadingScreens.turn(byDegrees: degrees, at: now)
    }

    public static let turnDegreesPerPoint: Float = 0.5
    public static let turnDegreesPerKey: Float = 10
}

extension LoadingScreenWorldAdapter: LoadingScreenWorld {}

extension LoadingScreenWorldAdapter: LoadingScreenWorldPort {}
