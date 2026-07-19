// Door proximity interaction + async interior/exterior scene swaps. Split
// from CellStreamer so exterior grid scheduling stays readable.

import OSLog
import simd

extension CellStreamer {
    /// Returns true only when a successful transition replaced current view.
    func finishDoorTransition(_ entries: [DoorTransitionBuildResult]) -> Bool {
        guard let entry = entries.last else { return false }
        transitionInFlight = nil
        // A cell build ahead of transition on serial queue may complete in
        // same poll. Fold it into suspended exterior state first.
        _ = integrateOneBuild()
        switch entry.result {
        case let .success(transition):
            apply(transition: transition)
            return true
        case let .failure(error):
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
        cameraPosition: SIMD3<Float>,
        activate: Bool,
        completedLOD: [DistantLODBuildResult]
    ) -> Bool {
        guard let interiorScene else { return false }
        for entry in completedLOD {
            if case let .success(scene) = entry.result, let scene {
                evictUnused(scene.assets)
            }
        }
        if activate {
            requestDoorTransition(nearestDoor(in: interiorScene, to: cameraPosition))
        }
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

    func requestDoorTransition(_ door: PlacedDoor?) {
        guard transitionInFlight == nil, let door else { return }
        transitionInFlight = door.reference
        runner.enqueueDoorTransition(from: door.reference)
    }

    func apply(transition: DoorTransition) {
        let camera = SceneCamera.teleport(placement: transition.destinationPlacement)
        switch transition.scene.location {
        case .interior:
            let previous = interiorScene
            interiorScene = transition.scene
            if let previous {
                evictUnused(previous.assets)
            }
            sink(transition.scene.renderScene, camera)
        case let .exterior(coordinate):
            let previousInterior = interiorScene
            interiorScene = nil
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
    }
}
