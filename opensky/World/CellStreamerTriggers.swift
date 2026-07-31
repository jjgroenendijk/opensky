// Per-frame trigger-volume occupancy and edge events for CellStreamer
// (issue #173). Split from CellStreamer.swift for the same file-size reason as
// CellStreamerAmbience, and shaped like it: the streamer keeps the previous
// answer, diffs against the current one, and emits only the difference.
//
// Rate: once per rendered frame, from the streamer update path — never per
// 120 Hz physics substep. Triggers are gameplay-rate events, the substep loop
// is a hot path, and firing a script event 120 times a second for a player
// standing still would be both wrong and expensive.
//
// Gate: walk mode only, matching the interaction ray. Fly mode is a developer
// camera with no body, so it has no occupancy and emits nothing.

import simd

/// The authoritative player capsule pose for one frame.
///
/// The streamer is driven with the *eye* position, and feet are eye minus
/// `PlayerCapsule.eyeHeight` only while walking, so the value is passed in
/// from `WalkController` rather than derived inside the streamer. Nil at the
/// call site means "not in walk mode, do not test".
nonisolated struct PlayerCapsuleState: Equatable, Sendable {
    let capsule: PlayerCapsule
    /// Capsule bottom in world space, as advanced by `WalkController`.
    let feetPosition: SIMD3<Float>

    init(capsule: PlayerCapsule = .standard, feetPosition: SIMD3<Float>) {
        self.capsule = capsule
        self.feetPosition = feetPosition
    }
}

/// One trigger-occupancy edge. Identity is the authoring REFR's
/// `ReferenceKey`, because that is what a script instance is addressed by.
nonisolated struct TriggerTransitionEvent: Equatable, Sendable {
    nonisolated enum Phase: Equatable, Sendable {
        case enter
        case leave
    }

    let reference: ReferenceKey
    let phase: Phase
}

extension CellStreamer {
    /// Longest teleport, in capsule radii, that is still sampled for volumes
    /// crossed on the way. Past this the sweep samples evenly at coarser
    /// spacing, so a very long jump stays O(1) rather than O(distance).
    static let maximumTriggerSweepSamples = 16

    /// Subscribes `triggerLog` to this streamer's own fan-out, from `init`.
    ///
    /// The readout log is an ordinary subscriber, exactly like the Papyrus
    /// bridge, so nothing in `dispatchTriggerEdges` knows a readout exists.
    /// Weak, because the fan-out this streamer owns would otherwise retain it
    /// back.
    func installTriggerLogging() {
        onTriggerTransition.add { [weak self] event in
            guard let self else { return }
            triggerLog.record(event, formID: referenceEntry(key: event.reference)?.formID)
        }
    }

    /// Trigger volumes the capsule intersects right now, interior-aware in the
    /// same shape as `collisionCandidates(overlapping:)`: an interior scene
    /// replaces the exterior composition entirely, so it answers alone.
    func triggerVolumes(intersecting state: PlayerCapsuleState) -> [TriggerVolume] {
        triggerVolumes(intersecting: state.capsule, at: state.feetPosition)
    }

    private func triggerVolumes(
        intersecting capsule: PlayerCapsule,
        at feetPosition: SIMD3<Float>
    ) -> [TriggerVolume] {
        if let interiorScene {
            return interiorScene.triggerVolumes.volumes(
                intersecting: capsule, at: feetPosition
            )
        }
        return composition.triggerVolumes(intersecting: capsule, at: feetPosition)
    }

    /// Summed trigger accounting over whatever is currently live, for the
    /// inspection surface.
    func triggerStats() -> TriggerVolumeStats {
        if let interiorScene {
            return interiorScene.triggerVolumes.stats
        }
        return composition.triggerStats()
    }

    /// One frame's occupancy test and edge diff.
    ///
    /// A nil state (fly mode, or a frame with no walk controller) tests
    /// nothing and diffs nothing: occupancy is *frozen*, not cleared, so
    /// toggling to fly mode inside a volume does not fabricate a leave the
    /// player never performed. The leave fires on the first walk-mode frame
    /// that finds the capsule outside.
    func updateTriggerOccupancy(_ state: PlayerCapsuleState?) {
        guard let state else {
            lastTriggerFeetPosition = nil
            return
        }
        let previous = lastTriggerFeetPosition ?? state.feetPosition
        lastTriggerFeetPosition = state.feetPosition
        let occupied = references(of: triggerVolumes(intersecting: state))
        var touched = occupied
        for sample in Self.sweepSamples(
            from: previous, to: state.feetPosition, radius: state.capsule.radius
        ) {
            touched.formUnion(references(of: triggerVolumes(
                intersecting: state.capsule, at: sample
            )))
        }
        dispatchTriggerEdges(occupied: occupied, touched: touched)
    }

    /// Fires `leave` for every occupied volume this scene authored, before the
    /// scene's script instances are retired.
    ///
    /// Called from `emitCellDetached(_:)`, which is the single funnel every
    /// unload path goes through — grid eviction, a coverage-transition drop,
    /// and a door transition replacing the previous scene.
    func releaseTriggers(in scene: CellScene) {
        guard !occupiedTriggers.isEmpty else { return }
        let owned = Set(scene.triggerVolumes.volumes.map(\.reference))
        let released = occupiedTriggers.intersection(owned)
        guard !released.isEmpty else { return }
        occupiedTriggers.subtract(released)
        for key in released.sorted() {
            onTriggerTransition(TriggerTransitionEvent(reference: key, phase: .leave))
        }
    }

    /// Enters first, then leaves, both in ascending `ReferenceKey` order so
    /// dispatch is deterministic — the same ordering rule `queueOnActivate`
    /// follows. A volume visited and left inside one frame appears in
    /// `touched` but not in `occupied`, which is what makes a teleport across
    /// a volume emit enter followed by leave instead of nothing at all.
    ///
    /// Occupancy is committed before any handler runs, so a script that moves
    /// the player from inside its own handler sees a consistent set.
    private func dispatchTriggerEdges(
        occupied: Set<ReferenceKey>,
        touched: Set<ReferenceKey>
    ) {
        let entered = touched.subtracting(occupiedTriggers)
        let left = occupiedTriggers.union(touched).subtracting(occupied)
        occupiedTriggers = occupied
        for key in entered.sorted() {
            onTriggerTransition(TriggerTransitionEvent(reference: key, phase: .enter))
        }
        for key in left.sorted() {
            onTriggerTransition(TriggerTransitionEvent(reference: key, phase: .leave))
        }
    }

    private func references(of volumes: [TriggerVolume]) -> Set<ReferenceKey> {
        Set(volumes.map(\.reference))
    }

    /// Intermediate capsule poses between two frames' feet positions, spaced
    /// about one capsule radius apart so a volume at least that thick cannot
    /// be stepped over. Both endpoints are excluded: the destination is
    /// sampled as the frame's occupancy, and the origin was last frame's.
    ///
    /// A normal walking frame moves far less than a radius and produces no
    /// samples at all, so this costs nothing until something teleports.
    static func sweepSamples(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>,
        radius: Float
    ) -> [SIMD3<Float>] {
        let delta = destination - origin
        let distance = simd_length(delta)
        let spacing = max(radius, 1)
        guard distance.isFinite, distance > spacing else { return [] }
        let wanted = Int((distance / spacing).rounded(.up)) - 1
        let count = min(maximumTriggerSweepSamples, max(wanted, 0))
        guard count > 0 else { return [] }
        return (1 ... count).map {
            origin + delta * (Float($0) / Float(count + 1))
        }
    }
}
