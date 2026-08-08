// Dynamic rigid bodies inside the streaming controller (issue #193, roadmap
// item 15.2). Split from CellStreamer for the file cap, like the trigger and
// ambience satellites.
//
// The registry follows residency rather than being pushed at from the build
// path: once per frame the resident cells are compared against what the body
// world already holds, a cell whose scene is new or has been rebuilt hands over
// its placements, and a cell that is gone has its bodies dropped. Doing it as a
// reconciliation rather than as a pair of load/unload callbacks means a
// coverage transition, a door transition, and a world-state rebuild all get the
// right answer without any of them knowing physics exists.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

extension CellStreamer {
    /// One frame of dynamic simulation: reconcile residency, shove whatever the
    /// player walked into, step the solver, then hand any newly-settled resting
    /// transform to the world state.
    func advancePhysics(frameTime: Float, player: PlayerCapsuleState?) {
        reconcileDynamicBodies()
        pushDynamicBodies(player: player, frameTime: frameTime)
        dynamicBodies.advance(
            by: frameTime,
            world: DynamicStepWorld(staticCandidates: { [weak self] bounds in
                self?.staticCollisionCandidates(overlapping: bounds) ?? []
            })
        )
        dynamicBodies.retainBodies(occupying: Set(residentDynamicBodyScenes().keys))
        for settled in dynamicBodies.drainSettledTransforms() {
            onBodySettled?(settled.key, settled.transform, settled.placingCell)
        }
        if composition.setDynamicDrawOwnership(dynamicBodies.exteriorDrawOwnership) {
            // Draw ownership changes only at a cell boundary. Recompose once
            // there so the occupied cell can outlive the placing cell without
            // rebuilding either cell's baked scene.
            sink(composition.composedScene(), nil)
        }
        // Published every tick rather than only when something moved: a body
        // that has settled away from where its cell drew it keeps a delta until
        // the rebuild bakes it in, so "no movement this frame" is not "no
        // displacement to draw".
        onDynamicPosesChanged?(dynamicBodies.instanceDeltas)
    }

    /// Adds the bodies of every newly resident or rebuilt cell and drops the
    /// bodies of every cell that left.
    func reconcileDynamicBodies() {
        let resident = residentDynamicBodyScenes()
        dynamicBodies.retainBodies(occupying: Set(resident.keys))
        for location in dynamicBodies.installedCells.keys where resident[location] == nil {
            dynamicBodies.removeCell(location)
        }
        // Cells are visited in a stable order so that two runs of the same
        // session install bodies in the same order, which the solver's
        // determinism rests on.
        for location in resident.keys.sorted(by: CellSceneLocation.isOrderedBefore) {
            guard let scene = resident[location] else { continue }
            guard dynamicBodies.installedCells[location] != scene.stateSequence else { continue }
            dynamicBodies.setCell(
                location, placements: scene.dynamicBodies, sequence: scene.stateSequence
            )
        }
    }

    private func residentDynamicBodyScenes() -> [CellSceneLocation: CellScene] {
        var resident: [CellSceneLocation: CellScene] = [:]
        if let interiorScene, let location = interiorScene.location {
            resident[location] = interiorScene
        } else {
            for scene in composition.cells.values {
                guard let location = scene.location else { continue }
                resident[location] = scene
            }
        }
        return resident
    }

    /// The player's shove, from how far the capsule moved since the last frame.
    /// Deriving the velocity here rather than plumbing one down keeps the
    /// capsule's own signature unchanged, and a teleport — a door transition or
    /// a reseed — is discarded rather than delivered as an enormous impulse.
    private func pushDynamicBodies(player: PlayerCapsuleState?, frameTime: Float) {
        guard let player, frameTime > 0 else {
            dynamicBodies.lastPushFeetPosition = player?.feetPosition
            return
        }
        defer { dynamicBodies.lastPushFeetPosition = player.feetPosition }
        guard let previous = dynamicBodies.lastPushFeetPosition else { return }
        let velocity = (player.feetPosition - previous) / frameTime
        guard simd_length(velocity) <= Self.maximumPushSpeed else { return }
        dynamicBodies.push(
            capsule: player.capsule,
            feetPosition: player.feetPosition,
            velocity: velocity
        )
    }

    /// Faster than this and the capsule was teleported, not walked, so the
    /// frame contributes no shove. Engine units per second; a sprint is a few
    /// hundred.
    static let maximumPushSpeed: Float = 3000
}

nonisolated extension CellSceneLocation {
    /// A total order over cell identities, so a dictionary of resident cells
    /// can be visited reproducibly. Exteriors sort by grid coordinate and come
    /// before every interior, which sorts by CELL FormID.
    static func isOrderedBefore(_ lhs: CellSceneLocation, _ rhs: CellSceneLocation) -> Bool {
        switch (lhs, rhs) {
        case let (.exterior(left), .exterior(right)):
            (left.x, left.y) < (right.x, right.y)
        case let (.interior(left), .interior(right)):
            left.rawValue < right.rawValue
        case (.exterior, .interior):
            true
        case (.interior, .exterior):
            false
        }
    }
}
