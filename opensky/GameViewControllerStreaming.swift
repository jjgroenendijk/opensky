// Streaming setup satellite for GameViewController. Split from
// GameViewController.swift to keep that file under the strict-lint size cap
// after the M9.2.2 ambience-context subscription landed here.

import OSLog
import simd

extension GameViewController {
    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Weak captures both ways -> no retain cycle (this controller
    /// owns both renderer + streamer).
    func wireStreaming(provider: any CellSceneProvider, renderer: Renderer) {
        let runner = SerialCellBuildRunner(provider: provider)
        let controller = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    Self.logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
        // Runtime world state (issue #160). Every dispatched build snapshots the
        // store on the main thread, and every journalled mutation tells the
        // streamer which cell to rebuild so the change is visible without a
        // reload. Unowned-free: the store outlives the streamer, and the
        // streamer is captured weakly the other way.
        let worldState = worldState
        controller.stateSource = { worldState.snapshot() }
        worldState.onMutation = { [weak controller] location, sequence in
            controller?.noteStateMutation(in: location, sequence: sequence)
        }
        wireGlobals(provider: provider, renderer: renderer)
        renderer.onFrame = { [weak self, weak controller, weak renderer] position in
            let interactionRay = renderer.flatMap { renderer -> InteractionRay? in
                guard renderer.movementMode == .walk else { return nil }
                return InteractionRay(
                    origin: renderer.freeFlyCamera.position,
                    direction: renderer.freeFlyCamera.forward
                )
            }
            controller?.update(
                cameraPosition: position,
                interactionRay: interactionRay,
                activate: self?.cameraInput.consumeActivation() ?? false
            )
            if let renderer {
                self?.updateHUDFrame(renderer: renderer)
            }
        }
        // Live XCLR region feed (M7.2.3): the streamer pushes the center cell's
        // REGN set into the weather runtime so region-weighted selection runs
        // live. Same main thread as the draw loop -> WeatherSystem stays
        // single-thread-owned.
        controller.onCenterRegionsChanged = { [weak renderer] regions in
            renderer?.weather?.setRegions(regions)
        }
        controller.onInteractionTargetChanged = { [weak self] target in
            self?.updateHUDTarget(target)
        }
        wireAudioCallbacks(controller)
        renderer.terrainSampler = { [weak controller] position in
            controller?.sampleTerrain(at: position)
        }
        renderer.collisionQuery = { [weak controller] bounds in
            controller?.collisionCandidates(overlapping: bounds) ?? []
        }
        streamer = controller
    }

    /// Runtime global variables (issue #165) and the game clock (issue #164).
    /// Weather-chance selection and the clock's per-frame TimeScale read both
    /// consume `GlobalResolution`, so every global write hands each a fresh
    /// resolution rather than rebuilding cells: a global changes a number, not
    /// a scene. Writes to the five clock-owned time globals redirect into the
    /// renderer's clock instead of storing an override (one source of truth;
    /// see docs/engine/game-clock.md).
    private func wireGlobals(provider: any CellSceneProvider, renderer: Renderer) {
        let worldState = worldState
        let globalStore = (provider as? GlobalDataProviding)?.globalStore
        self.globalStore = globalStore
        renderer.weather?.setGlobalResolution(
            worldState.globalResolution(defaults: globalStore), reroll: false
        )
        renderer.gameTime.globalResolution = worldState.globalResolution(defaults: globalStore)
        worldState.onTimeGlobalWrite = { [weak renderer] timeGlobal, value in
            guard let renderer else { return nil }
            let previous = renderer.gameClock.projectedValue(timeGlobal)
            renderer.gameTime.clock.setProjectedValue(value, for: timeGlobal)
            return previous
        }
        // Weak `self` breaks what would otherwise be a cycle through the store
        // this controller owns.
        worldState.onGlobalMutation = { [weak self, weak renderer] _ in
            guard let self, let renderer else { return }
            let resolution = self.worldState.globalResolution(defaults: globalStore)
            renderer.gameTime.globalResolution = resolution
            renderer.weather?.setGlobalResolution(resolution)
        }
    }

    /// World-audio directors are built lazily alongside the audio engine, so
    /// each callback remains a no-op until audio is enabled. Papyrus
    /// OnActivate will subscribe beside the interaction handler, not replace
    /// this engine event.
    private func wireAudioCallbacks(_ controller: CellStreamer) {
        controller.onInteraction = { [weak self] event in
            self?.soundDirector?.handleInteraction(event)
        }
        controller.onInteractionAnimation = { [weak self] event in
            self?.soundDirector?.handleInteractionAnimation(event)
        }
        controller.onAmbienceContextChanged = { [weak self] context in
            self?.soundDirector?.handleAmbienceContext(context)
        }
        controller.onMusicContextChanged = { [weak self] context in
            self?.musicDirector?.handleMusicContext(context)
        }
    }
}
