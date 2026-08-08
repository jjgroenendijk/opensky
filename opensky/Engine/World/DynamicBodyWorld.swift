// The runtime registry of simulated rigid bodies (issue #193, roadmap item
// 15.2): which references are dynamic right now, the fixed-step clock they
// advance on, and the lifecycle rules that tie them to cell residency and to
// persisted world state.
//
// A body exists only while the exterior cell it currently occupies is
// resident. Streaming adds bodies from their placing scene, re-bins them as
// they move, and drops them when their occupied cell leaves. What survives is
// the resting
// transform: once a body sleeps, its pose is written to the reference's
// `.transform` component, which is what a save records and what the next build
// of that cell places the object by. A body that is still moving when its cell
// unloads keeps its last written resting pose, not its mid-flight one — a crate
// should not be found in mid-air after a reload.
//
// Ordering is by `ReferenceKey` throughout. The registry keeps its bodies in a
// sorted array rather than a dictionary precisely so that the solver's
// iteration order, and therefore the trajectories, cannot depend on hashing.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

/// A body a cell build produced, before the runtime gives it a pose.
nonisolated struct DynamicBodyPlacement: Sendable {
    let key: ReferenceKey
    let reference: FormID
    let definition: DynamicBodyDefinition
    /// The reference's own origin, from its placement or its transform
    /// override.
    let originPosition: SIMD3<Float>
    let orientation: simd_quatf
}

/// Counts one refresh of the physics panel shows (item 15.9 ships the panel;
/// this is the value it reads).
nonisolated struct DynamicBodyStatsSnapshot: Equatable, Sendable {
    var bodyCount = 0
    var activeBodyCount = 0
    var sleepingBodyCount = 0
    var contactCount = 0
    var substepCount = 0
    var recoveredBodyCount = 0
    /// True while stepping is suspended by the panel's freeze control.
    var isFrozen = false
}

nonisolated struct SettledDynamicBodyTransform: Sendable {
    let key: ReferenceKey
    let transform: ReferenceTransformOverride
    let placingCell: CellSceneLocation
}

/// The panel seam for `World > Combat & Physics` (issue #193 scope point 7).
/// Specified here, consumed by item 15.9 — the same shape as every other panel
/// bridge: one `Equatable` snapshot out, plain actions in.
@MainActor
protocol PhysicsControlProviding: AnyObject {
    var dynamicBodyStatsSnapshot: DynamicBodyStatsSnapshot { get }
    /// Suspends and resumes integration without discarding the bodies, so a
    /// developer can inspect a scene mid-fall.
    func setPhysicsFrozen(_ frozen: Bool)
    /// Returns every body to the pose its cell build placed it at and clears
    /// its velocity. Action-only; it leaves no provider state behind.
    func resetDynamicBodies()
}

nonisolated struct DynamicBodyWorld {
    /// Bodies in ascending `ReferenceKey` order — the solver's iteration order.
    private(set) var bodies: [DynamicBody] = []
    /// Pose each body was placed at, for the panel's reset action.
    private var placedPoses: [ReferenceKey: (position: SIMD3<Float>, orientation: simd_quatf)] = [:]
    /// Resting poses observed since the last drain, for persistence.
    private var settled: [ReferenceKey: ReferenceTransformOverride] = [:]
    /// Sleep state as of the last step, so a body is only recorded the step it
    /// falls asleep rather than on every step it stays asleep.
    private var wasSleeping: Set<ReferenceKey> = []
    private var accumulatedTime: Float = 0
    /// `CellScene.stateSequence` of the scene whose placements are installed,
    /// per cell. A rebuilt cell arrives with a fresh sequence and so hands its
    /// placements over again; an unchanged one is skipped. Kept here rather than
    /// on the streamer because it describes what this registry holds.
    private(set) var installedCells: [CellSceneLocation: UInt64] = [:]
    /// Capsule bottom at the previous shove, for deriving the player's velocity
    /// from how far it walked. Nil before the first walk-mode frame.
    var lastPushFeetPosition: SIMD3<Float>?
    var isFrozen = false
    private(set) var lastStats = DynamicStepStats()

    var bodyCount: Int {
        bodies.count
    }

    var activeBodyCount: Int {
        bodies.count(where: { !$0.isSleeping })
    }

    var sleepingBodyCount: Int {
        bodies.count(where: \.isSleeping)
    }

    var statsSnapshot: DynamicBodyStatsSnapshot {
        DynamicBodyStatsSnapshot(
            bodyCount: bodies.count,
            activeBodyCount: activeBodyCount,
            sleepingBodyCount: sleepingBodyCount,
            contactCount: lastStats.contactCount,
            substepCount: lastStats.substepCount,
            recoveredBodyCount: lastStats.recoveredBodyCount,
            isFrozen: isFrozen
        )
    }

    // MARK: - Lifecycle

    /// Replaces the bodies of one cell, which is what a cell build or rebuild
    /// does. A body already registered under the same key keeps its live pose
    /// and velocity: a rebuild triggered by an unrelated runtime-state write
    /// must not teleport a crate back to where the plugin put it.
    mutating func setCell(
        _ location: CellSceneLocation,
        placements: [DynamicBodyPlacement],
        sequence: UInt64 = 0
    ) {
        installedCells[location] = sequence
        var retained = bodies.filter { $0.placingCell != location }
        for placement in placements {
            // The placed pose is refreshed whether or not the body is new. It
            // is what this build *drew* the reference at, so a rebuild that
            // bakes a settled pose into the scene has to move the reset target
            // and the render delta with it, or the object would be drawn twice
            // displaced by the distance it had already fallen.
            placedPoses[placement.key] = (
                position: placement.originPosition, orientation: placement.orientation
            )
            if let existing = bodies.first(where: { $0.key == placement.key }) {
                retained.append(existing)
                continue
            }
            retained.append(DynamicBody(
                key: placement.key,
                reference: placement.reference,
                cell: location,
                definition: placement.definition,
                originPosition: placement.originPosition,
                orientation: placement.orientation
            ))
        }
        bodies = retained.sorted { $0.key < $1.key }
        rebinExteriorBodies()
    }

    /// Drops every body currently occupying a departing cell. A body that was
    /// placed there but crossed into a resident neighbour keeps simulating.
    mutating func removeCell(_ location: CellSceneLocation) {
        let departing = bodies.filter { $0.occupiedCell == location }
        for body in departing {
            placedPoses.removeValue(forKey: body.key)
            wasSleeping.remove(body.key)
        }
        bodies.removeAll { $0.occupiedCell == location }
        installedCells.removeValue(forKey: location)
    }

    /// Retires bodies that crossed beyond the resident composition. Unlike
    /// `removeCell`, this also covers an occupied cell that was never loaded and
    /// therefore never appears in `installedCells`.
    mutating func retainBodies(occupying resident: Set<CellSceneLocation>) {
        let departing = bodies.filter { !resident.contains($0.occupiedCell) }
        for body in departing {
            placedPoses.removeValue(forKey: body.key)
            wasSleeping.remove(body.key)
        }
        bodies.removeAll { !resident.contains($0.occupiedCell) }
    }

    mutating func removeAll() {
        bodies.removeAll()
        placedPoses.removeAll()
        wasSleeping.removeAll()
        installedCells.removeAll()
        accumulatedTime = 0
    }

    /// Registers one body outside a cell build — the path a dropped inventory
    /// item takes, which has a spawn state but no placed reference yet.
    mutating func add(_ placement: DynamicBodyPlacement, in location: CellSceneLocation) {
        bodies.removeAll { $0.key == placement.key }
        bodies.append(DynamicBody(
            key: placement.key,
            reference: placement.reference,
            cell: location,
            definition: placement.definition,
            originPosition: placement.originPosition,
            orientation: placement.orientation
        ))
        placedPoses[placement.key] = (
            position: placement.originPosition, orientation: placement.orientation
        )
        bodies.sort { $0.key < $1.key }
        rebinExteriorBodies()
    }

    /// Forces bodies to sleep where they stand until at most `limit` are awake
    /// (issue #374).
    ///
    /// The order is ascending `ReferenceKey`, which is this registry's order
    /// everywhere else and is stated rather than described as "oldest": a body
    /// is placed by its cell build and carries no spawn time, so age is not
    /// something the registry knows. What it does guarantee is that two runs
    /// that reach the same over-budget state put the same bodies to sleep.
    ///
    /// A slept body keeps its pose and is persisted by the ordinary settled
    /// drain, so the cap costs motion rather than position — a crate stops
    /// mid-tumble instead of vanishing.
    ///
    /// - Returns: how many were put to sleep.
    @discardableResult
    mutating func sleepExcessBodies(over limit: Int) -> Int {
        let awake = bodies.indices.filter { !bodies[$0].isSleeping }
        let excess = awake.count - max(0, limit)
        guard excess > 0 else { return 0 }
        for index in awake.prefix(excess) {
            bodies[index].isSleeping = true
            bodies[index].linearVelocity = .zero
            bodies[index].angularVelocity = .zero
        }
        return excess
    }

    /// Returns every body to its placed pose, at rest and awake.
    mutating func reset() {
        for index in bodies.indices {
            guard let pose = placedPoses[bodies[index].key] else { continue }
            bodies[index] = DynamicBody(
                key: bodies[index].key,
                reference: bodies[index].reference,
                cell: bodies[index].placingCell,
                definition: bodies[index].definition,
                originPosition: pose.position,
                orientation: pose.orientation
            )
        }
        wasSleeping.removeAll()
        settled.removeAll()
        accumulatedTime = 0
        lastStats = DynamicStepStats()
        rebinExteriorBodies()
    }

    // MARK: - Stepping

    /// Advances the simulation by one frame's worth of time, in whole fixed
    /// steps of `WalkController.fixedTimeStep`. Leftover time carries forward,
    /// and a frame longer than `WalkController.maximumFrameTime` contributes
    /// only that much, exactly as the player capsule's clock does.
    @discardableResult
    mutating func advance(by frameTime: Float, world: DynamicStepWorld) -> DynamicStepStats {
        guard !isFrozen, !bodies.isEmpty else {
            lastStats = DynamicStepStats(
                activeBodyCount: activeBodyCount,
                sleepingBodyCount: sleepingBodyCount
            )
            return lastStats
        }
        accumulatedTime += min(max(frameTime, 0), WalkController.maximumFrameTime)
        var stats = DynamicStepStats()
        while accumulatedTime + Float.ulpOfOne >= WalkController.fixedTimeStep {
            stats = DynamicBodySolver.step(
                bodies: &bodies, world: world, dt: WalkController.fixedTimeStep
            )
            rebinExteriorBodies()
            accumulatedTime -= WalkController.fixedTimeStep
        }
        recordSettled()
        lastStats = stats
        return stats
    }

    /// Updates exterior ownership inside the fixed-step loop. `bodies` is
    /// already in `ReferenceKey` order, so a boundary crossing cannot make
    /// lifecycle or draw ownership depend on dictionary iteration.
    private mutating func rebinExteriorBodies() {
        for index in bodies.indices {
            guard case .exterior = bodies[index].occupiedCell else { continue }
            bodies[index].occupiedCell = .exterior(
                CellGridManager.cellCoordinate(for: bodies[index].originPosition)
            )
        }
    }

    /// Records the resting transform of every body that fell asleep since the
    /// last step, and forgets bodies that woke back up.
    private mutating func recordSettled() {
        for body in bodies {
            guard body.isSleeping else {
                wasSleeping.remove(body.key)
                continue
            }
            guard wasSleeping.insert(body.key).inserted else { continue }
            settled[body.key] = ReferenceTransformOverride(
                position: body.originPosition,
                rotation: MatrixMath.eulerAngles(of: body.orientation)
            )
        }
    }

    /// Hands over the resting transforms recorded since the last call, so the
    /// caller can write them to `WorldStateStore` under the `.transform`
    /// component. Ordered by key, because a journal has to be reproducible.
    mutating func drainSettledTransforms() -> [SettledDynamicBodyTransform] {
        let drained = settled.sorted { $0.key < $1.key }
            .compactMap { key, transform in
                bodies.first(where: { $0.key == key }).map {
                    SettledDynamicBodyTransform(
                        key: key, transform: transform, placingCell: $0.placingCell
                    )
                }
            }
        settled.removeAll()
        return drained
    }

    // MARK: - Queries

    /// Every body's shapes at their current pose, for the collision query the
    /// player capsule and the interaction ray run. Bodies are visited in key
    /// order so the candidate list is stable.
    func placedShapes(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        bodies.filter { $0.worldBounds.overlaps(bounds) }
            .flatMap { $0.placedShapes() }
            .filter { $0.bounds.overlaps(bounds) }
    }

    /// Where every moved body is now, relative to where its cell build drew it,
    /// keyed by the REFR the draw instances carry (issue #193).
    ///
    /// Bodies that have not moved are absent rather than present with an
    /// identity, so a world whose clutter is all standing still hands the
    /// renderer an empty map and costs it nothing. Rebuilt per frame rather
    /// than cached: fifty-odd entries is a few microseconds, and a cache here
    /// would have to be invalidated by every lifecycle path in this type.
    var instanceDeltas: [UInt32: float4x4] {
        var deltas: [UInt32: float4x4] = [:]
        for body in bodies {
            guard let placed = placedPoses[body.key] else { continue }
            guard
                let delta = body.instanceDelta(
                    fromPlacedPosition: placed.position, orientation: placed.orientation
                ) else { continue }
            deltas[body.reference.rawValue] = delta
        }
        return deltas
    }

    /// Current exterior draw owner by REFR FormID. The placing cell remains
    /// separate so persistence can rebuild the authoritative reference later.
    var exteriorDrawOwnership: [UInt32: CellCoordinate] {
        var ownership: [UInt32: CellCoordinate] = [:]
        for body in bodies {
            guard case let .exterior(coordinate) = body.occupiedCell else { continue }
            ownership[body.reference.rawValue] = coordinate
        }
        return ownership
    }

    func body(for key: ReferenceKey) -> DynamicBody? {
        bodies.first { $0.key == key }
    }

    /// Applies an impulse to one body, waking it.
    mutating func applyImpulse(
        _ impulse: SIMD3<Float>,
        at point: SIMD3<Float>,
        to key: ReferenceKey
    ) {
        guard let index = bodies.firstIndex(where: { $0.key == key }) else { return }
        bodies[index].applyImpulse(impulse, at: point)
    }

    /// The push a moving player capsule gives the clutter it walks into
    /// (issue #193 scope point 5).
    ///
    /// The capsule is not itself a rigid body — it is a character controller
    /// with no mass — so the shove is modelled rather than solved: a body whose
    /// collider overlaps the capsule takes an impulse along the horizontal
    /// direction from the capsule axis to the body, sized by the player's own
    /// horizontal speed and the body's mass. That makes a light bowl skitter
    /// and a heavy crate barely shift, which is the behaviour the shove is for,
    /// without letting a walking player inject unbounded energy.
    mutating func push(
        capsule: PlayerCapsule,
        feetPosition: SIMD3<Float>,
        velocity: SIMD3<Float>
    ) {
        let horizontal = SIMD3<Float>(velocity.x, velocity.y, 0)
        let speed = simd_length(horizontal)
        guard speed > Float.ulpOfOne else { return }
        let segment = (
            feetPosition + SIMD3<Float>(0, 0, capsule.radius),
            feetPosition + SIMD3<Float>(0, 0, capsule.height - capsule.radius)
        )
        for index in bodies.indices {
            let body = bodies[index]
            let near = DynamicCollisionMath.closestPoint(onSegment: segment, to: body.position)
            let combined = capsule.radius + body.definition.boundingRadius
            guard simd_distance_squared(near, body.position) <= combined * combined else {
                continue
            }
            var direction = SIMD3<Float>(
                body.position.x - near.x, body.position.y - near.y, 0
            )
            let length = simd_length(direction)
            direction = length > Float.ulpOfOne ? direction / length : horizontal / speed
            // Only the component of the walk that is into the body pushes it;
            // walking away from a crate must not drag it along.
            let approach = max(0, simd_dot(horizontal, direction))
            guard approach > Float.ulpOfOne else { continue }
            let impulse = direction * approach * body.definition.mass * Self.pushEfficiency
            bodies[index].applyImpulse(impulse, at: near)
        }
    }

    /// How much of the player's momentum a shove transfers. Below one because a
    /// walking actor braces rather than transferring its whole stride, and
    /// because a value of one makes light clutter fly.
    static let pushEfficiency: Float = 0.35
}
