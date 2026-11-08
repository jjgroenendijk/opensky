// App side of `LoadingScreenCoordinator`: door transitions, fast travel, and loads
// start and end it, the renderer draws the cover object, the game's loading movie
// draws the tip, and a menu entry pauses the world. The rules live in the
// coordinator. See docs/engine/loading-screens.md.

import Foundation
public import OpenSkyCells
import OpenSkyConditions
public import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
public import OpenSkyLoading
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuests
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySession
public import OpenSkySessionInterface
import OpenSkyTerrain
public import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// What `LoadingScreenWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol LoadingScreenWorldHost: MenuInputConsumer {
    var followerCommandWorld: any FollowerCommandWorldPort { get }
    var loadingScreens: any LoadingScreenPort { get }
    var renderer: (any RendererPort)? { get }
    var runtimeStateWorld: any RuntimeStateWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var worldData: WorldDataStores? { get }
}

public final class LoadingScreenWorldAdapter {
    public static let identifier = MenuIdentifier.loadingMenu

    public unowned let game: any LoadingScreenWorldHost
    private var meshes: MeshLibrary?
    private var failedModels: Set<String> = []
    /// When the session-start or travel cover went up; nil once it lifted.
    private var startCoverSince: Double?
    /// Where a fast travel lands; the cover waits until the grid is centered there.
    private var moveTarget: SIMD3<Float>?
    public lazy var movie = MenuMovieOverlay(movies: game.swfMovies) { [weak self] in
        self?.game.renderer
    }

    /// The tip the movie shows; nil while no movie was asked for.
    public var movieText: String?
    public var movieFadedOut = false
    private var cameraPaths: AssetLoader<String, NIFCameraTrack>?
    /// A stuck build must not trap the player behind the cover.
    public static let startCoverLimitSeconds = 60.0

    public let presentationHost: any LoadingScreenPresentationHost

    public var presentation: LoadingScreenPresentationAdapter {
        LoadingScreenPresentationAdapter(
            owner: self,
            game: presentationHost
        )
    }

    public init(game: some LoadingScreenWorldHost & LoadingScreenPresentationHost) {
        presentationHost = game
        self.game = game
    }

    public var now: Double {
        Date().timeIntervalSinceReferenceDate
    }

    public func wire(streamer: CellStreamer, gameSession: GameSession) {
        streamer.onDoorTransitionStarted = { [weak self] in
            guard let self else { return }
            game.loadingScreens.begin(at: now)
        }
        streamer.onDoorTransitionFinished = { [weak self] scene in
            guard let self else { return }
            guard let scene else {
                game.loadingScreens.cancel()
                return
            }
            game.loadingScreens.destinationReady(location: location(of: scene), at: now)
            game.followerCommandWorld.bringFollowers(into: scene)
        }
        gameSession.frameSteps.register(.loadingScreen) { [weak self] _ in
            guard let self else { return }
            liftStartCoverIfReady()
            game.loadingScreens.tick(time: now)
            movie.tick()
        }
        wireCameraPaths(gameSession: gameSession)
    }

    /// The MOD2 camera meshes are small, and five serve every screen, so all are warmed.
    private func wireCameraPaths(gameSession: GameSession) {
        guard let files = game.worldData?.scriptFileSystem else { return }
        let paths = AssetLoader<String, NIFCameraTrack> { path in
            try NIFCameraTrack(file: NIFFile(data: files.contents(forPath: "meshes\\" + path)))
        }
        let screens = presentationRecords?.loadScreens.records ?? []
        for path in Set(screens.compactMap(\.record.cameraPath)) {
            paths.prefetch(path)
        }
        cameraPaths = paths
        gameSession.assetDrains.register(.loadingCameraPaths) { _ in paths.drain() }
    }

    /// The path's camera position at `seconds`, looping over the controller's window.
    private func cameraOffset(_ frame: LoadingCoverFrame) -> SIMD3<Float> {
        guard let path = frame.cameraPath, let track = cameraPaths?.value(for: path) else {
            return .zero
        }
        let length = Double(track.stopTime - track.startTime)
        let local = length > 0 ? frame.elapsedSeconds.truncatingRemainder(dividingBy: length) : 0
        return track.translation(at: track.startTime + Float(local))
    }

    /// Covers the session start until the near grid and the first distant ring
    /// are in, as the game does, so the world never opens with bare sky.
    public func coverSessionStart() {
        guard game.streamer != nil else { return }
        startCoverSince = now
        moveTarget = nil
        game.loadingScreens.beginLoad(at: now)
    }

    /// Fast travel: the view goes dark at once, the screen is picked once the cell
    /// at `feet` is built, and it holds until the area around it is in.
    public func coverMove(to feet: SIMD3<Float>) {
        guard game.streamer != nil, !game.loadingScreens.isCovering else { return }
        startCoverSince = now
        moveTarget = feet
        game.loadingScreens.begin(at: now)
    }

    private func liftStartCoverIfReady() {
        guard let since = startCoverSince, let streamer = game.streamer else { return }
        let timedOut = now - since > Self.startCoverLimitSeconds
        if let target = moveTarget, game.loadingScreens.isWaitingForDestination {
            let scene = streamer.interiorScene
                ?? streamer.composition.cells[CellCoordinate(containing: target)]
            guard scene != nil || timedOut else { return }
            game.loadingScreens.destinationKnown(
                location: scene.flatMap { location(of: $0) },
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
            Self.logger.warning("[WARNING] start area not ready in time; cover lifted")
        }
        let seconds = unsafe String(format: "%.2f", now - since)
        Self.logger.notice("[INFO] start cover lifted after \(seconds, privacy: .public) s")
        game.loadingScreens.loadFinished(at: now)
    }

    /// The destination cell's location, which is where the player stands when the screen is chosen.
    private func location(of scene: any CellScenePort) -> ResolvedFormID? {
        game.runtimeStateWorld.location(of: scene.locationKey)
    }

    public func placement(
        _ frame: LoadingCoverFrame,
        gameSession: any GameSessionPort
    ) -> [RenderPlacement] {
        let renderer = gameSession.renderer
        guard
            frame.drawsObject, let path = frame.model,
            !failedModels.contains(path) else { return [] }
        if
            meshes == nil,
            let fileSystem = game.worldData?.scriptFileSystem
        {
            meshes = (try? TextureLibrary(fileSystem: fileSystem, device: renderer.device)).map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        do {
            guard let model = try meshes?.model(path: path) else { return [] }
            let view = coverView(gameSession)
            let radius = meshes?.bounds(forPath: path)
                .map { simd_length($0.max - $0.min) / 2 } ?? 64
            return [RenderPlacement(
                model: model,
                transform: frame.objectTransform(
                    eye: view.position, yaw: view.yaw, pitch: view.pitch, radius: radius,
                    cameraOffset: cameraOffset(frame)
                ),
                castsShadows: false,
                layer: .loadingCover
            )]
        } catch {
            failedModels.insert(path)
            Self.logger.warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    public func coverView(_ gameSession: any GameSessionPort) -> FreeFlyCamera {
        gameSession.dialogueRestorePose ?? gameSession.freeFlyCamera
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

    public static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Loading"
    )
}

extension LoadingScreenWorldAdapter: LoadingScreenWorld {}

extension LoadingScreenWorldAdapter: LoadingScreenWorldPort {}
