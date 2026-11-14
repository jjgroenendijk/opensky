// Selected-door transition dispatch + async interior/exterior scene swaps. Split
// from CellStreamer so exterior grid scheduling stays readable.

import Foundation
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
public import OpenSkyWorldInterface
import simd

extension CellStreamer.TransitionSteps {
    /// Returns true only when a successful transition replaced current view.
    /// The finished door builds, held until `fTeleportDoorActivateDelayTimer` has passed
    /// since the player used the door. A rebuild does not wait.
    func drainDoorTransitions(frameTime: Float) -> [DoorTransitionBuildResult] {
        streamer.doorState.heldDoorTransitions += streamer.runner.drainCompletedDoorTransitions()
        if frameTime.isFinite, frameTime > 0 {
            streamer.doorState.doorTransitionHold = max(
                0,
                streamer.doorState.doorTransitionHold - frameTime
            )
        }
        guard streamer.doorState.doorTransitionHold <= 0 || streamer.interiorRebuildInFlight
        else { return [] }
        defer { streamer.doorState.heldDoorTransitions = [] }
        return streamer.doorState.heldDoorTransitions
    }

    public func finishDoorTransition(_ entries: [DoorTransitionBuildResult]) -> Bool {
        guard let entry = entries.last else { return false }
        streamer.transitionInFlight = nil
        streamer.doorState.automaticDoorOccupancy = nil
        let motionInteraction = streamer.doorState.doorMotionInteraction
        streamer.doorState.doorMotionInteraction = nil
        let isRebuild = streamer.interiorRebuildInFlight
        streamer.interiorRebuildInFlight = false
        // A cell build ahead of transition on serial queue may complete in
        // same poll. Fold it into suspended exterior state first.
        _ = streamer.builds.integrateOneBuild()
        switch entry.result {
        case let .success(transition):
            emitDoorMotion(.closed, interaction: motionInteraction)
            apply(transition: transition, sourceDoor: entry.sourceDoor, isRebuild: isRebuild)
            if !isRebuild {
                streamer.events.onDoorTransitionFinished?(transition.scene)
            }
            return true
        case let .failure(error):
            emitDoorMotion(.cancelled, interaction: motionInteraction)
            streamer.noteDoorTransitionFailure()
            if !isRebuild {
                streamer.events.onDoorTransitionFinished?(nil)
            }
            let reason = String(describing: error)
            CellStreamer.logger.warning(
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
        guard streamer.interiorScene != nil else { return false }
        if streamer.props.integrateActorProps() {
            streamer.sink(streamer.props.viewScene(), nil)
        }
        streamer.coverage.discardDistantLOD(completedLOD)
        streamer.runtimeStates.dispatchInteriorRebuildIfNeeded()
        return true
    }

    public func nearestDoor(in scene: CellScene, to position: SIMD3<Float>) -> PlacedDoor? {
        scene.doors
            .filter { simd_distance($0.position, position) <= CellStreamer.doorActivationRadius }
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
        guard streamer.transitionInFlight == nil else { return false }
        streamer.transitionInFlight = sourceDoor
        streamer.doorState.doorTransitionHold = 0
        streamer.interiorRebuildInFlight = false
        // Built against the live store, so a changed interior comes back changed.
        streamer.runner.enqueueDoorTransition(from: sourceDoor, state: streamer.stateSource())
        streamer.events.onDoorTransitionStarted?()
        return true
    }

    /// Drops the interior and shows the resident exterior again at `camera`,
    /// for a teleport out that uses no door. The grid then follows the camera.
    public func leaveInterior(camera: SceneCamera) {
        guard let previous = streamer.interiorScene else { return }
        streamer.hasSeededCamera = true
        streamer.interiorScene = nil
        streamer.doorState.interiorSourceDoor = nil
        streamer.interiorMutationSequence = 0
        streamer.residents.updateInteractionTarget(ray: nil)
        streamer.triggers.emitCellDetached(previous)
        streamer.coverage.evictUnused(previous.assets)
        streamer.sink(streamer.props.viewScene(), camera)
        streamer.ambience.invalidateAmbienceContext()
        streamer.ambience.invalidateMusicContext()
    }

    private func emitDoorMotion(
        _ phase: InteractionAnimationPhase,
        interaction: PlacedInteraction?
    ) {
        guard let interaction else { return }
        streamer.events.onInteractionAnimation?(InteractionAnimationEvent(
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
        streamer.residents.updateInteractionTarget(ray: nil)
        let camera = isRebuild
            ? nil
            : SceneCamera.teleport(placement: transition.destinationPlacement)
        streamer.hasSeededCamera = streamer.hasSeededCamera || camera != nil
        switch transition.scene.location {
        case .interior:
            let previous = streamer.interiorScene
            streamer.interiorScene = transition.scene
            streamer.doorState.interiorSourceDoor = sourceDoor ?? streamer.doorState
                .interiorSourceDoor
            // A rebuild re-enters the same interior, so its scripts stay
            // attached; only a player-driven move retires the old cell.
            if let previous {
                if !isRebuild {
                    streamer.triggers.emitCellDetached(previous)
                }
                streamer.coverage.evictUnused(previous.assets)
            }
            streamer.triggers.emitCellAttached(transition.scene, firstIntegration: !isRebuild)
            streamer.sink(streamer.props.viewScene(), camera)
        case let .exterior(coordinate):
            let previousInterior = streamer.interiorScene
            streamer.interiorScene = nil
            streamer.doorState.interiorSourceDoor = nil
            streamer.interiorMutationSequence = 0
            // The runner already builds in the destination worldspace.
            if
                let worldspace = transition.worldspaceEditorID,
                worldspace != streamer.worldspaceEditorID
            {
                streamer.switchExterior(
                    to: worldspace, at: transition.destinationPlacement.position
                )
            }
            let replaced = streamer.composition.setCell(transition.scene, at: coordinate)
            streamer.core.seedResident(coordinate)
            if let previousInterior {
                streamer.triggers.emitCellDetached(previousInterior)
                streamer.coverage.evictUnused(previousInterior.assets)
            }
            // `replaced` is the same cell rebuilt at the same coordinate, so
            // the attach below reconciles it; detaching first would retire
            // instances the attach immediately recreates.
            if let replaced {
                streamer.coverage.evictUnused(replaced.assets)
            }
            streamer.triggers.emitCellAttached(transition.scene, firstIntegration: !isRebuild)
            streamer.sink(streamer.props.viewScene(), camera)
        case nil:
            CellStreamer.logger.warning("[WARNING] door destination scene has no CELL identity")
        }
        // A scene swap changes the ambience context even when the key matches
        // (e.g. re-entering the same interior); force a re-emit next tick.
        streamer.ambience.invalidateAmbienceContext()
        streamer.ambience.emitAmbienceContextIfNeeded()
        streamer.ambience.invalidateMusicContext()
        streamer.ambience.emitMusicContextIfNeeded()
    }
}
