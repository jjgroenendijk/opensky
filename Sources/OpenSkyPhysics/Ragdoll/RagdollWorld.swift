// The registry of live ragdolls, shaped like `DynamicBodyWorld`: sorted by
// `ReferenceKey`, stepped on `PhysicsStep.fixedTimeStep`, with a settled-pose
// drain and cell-scoped lifecycle. Each ragdoll runs its own joint solver.
// Ragdolls do not collide with each other (docs/engine/ragdoll-solver.md).
// See docs/engine/ragdoll.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// Counts one refresh of the ragdoll panel shows.
nonisolated public struct RagdollStatsSnapshot: Equatable, Sendable {
    public var ragdollCount = 0
    public var activeRagdollCount = 0
    public var settledRagdollCount = 0
    /// Bone bodies across every live ragdoll.
    public var boneBodyCount = 0
    /// Joints across every live ragdoll.
    public var jointCount = 0
    /// Joint limits still violated after the last solve, summed over every
    /// ragdoll. Zero once they have all converged.
    public var jointViolationCount = 0
    /// Constraint solver iterations one substep runs, which is a constant the
    /// panel shows beside the violation count so the two read together.
    public var solverIterationCount: Int = RagdollConstraintSolver.iterationCount
    /// Bodies whose integrated pose came back non-finite. Always zero; a
    /// non-zero value is the stability gate failing in the open.
    public var recoveredBodyCount = 0
    /// Bone pairs the biped filter admits, summed over every live ragdoll.
    public var selfCollisionPairCount = 0
    /// Bone-against-bone contacts at the last solve, summed the same way. Zero
    /// on a vanilla humanoid standing at its bind pose, and non-zero once a limb
    /// has fallen across the torso.
    public var selfContactCount = 0
    public var isSelfCollisionEnabled = true
    public var isFrozen = false

    public init(
        ragdollCount: Int = 0,
        activeRagdollCount: Int = 0,
        settledRagdollCount: Int = 0,
        boneBodyCount: Int = 0,
        jointCount: Int = 0,
        jointViolationCount: Int = 0,
        solverIterationCount: Int = RagdollConstraintSolver.iterationCount,
        recoveredBodyCount: Int = 0,
        selfCollisionPairCount: Int = 0,
        selfContactCount: Int = 0,
        isSelfCollisionEnabled: Bool = true,
        isFrozen: Bool = false
    ) {
        self.ragdollCount = ragdollCount
        self.activeRagdollCount = activeRagdollCount
        self.settledRagdollCount = settledRagdollCount
        self.boneBodyCount = boneBodyCount
        self.jointCount = jointCount
        self.jointViolationCount = jointViolationCount
        self.solverIterationCount = solverIterationCount
        self.recoveredBodyCount = recoveredBodyCount
        self.selfCollisionPairCount = selfCollisionPairCount
        self.selfContactCount = selfContactCount
        self.isSelfCollisionEnabled = isSelfCollisionEnabled
        self.isFrozen = isFrozen
    }
}

/// The panel seam for the ragdoll controls under `World > Combat & Physics`.
@MainActor
public protocol RagdollControlProviding: AnyObject {
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
    /// Switches self-collision between a ragdoll's own bones on and off, waking
    /// every corpse so the change is visible on the ones already lying down.
    func setRagdollSelfCollision(_ enabled: Bool)
    /// Drops every live ragdoll. The corpses stay dead; they stop simulating and
    /// fall back to their recorded resting pose.
    func clearRagdolls()
}

nonisolated public struct RagdollWorld: Sendable {
    /// Ragdolls in ascending `ReferenceKey` order.
    public private(set) var ragdolls: [(key: ReferenceKey, instance: RagdollInstance)] = []
    /// Which cell each ragdoll's actor belongs to, so streaming can drop a
    /// cell's corpses wholesale.
    private var cells: [ReferenceKey: CellSceneLocation] = [:]
    /// Resting transforms observed since the last drain.
    private var settled: [ReferenceKey: PlacedReference.Placement] = [:]
    /// Which ragdolls had already settled at the last step, so a corpse is
    /// recorded the step it comes to rest rather than on every step after.
    private var wasSettled: Set<ReferenceKey> = []
    /// Keys in the order they were added, oldest first. `ragdolls` is sorted by key,
    /// so `trim(to:)` needs this separate age order.
    private var spawnOrder: [ReferenceKey] = []
    private var accumulatedTime: Float = 0
    public var isFrozen = false
    /// Whether a ragdoll's bones may touch each other at all: one switch over every
    /// definition's pairs.
    public var isSelfCollisionEnabled = true {
        didSet {
            guard isSelfCollisionEnabled != oldValue else { return }
            for index in ragdolls.indices {
                ragdolls[index].instance.isSelfCollisionEnabled = isSelfCollisionEnabled
                // A corpse that has already settled would otherwise keep the
                // pose it settled into under the old rule, which reads as the
                // switch having done nothing.
                ragdolls[index].instance.wake()
            }
        }
    }

    public var ragdollCount: Int {
        ragdolls.count
    }

    public var statsSnapshot: RagdollStatsSnapshot {
        var snapshot = RagdollStatsSnapshot(
            isSelfCollisionEnabled: isSelfCollisionEnabled, isFrozen: isFrozen
        )
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
            snapshot.selfCollisionPairCount += entry.instance.definition.selfCollision.pairCount
            snapshot.selfContactCount += entry.instance.lastStats.pairContactCount
        }
        return snapshot
    }

    // MARK: - Lifecycle

    /// Registers one ragdoll, replacing any the same actor already had.
    public mutating func add(
        _ instance: RagdollInstance,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    ) {
        var instance = instance
        instance.isSelfCollisionEnabled = isSelfCollisionEnabled
        ragdolls.removeAll { $0.key == key }
        ragdolls.append((key: key, instance: instance))
        ragdolls.sort { $0.key < $1.key }
        cells[key] = cell
        wasSettled.remove(key)
        spawnOrder.removeAll { $0 == key }
        spawnOrder.append(key)
    }

    public mutating func remove(_ key: ReferenceKey) {
        ragdolls.removeAll { $0.key == key }
        cells.removeValue(forKey: key)
        wasSettled.remove(key)
        spawnOrder.removeAll { $0 == key }
    }

    /// Stops simulating the oldest corpses until at most `limit` remain. A trimmed
    /// corpse falls back to its recorded `ActorDeathState` rest transform.
    /// - Returns: how many stopped simulating.
    @discardableResult
    public mutating func trim(to limit: Int) -> Int {
        let excess = ragdolls.count - max(0, limit)
        guard excess > 0 else { return 0 }
        for key in Array(spawnOrder.prefix(excess)) {
            remove(key)
        }
        return excess
    }

    /// Drops every ragdoll whose cell is not in `resident`, as a cell that leaves
    /// residency drops its dynamic bodies.
    /// - Returns: how many were dropped.
    @discardableResult
    public mutating func retainCells(_ resident: Set<CellSceneLocation>) -> Int {
        let departing = cells.filter { !resident.contains($0.value) }.map(\.key)
        for key in departing {
            remove(key)
        }
        return departing.count
    }

    public mutating func removeAll() {
        ragdolls.removeAll()
        cells.removeAll()
        wasSettled.removeAll()
        spawnOrder.removeAll()
        settled.removeAll()
        accumulatedTime = 0
    }

    public func instance(for key: ReferenceKey) -> RagdollInstance? {
        ragdolls.first { $0.key == key }?.instance
    }

    public func isRagdolling(_ key: ReferenceKey) -> Bool {
        ragdolls.contains { $0.key == key }
    }

    // MARK: - Stepping

    /// Advances every ragdoll by one frame's worth of time, in whole fixed steps
    /// of `PhysicsStep.fixedTimeStep`. Leftover time carries forward and an
    /// over-long frame contributes only `PhysicsStep.maximumFrameTime`,
    /// exactly as the dynamic body registry's clock does.
    public mutating func advance(by frameTime: Float, world: DynamicStepWorld) {
        guard !isFrozen, !ragdolls.isEmpty else { return }
        accumulatedTime += min(max(frameTime, 0), PhysicsStep.maximumFrameTime)
        while accumulatedTime + Float.ulpOfOne >= PhysicsStep.fixedTimeStep {
            for index in ragdolls.indices {
                ragdolls[index].instance.step(
                    world: world, dt: PhysicsStep.fixedTimeStep
                )
            }
            accumulatedTime -= PhysicsStep.fixedTimeStep
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
            settled[entry.key] = PlacedReference.Placement(
                position: position,
                rotation: MatrixMath.eulerAngles(of: orientation)
            )
        }
    }

    /// Hands over the resting transforms recorded since the last call, in key
    /// order, so the caller can write them into `ActorDeathState`.
    public mutating func drainSettledTransforms() -> [(
        key: ReferenceKey,
        placement: PlacedReference.Placement
    )] {
        let drained = settled.sorted { $0.key < $1.key }
            .map { (key: $0.key, placement: $0.value) }
        settled.removeAll()
        return drained
    }

    // MARK: - Queries

    public init() {}
}
