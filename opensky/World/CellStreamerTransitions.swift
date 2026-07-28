// Selected-door transition dispatch + async interior/exterior scene swaps. Split
// from CellStreamer so exterior grid scheduling stays readable.

import OSLog
import simd

extension CellStreamer {
    /// Returns true only when a successful transition replaced current view.
    func finishDoorTransition(_ entries: [DoorTransitionBuildResult]) -> Bool {
        guard let entry = entries.last else { return false }
        transitionInFlight = nil
        let motionInteraction = doorMotionInteraction
        doorMotionInteraction = nil
        let isRebuild = interiorRebuildInFlight
        interiorRebuildInFlight = false
        // A cell build ahead of transition on serial queue may complete in
        // same poll. Fold it into suspended exterior state first.
        _ = integrateOneBuild()
        switch entry.result {
        case let .success(transition):
            emitDoorMotion(.closed, interaction: motionInteraction)
            apply(transition: transition, sourceDoor: entry.sourceDoor, isRebuild: isRebuild)
            return true
        case let .failure(error):
            emitDoorMotion(.cancelled, interaction: motionInteraction)
            noteDoorTransitionFailure()
            let reason = String(describing: error)
            Self.logger.warning(
                "[WARNING] door transition failed: \(reason, privacy: .public)"
            )
            return false
        }
    }

    /// Returns true while interior owns current view. Exterior composition +
    /// bookkeeping remain resident but frozen until a door returns outside.
    func updateInteriorIfNeeded(
        completedLOD: [DistantLODBuildResult]
    ) -> Bool {
        guard interiorScene != nil else { return false }
        for entry in completedLOD {
            if case let .success(scene) = entry.result, let scene {
                evictUnused(scene.assets)
            }
        }
        dispatchInteriorRebuildIfNeeded()
        return true
    }

    func nearestDoor(in scene: CellScene, to position: SIMD3<Float>) -> PlacedDoor? {
        scene.doors
            .filter { simd_distance($0.position, position) <= Self.doorActivationRadius }
            .min { lhs, rhs in
                simd_distance_squared(lhs.position, position)
                    < simd_distance_squared(rhs.position, position)
            }
    }

    @discardableResult
    func requestDoorTransition(_ door: PlacedDoor?) -> Bool {
        guard transitionInFlight == nil, let door else { return false }
        transitionInFlight = door.reference
        interiorRebuildInFlight = false
        // Issue #160: the destination is built against the live store, so an
        // interior the player has already changed comes back changed.
        runner.enqueueDoorTransition(from: door.reference, state: stateSource())
        return true
    }

    private func emitDoorMotion(
        _ phase: InteractionAnimationPhase,
        interaction: PlacedInteraction?
    ) {
        guard let interaction else { return }
        onInteractionAnimation?(InteractionAnimationEvent(
            interaction: interaction,
            phase: phase
        ))
    }

    /// Swaps in a built door destination.
    ///
    /// - Parameters:
    ///   - sourceDoor: the door whose transition produced this scene, retained
    ///     for an interior so a later world-state change can be made visible by
    ///     re-running the same transition (issue #160).
    ///   - isRebuild: true when this transition is such a rebuild rather than a
    ///     player-driven move. A rebuild passes no camera to the sink, so the
    ///     scene swaps underneath a player who stays where they were standing.
    func apply(transition: DoorTransition, sourceDoor: FormID? = nil, isRebuild: Bool = false) {
        updateInteractionTarget(ray: nil)
        let camera = isRebuild
            ? nil
            : SceneCamera.teleport(placement: transition.destinationPlacement)
        switch transition.scene.location {
        case .interior:
            let previous = interiorScene
            interiorScene = transition.scene
            interiorSourceDoor = sourceDoor ?? interiorSourceDoor
            if let previous {
                evictUnused(previous.assets)
            }
            sink(transition.scene.renderScene, camera)
        case let .exterior(coordinate):
            let previousInterior = interiorScene
            interiorScene = nil
            interiorSourceDoor = nil
            interiorMutationSequence = 0
            let replaced = composition.setCell(transition.scene, at: coordinate)
            core.seedResident(coordinate)
            if let previousInterior {
                evictUnused(previousInterior.assets)
            }
            if let replaced {
                evictUnused(replaced.assets)
            }
            sink(composition.composedScene(), camera)
        case nil:
            Self.logger.warning("[WARNING] door destination scene has no CELL identity")
        }
        // A scene swap changes the ambience context even when the key matches
        // (e.g. re-entering the same interior); force a re-emit next tick.
        invalidateAmbienceContext()
        emitAmbienceContextIfNeeded()
        invalidateMusicContext()
        emitMusicContextIfNeeded()
    }
}
