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
        controller.onInteraction = { [weak self] event in
            // World SFX director subscription (M9.2.2). The director is built
            // lazily alongside the audio engine; before that this is a no-op.
            // Papyrus OnActivate will subscribe here alongside, not replace.
            self?.soundDirector?.handleInteraction(event)
        }
        controller.onAmbienceContextChanged = { [weak self] context in
            self?.soundDirector?.handleAmbienceContext(context)
        }
        // Music director subscription (M9.2.3). Same lazy-construction policy
        // as the sound director: a no-op until audio is enabled.
        controller.onMusicContextChanged = { [weak self] context in
            self?.musicDirector?.handleMusicContext(context)
        }
        renderer.terrainSampler = { [weak controller] position in
            controller?.sampleTerrain(at: position)
        }
        renderer.collisionQuery = { [weak controller] bounds in
            controller?.collisionCandidates(overlapping: bounds) ?? []
        }
        streamer = controller
    }
}
