// App side of `LoadingScreenCoordinator`: door transitions start and end it,
// the renderer draws the cover object and the text, and a menu entry pauses
// the world. The rules live in the coordinator. See docs/engine/loading-screens.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyWorld
import simd

final class LoadingScreenWorldAdapter {
    static let identifier: MenuIdentifier = "LoadingMenu"

    unowned let game: GameViewController
    private var meshes: MeshLibrary?
    private var failedModels: Set<String> = []
    /// When the session-start cover went up; nil once it lifted.
    private var startCoverSince: Double?
    /// A stuck build must not trap the player behind the cover.
    static let startCoverLimitSeconds = 60.0

    init(game: GameViewController) {
        self.game = game
    }

    var now: Double {
        Date().timeIntervalSinceReferenceDate
    }

    func wire(streamer: CellStreamer, renderer: Renderer) {
        let loading = game.loadingScreens
        loading.attach(world: self)
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
        }
        renderer.onFrame.add { [weak self] _ in
            guard let self else { return }
            liftStartCoverIfReady()
            game.loadingScreens.tick(time: now)
        }
    }

    /// Covers the session start until the near grid and the first distant ring
    /// are in, as the game does, so the world never opens with bare sky.
    func coverSessionStart() {
        guard game.streamer != nil else { return }
        startCoverSince = now
        game.loadingScreens.beginLoad(at: now)
    }

    private func liftStartCoverIfReady() {
        guard let since = startCoverSince, let streamer = game.streamer else { return }
        let timedOut = now - since > Self.startCoverLimitSeconds
        guard streamer.startAreaReady || timedOut else { return }
        startCoverSince = nil
        if timedOut {
            Self.logger.warning("[WARNING] start area not ready in time; cover lifted")
        }
        let seconds = String(format: "%.2f", now - since)
        Self.logger.notice("[INFO] start cover lifted after \(seconds, privacy: .public) s")
        game.loadingScreens.loadFinished(at: now)
    }

    /// The destination cell's `XLCN`, which is where the player stands when the screen is chosen.
    private func location(of scene: CellScene) -> ResolvedFormID? {
        guard
            let link = scene.locationLink,
            let plugin = scene.ownerPluginName,
            let locations = (game.worldData as? LocationDataProviding)?.locationStore
        else { return nil }
        return locations.resolvedID(link, fromPlugin: plugin)
    }

    private func placement(_ frame: LoadingCoverFrame, renderer: Renderer) -> [RenderPlacement] {
        guard
            frame.drawsObject, let path = frame.model,
            !failedModels.contains(path) else { return [] }
        if
            meshes == nil,
            let fileSystem = (game.worldData as? ScriptDataProviding)?.scriptFileSystem
        {
            meshes = (try? TextureLibrary(fileSystem: fileSystem, device: renderer.device)).map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        do {
            guard let model = try meshes?.model(path: path) else { return [] }
            let view = renderer.dialogueCameraState.restorePose ?? renderer.freeFlyCamera
            let radius = meshes?.bounds(forPath: path)
                .map { simd_length($0.max - $0.min) / 2 } ?? 64
            return [RenderPlacement(
                model: model,
                transform: frame.objectTransform(eye: view.position, yaw: view.yaw, radius: radius),
                castsShadows: false,
                layer: .loadingCover
            )]
        } catch {
            failedModels.insert(path)
            Self.logger.warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Loading"
    )
}

extension LoadingScreenWorldAdapter: LoadingScreenWorld {
    var presentationRecords: PresentationRecordStore? {
        (game.worldData as? PresentationDataProviding)?.presentationRecords
    }

    /// Most LSCR conditions ask about the location, so the context carries the LCTN store.
    func loadingConditionContext() -> ConditionContext {
        var context = game.runtimeState.conditionContext()
        context.data = ConditionDataResolution(
            formLists: (game.worldData as? FactionDataProviding)?.formListStore,
            locations: (game.worldData as? LocationDataProviding)?.locationStore
        )
        return context
    }

    func loadingText(of screen: ResolvedRecord<LoadScreen>) -> String? {
        DialogueMenuModel.text(
            screen.record.description,
            kind: .strings,
            strings: game.journal.strings?.scoped(to: screen.sourcePlugin)
        )
    }

    func presentLoadingCover(_ frame: LoadingCoverFrame?) {
        guard let renderer = game.renderer else { return }
        do {
            if let frame, frame.drawsObject {
                try renderer.setLoadingCover(placement(frame, renderer: renderer))
            } else {
                try renderer.setLoadingCover(nil)
            }
        } catch {
            Self.logger
                .error(
                    "[ERROR] loading cover failed: \(String(describing: error), privacy: .public)"
                )
        }
        renderer.uiScene = frame?.overlay ?? .empty
    }

    var currentLocation: ResolvedFormID? {
        guard
            let streamer = game.streamer,
            let cell = streamer.currentCellLocation,
            let scene = streamer.residentScene(at: cell)
        else { return nil }
        return location(of: scene)
    }

    func setLoadingPaused(_ paused: Bool) {
        if paused {
            game.menuMode.inputConsumer = game
            game.menuMode.present(Self.identifier)
        } else {
            game.menuMode.dismiss(Self.identifier)
        }
    }
}
