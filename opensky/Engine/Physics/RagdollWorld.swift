// The registry of live ragdolls (issue #197, roadmap item 15.6): which corpses
// are simulating right now, the fixed-step clock they advance on, and the
// resting transforms they hand to persistence.
//
// It is deliberately the same shape as `DynamicBodyWorld`, because it has the
// same job for a different kind of body: a keyed collection in sorted order, a
// fixed-step accumulator on `WalkController.fixedTimeStep`, a settled-pose drain
// for the world-state store, and a cell-scoped lifecycle so streaming a cell out
// takes its corpses with it. A reader who has understood one has understood the
// other.
//
// The one structural difference is that a ragdoll is not one body but a body
// *list with joints*, so each entry steps its own solver over its own bodies
// rather than every body sharing one. Ragdolls do not collide with each other:
// two corpses in a pile is a case the joint solver would have to arbitrate
// between two constraint sets at once, and the honest version of that is more
// than this item takes on. Each ragdoll collides with the static world and with
// itself, and the limitation is stated in docs/engine/ragdoll.md rather than
// hidden.
//
// Ordering is by `ReferenceKey` throughout, for the reason the dynamic body
// registry sorts: the solver's iteration order, and therefore the trajectories,
// must not depend on hashing.
//
// Documented in docs/engine/ragdoll.md.

import simd

/// Counts one refresh of the ragdoll panel shows.
nonisolated struct RagdollStatsSnapshot: Equatable, Sendable {
    var ragdollCount = 0
    var activeRagdollCount = 0
    var settledRagdollCount = 0
    /// Bone bodies across every live ragdoll.
    var boneBodyCount = 0
    /// Joints across every live ragdoll.
    var jointCount = 0
    /// Joint limits still violated after the last solve, summed over every
    /// ragdoll. Zero once they have all converged.
    var jointViolationCount = 0
    /// Constraint solver iterations one substep runs, which is a constant the
    /// panel shows beside the violation count so the two read together.
    var solverIterationCount = RagdollConstraintSolver.iterationCount
    /// Bodies whose integrated pose came back non-finite. Always zero; a
    /// non-zero value is the stability gate failing in the open.
    var recoveredBodyCount = 0
    var isFrozen = false
}

/// The panel seam for the ragdoll controls under `World > Combat & Physics`
/// (issue #197 scope point 7).
@MainActor
protocol RagdollControlProviding: AnyObject {
    var ragdollStatsSnapshot: RagdollStatsSnapshot { get }
    /// Kills the selected actor and hands its skeleton to the physics, which is
    /// the dev trigger the item's acceptance drives.
    ///
    /// - Returns: false when there is no selected actor, or when its skeleton
    ///   carries no ragdoll to spawn.
    @discardableResult
    func triggerRagdoll() -> Bool
    /// Suspends and resumes ragdoll stepping without discarding the corpses.
    func setRagdollFrozen(_ frozen: Bool)
    /// Drops every live ragdoll. The corpses stay dead; they stop simulating and
    /// fall back to their recorded resting pose.
    func clearRagdolls()
}

nonisolated struct RagdollWorld {
    /// Ragdolls in ascending `ReferenceKey` order.
    private(set) var ragdolls: [(key: ReferenceKey, instance: RagdollInstance)] = []
    /// Which cell each ragdoll's actor belongs to, so streaming can drop a
    /// cell's corpses wholesale.
    private var cells: [ReferenceKey: CellSceneLocation] = [:]
    /// Resting transforms observed since the last drain.
    private var settled: [ReferenceKey: ReferenceTransformOverride] = [:]
    /// Which ragdolls had already settled at the last step, so a corpse is
    /// recorded the step it comes to rest rather than on every step after.
    private var wasSettled: Set<ReferenceKey> = []
    /// Keys in the order they were added, oldest first. `ragdolls` itself is
    /// sorted by `ReferenceKey` so the solver's iteration order cannot depend
    /// on hashing, which means the array carries no notion of age; the cap in
    /// `trim(to:)` needs one, so it is tracked here rather than by re-sorting
    /// the thing whose order is load-bearing (issue #374).
    private var spawnOrder: [ReferenceKey] = []
    private var accumulatedTime: Float = 0
    var isFrozen = false

    var ragdollCount: Int {
        ragdolls.count
    }

    var statsSnapshot: RagdollStatsSnapshot {
        var snapshot = RagdollStatsSnapshot(isFrozen: isFrozen)
        snapshot.ragdollCount = ragdolls.count
        for entry in ragdolls {
            if entry.instance.isSettled {
                snapshot.settledRagdollCount += 1
            } else {
                snapshot.activeRagdollCount += 1
            }
            snapshot.boneBodyCount += entry.instance.bodies.count
            snapshot.jointCount += entry.instance.definition.jointCount
            snapshot.jointViolationCount += entry.instance.lastStats.jointViolationCount
            snapshot.recoveredBodyCount += entry.instance.lastStats.recoveredBodyCount
        }
        return snapshot
    }

    // MARK: - Lifecycle

    /// Registers one ragdoll, replacing any the same actor already had.
    mutating func add(
        _ instance: RagdollInstance,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    ) {
        ragdolls.removeAll { $0.key == key }
        ragdolls.append((key: key, instance: instance))
        ragdolls.sort { $0.key < $1.key }
        cells[key] = cell
        wasSettled.remove(key)
        spawnOrder.removeAll { $0 == key }
        spawnOrder.append(key)
    }

    mutating func remove(_ key: ReferenceKey) {
        ragdolls.removeAll { $0.key == key }
        cells.removeValue(forKey: key)
        wasSettled.remove(key)
        spawnOrder.removeAll { $0 == key }
    }

    /// Stops simulating the oldest corpses until at most `limit` remain
    /// (issue #374).
    ///
    /// A trimmed corpse is not deleted and is not resurrected: it stops being
    /// stepped and falls back to the resting transform `ActorDeathState`
    /// recorded, which is exactly what happens to a corpse whose cell unloads.
    /// The body a player is looking at therefore stays on the floor; what it
    /// loses is the last of its motion.
    ///
    /// - Returns: how many stopped simulating.
    @discardableResult
    mutating func trim(to limit: Int) -> Int {
        let excess = ragdolls.count - max(0, limit)
        guard excess > 0 else { return 0 }
        for key in Array(spawnOrder.prefix(excess)) {
            remove(key)
        }
        return excess
    }

    /// Drops every ragdoll a cell owns. Called when the cell leaves residency.
    mutating func removeCell(_ location: CellSceneLocation) {
        let departing = cells.filter { $0.value == location }.map(\.key)
        for key in departing {
            remove(key)
        }
    }

    mutating func removeAll() {
        ragdolls.removeAll()
        cells.removeAll()
        wasSettled.removeAll()
        spawnOrder.removeAll()
        settled.removeAll()
        accumulatedTime = 0
    }

    func instance(for key: ReferenceKey) -> RagdollInstance? {
        ragdolls.first { $0.key == key }?.instance
    }

    func isRagdolling(_ key: ReferenceKey) -> Bool {
        ragdolls.contains { $0.key == key }
    }

    // MARK: - Stepping

    /// Advances every ragdoll by one frame's worth of time, in whole fixed steps
    /// of `WalkController.fixedTimeStep`. Leftover time carries forward and an
    /// over-long frame contributes only `WalkController.maximumFrameTime`,
    /// exactly as the dynamic body registry's clock does.
    mutating func advance(by frameTime: Float, world: DynamicStepWorld) {
        guard !isFrozen, !ragdolls.isEmpty else { return }
        accumulatedTime += min(max(frameTime, 0), WalkController.maximumFrameTime)
        while accumulatedTime + Float.ulpOfOne >= WalkController.fixedTimeStep {
            for index in ragdolls.indices {
                ragdolls[index].instance.step(
                    world: world, dt: WalkController.fixedTimeStep
                )
            }
            accumulatedTime -= WalkController.fixedTimeStep
        }
        recordSettled()
    }

    /// Records the resting root transform of every ragdoll that came to rest
    /// since the last step, and forgets the ones that woke back up.
    private mutating func recordSettled() {
        for entry in ragdolls {
            guard entry.instance.isSettled else {
                wasSettled.remove(entry.key)
                continue
            }
            guard wasSettled.insert(entry.key).inserted else { continue }
            guard
                let position = entry.instance.restingRootPosition,
                let orientation = entry.instance.restingRootOrientation
            else { continue }
            settled[entry.key] = ReferenceTransformOverride(
                position: position,
                rotation: MatrixMath.eulerAngles(of: orientation)
            )
        }
    }

    /// Hands over the resting transforms recorded since the last call, in key
    /// order, so the caller can write them into `ActorDeathState`.
    mutating func drainSettledTransforms() -> [(
        key: ReferenceKey,
        transform: ReferenceTransformOverride
    )] {
        let drained = settled.sorted { $0.key < $1.key }
            .map { (key: $0.key, transform: $0.value) }
        settled.removeAll()
        return drained
    }

    // MARK: - Queries

    /// The pose one ragdoll writes into the skinning path this frame, or nil
    /// when that actor is not ragdolling.
    func boneMatrices(
        for key: ReferenceKey,
        blending animated: [String: float4x4],
        worldToActor: float4x4
    ) -> [String: float4x4]? {
        guard let instance = instance(for: key) else { return nil }
        return instance.blendedBoneMatrices(animated: animated, worldToActor: worldToActor)
    }

    /// Applies an impulse to one ragdoll, waking it.
    mutating func applyImpulse(
        _ impulse: SIMD3<Float>,
        at point: SIMD3<Float>,
        to key: ReferenceKey
    ) {
        guard let index = ragdolls.firstIndex(where: { $0.key == key }) else { return }
        ragdolls[index].instance.applyImpulse(impulse, at: point)
    }
}
