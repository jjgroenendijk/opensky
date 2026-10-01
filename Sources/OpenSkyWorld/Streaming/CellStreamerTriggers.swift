// Trigger-volume occupancy and edge events, diffed against the last frame. Once per
// rendered frame, not per physics substep, and in walk mode only: fly mode has no body.

import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// The authoritative player capsule pose for one frame.
///
/// The streamer is driven with the *eye* position, and feet are eye minus
/// `PlayerCapsule.eyeHeight` only while walking, so the value is passed in
/// from `WalkController` rather than derived inside the streamer. Nil at the
/// call site means "not in walk mode, do not test".
nonisolated public struct PlayerCapsuleState: Equatable, Sendable {
    public let capsule: PlayerCapsule
    /// Capsule bottom in world space, as advanced by `WalkController`.
    public let feetPosition: SIMD3<Float>

    public init(capsule: PlayerCapsule = .standard, feetPosition: SIMD3<Float>) {
        self.capsule = capsule
        self.feetPosition = feetPosition
    }
}

extension CellStreamer {
    /// Longest teleport, in capsule radii, that is still sampled for volumes
    /// crossed on the way. Past this the sweep samples evenly at coarser
    /// spacing, so a very long jump stays O(1) rather than O(distance).
    public static let maximumTriggerSweepSamples = 16

    /// Subscribes `triggerLog` to this streamer's own fan-out, from `init`.
    ///
    /// The readout log is an ordinary subscriber, exactly like the Papyrus
    /// bridge, so nothing in `dispatchTriggerEdges` knows a readout exists.
    /// Weak, because the fan-out this streamer owns would otherwise retain it
    /// back.
    public func installTriggerLogging() {
        onTriggerTransition.add { [weak self] event in
            guard let self else { return }
            triggerLog.record(event, formID: referenceEntry(key: event.reference)?.formID)
        }
    }

    /// Trigger volumes the capsule intersects right now, interior-aware in the
    /// same shape as `collisionCandidates(overlapping:)`: an interior scene
    /// replaces the exterior composition entirely, so it answers alone.
    public func triggerVolumes(intersecting state: PlayerCapsuleState) -> [TriggerVolume] {
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
    public func triggerStats() -> TriggerVolumeStats {
        if let interiorScene {
            return interiorScene.triggerVolumes.stats
        }
        return composition.triggerStats()
    }

    /// One frame's occupancy test and diff. A nil state (fly mode) freezes occupancy, so
    /// switching modes inside a volume fakes no leave.
    public func updateTriggerOccupancy(_ state: PlayerCapsuleState?) {
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
    public func releaseTriggers(in scene: CellScene) {
        guard !occupiedTriggers.isEmpty else { return }
        let owned = Set(scene.triggerVolumes.volumes.map(\.reference))
        let released = occupiedTriggers.intersection(owned)
        guard !released.isEmpty else { return }
        occupiedTriggers.subtract(released)
        for key in released.sorted() {
            onTriggerTransition(TriggerTransitionEvent(reference: key, phase: .leave))
        }
    }

    /// Enters, then leaves, each by `ReferenceKey`, like `queueOnActivate`. A volume
    /// crossed within one frame is touched, not occupied, so it emits enter then leave.
    /// Occupancy commits before handlers run.
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

    /// Capsule poses between two frames' feet, about one radius apart, so a teleport
    /// cannot skip a volume. Endpoints excluded. A normal step gives no samples.
    public static func sweepSamples(
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
