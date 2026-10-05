// Selected-door transition dispatch + async interior/exterior scene swaps. Split
// from CellStreamer so exterior grid scheduling stays readable.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorldInterface
import simd

extension CellStreamer {
    /// Returns true only when a successful transition replaced current view.
    public func finishDoorTransition(_ entries: [DoorTransitionBuildResult]) -> Bool {
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
            if !isRebuild {
                onDoorTransitionFinished?(transition.scene)
            }
            return true
        case let .failure(error):
            emitDoorMotion(.cancelled, interaction: motionInteraction)
            noteDoorTransitionFailure()
            if !isRebuild {
                onDoorTransitionFinished?(nil)
            }
            let reason = String(describing: error)
            Self.logger.warning(
                "[WARNING] door transition failed: \(reason, privacy: .public)"
            )
            return false
        }
    }

    /// Returns true while interior owns current view. Exterior composition +
    /// bookkeeping remain resident but frozen until a door returns outside.
    public func updateInteriorIfNeeded(
        completedLOD: [DistantLODBuildResult]
    ) -> Bool {
        guard interiorScene != nil else { return false }
        if integrateActorProps() {
            sink(viewScene(), nil)
        }
        for entry in completedLOD {
            if case let .success(scene) = entry.result, let scene {
                evictUnused(scene.assets)
            }
        }
        dispatchInteriorRebuildIfNeeded()
        return true
    }

    public func nearestDoor(in scene: CellScene, to position: SIMD3<Float>) -> PlacedDoor? {
        scene.doors
            .filter { simd_distance($0.position, position) <= Self.doorActivationRadius }
            .min { lhs, rhs in
                simd_distance_squared(lhs.position, position)
                    < simd_distance_squared(rhs.position, position)
            }
    }

    @discardableResult
    public func requestDoorTransition(_ door: PlacedDoor?) -> Bool {
        guard let door else { return false }
        return requestDoorTransition(from: door.reference)
    }

    /// Goes through any door REFR in the load order, resident or not. A
    /// console-style teleport into an interior enters through its door.
    @discardableResult
    public func requestDoorTransition(from sourceDoor: FormID) -> Bool {
        guard transitionInFlight == nil else { return false }
        transitionInFlight = sourceDoor
        interiorRebuildInFlight = false
        // Built against the live store, so a changed interior comes back changed.
        runner.enqueueDoorTransition(from: sourceDoor, state: stateSource())
        onDoorTransitionStarted?()
        return true
    }

    /// Drops the interior and shows the resident exterior again at `camera`,
    /// for a teleport out that uses no door. The grid then follows the camera.
    public func leaveInterior(camera: SceneCamera) {
        guard let previous = interiorScene else { return }
        interiorScene = nil
        interiorSourceDoor = nil
        interiorMutationSequence = 0
        updateInteractionTarget(ray: nil)
        emitCellDetached(previous)
        evictUnused(previous.assets)
        sink(viewScene(), camera)
        invalidateAmbienceContext()
        invalidateMusicContext()
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
    /// - Parameters:
    ///   - sourceDoor: kept for an interior, so a world-state change can rerun it.
    ///   - isRebuild: true for such a rerun; no camera is passed, so the player stays put.
    public func apply(
        transition: DoorTransition,
        sourceDoor: FormID? = nil,
        isRebuild: Bool = false
    ) {
        updateInteractionTarget(ray: nil)
        let camera = isRebuild
            ? nil
            : SceneCamera.teleport(placement: transition.destinationPlacement)
        switch transition.scene.location {
        case .interior:
            let previous = interiorScene
            interiorScene = transition.scene
            interiorSourceDoor = sourceDoor ?? interiorSourceDoor
            // A rebuild re-enters the same interior, so its scripts stay
            // attached; only a player-driven move retires the old cell.
            if let previous {
                if !isRebuild {
                    emitCellDetached(previous)
                }
                evictUnused(previous.assets)
            }
            emitCellAttached(transition.scene, firstIntegration: !isRebuild)
            sink(viewScene(), camera)
        case let .exterior(coordinate):
            let previousInterior = interiorScene
            interiorScene = nil
            interiorSourceDoor = nil
            interiorMutationSequence = 0
            let replaced = composition.setCell(transition.scene, at: coordinate)
            core.seedResident(coordinate)
            if let previousInterior {
                emitCellDetached(previousInterior)
                evictUnused(previousInterior.assets)
            }
            // `replaced` is the same cell rebuilt at the same coordinate, so
            // the attach below reconciles it; detaching first would retire
            // instances the attach immediately recreates.
            if let replaced {
                evictUnused(replaced.assets)
            }
            emitCellAttached(transition.scene, firstIntegration: !isRebuild)
            sink(viewScene(), camera)
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
