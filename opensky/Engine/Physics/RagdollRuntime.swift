// Death and ragdoll activation (issue #197, roadmap item 15.6): the director
// that notices an actor at zero health, raises the census-named death events,
// waits for the graph's hand-off, and spawns the ragdoll it asks for.
//
// The order every frame runs in, and why it is that order:
//
//   1. `noteZeroHealth(_:)` — the 15.3 flag becomes a death. The engine writes
//      the death component and *asks* the graph to play the death, by raising
//      `bleedOutStart` and `DeathAnim`. It does not decide that the animation
//      has finished.
//   2. the fixed steps advance the graph, and the graph fires whatever it fires.
//   3. `handleGraphEvents(_:on:)` — a drained `AddRagdollToWorld` (or one of its
//      three siblings) is the hand-off, and that is what spawns the bodies.
//   4. `advance(by:)` — the live ragdolls step, and any that came to rest write
//      their resting transform into their death component.
//
// So a death whose graph refuses to hand off costs one death component and no
// bodies, which is visibly wrong in the right way: the actor is dead and still
// standing, rather than dead and in a pose the engine invented.
//
// ## The graph-less fallback
//
// An actor with no behavior graph attached — a synthetic test session, a
// headless probe, a creature whose graph this engine has not resolved — declares
// none of the hand-off events, so step 3 would never fire and the corpse would
// never fall. `RagdollWorldSeam.raiseRagdollEvent` reports whether a graph took
// the event, and a death that no graph took hands off immediately instead.
// The count of deaths that took that route is on the runtime, so a session can
// tell "the graph drove this" from "the engine had to".
//
// Documented in docs/engine/ragdoll.md.

import simd

/// One actor the runtime can kill and ragdoll.
nonisolated struct RagdollActor: Sendable {
    let key: ReferenceKey
    let cell: CellSceneLocation
    /// The ACHR this ragdoll stands for, for query attribution.
    let reference: FormID
    /// The ragdoll the actor's skeleton carries.
    let definition: RagdollDefinition
    /// The skeleton-world matrices the animation currently holds, in the actor's
    /// own space.
    let animatedBoneMatrices: [float4x4]
    /// Actor space to world space.
    let actorToWorld: float4x4
    /// How fast the whole actor was moving when it died, so a corpse keeps its
    /// momentum.
    let velocity: SIMD3<Float>

    init(
        key: ReferenceKey,
        cell: CellSceneLocation,
        reference: FormID,
        definition: RagdollDefinition,
        animatedBoneMatrices: [float4x4],
        actorToWorld: float4x4,
        velocity: SIMD3<Float> = .zero
    ) {
        self.key = key
        self.cell = cell
        self.reference = reference
        self.definition = definition
        self.animatedBoneMatrices = animatedBoneMatrices
        self.actorToWorld = actorToWorld
        self.velocity = velocity
    }
}

/// Everything `RagdollRuntime` needs from the session around it.
///
/// One protocol rather than a bag of closures, following the melee precedent:
/// every question below is something the session already knows how to answer,
/// and naming them together is what lets the acceptance tests drive the whole
/// runtime against a fake with no renderer, no window and no game data.
@MainActor
protocol RagdollWorldSeam: AnyObject {
    /// Everything a ragdoll needs about `key`, or nil when that actor has no
    /// resolvable skeleton right now.
    func ragdollActor(for key: ReferenceKey) -> RagdollActor?

    /// Raises one census-named event on `key`'s graph.
    ///
    /// - Returns: true when a graph declared the name. An actor with no graph
    ///   attached answers false, which is what routes the death down the
    ///   fallback rather than leaving it hanging.
    @discardableResult
    func raiseRagdollEvent(_ name: String, on key: ReferenceKey) -> Bool

    /// The static world a ragdoll collides with.
    var ragdollStepWorld: DynamicStepWorld { get }

    /// Records one component write, which is what makes a death survive a save.
    func writeDeathState(
        _ state: ActorDeathState,
        for key: ReferenceKey,
        in cell: CellSceneLocation
    )

    /// Reads back what was written, so the runtime never keeps its own copy of
    /// a fact the store owns.
    func deathState(of key: ReferenceKey) -> ActorDeathState?
}

@MainActor
final class RagdollRuntime {
    private(set) var world = RagdollWorld()
    /// Deaths whose graph took the death events and is expected to hand off.
    private(set) var pendingHandOffs: Set<ReferenceKey> = []
    /// How many deaths the graph drove, and how many the fallback had to.
    private(set) var graphDrivenDeathCount = 0
    private(set) var fallbackDeathCount = 0

    /// The blend the controlling `hkbRigidBodyRagdollControlsModifier` asks for,
    /// published by the behavior evaluator when it runs one. Vanilla's
    /// `DriveRagdollRB` in `0_master.hkx` carries 0.5 seconds; this is the
    /// default a session with no evaluated modifier falls back to, and it is
    /// that same value rather than an invented one.
    var blendDuration: Float = HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration

    private weak var seam: (any RagdollWorldSeam)?

    init(seam: (any RagdollWorldSeam)? = nil) {
        self.seam = seam
    }

    /// Attaches (or detaches) the session this runtime resolves against.
    func attach(seam: (any RagdollWorldSeam)?) {
        self.seam = seam
        reset()
    }

    // MARK: - Death

    /// One actor's health reached zero.
    ///
    /// Idempotent: an actor already recorded dead is ignored, so the caller can
    /// call this from a per-frame sweep over every resident actor without
    /// tracking edges itself.
    ///
    /// - Returns: true when this call is what killed the actor.
    @discardableResult
    func noteZeroHealth(of key: ReferenceKey) -> Bool {
        guard let seam, seam.deathState(of: key)?.isDead != true else { return false }
        guard let actor = seam.ragdollActor(for: key) else { return false }
        seam.writeDeathState(.justDied, for: key, in: actor.cell)
        var accepted = false
        for name in RagdollGraphNames.deathEvents {
            accepted = seam.raiseRagdollEvent(name, on: key) || accepted
        }
        if accepted {
            graphDrivenDeathCount += 1
            pendingHandOffs.insert(key)
        } else {
            fallbackDeathCount += 1
            activate(key, instant: false)
        }
        return true
    }

    /// Whether `key` reads as dead right now.
    func isDead(_ key: ReferenceKey) -> Bool {
        seam?.deathState(of: key)?.isDead ?? false
    }

    /// Whether activating `key` should open a container over its corpse rather
    /// than talk to it.
    func opensAsCorpse(_ key: ReferenceKey) -> Bool {
        isDead(key)
    }

    /// Records that `key`'s corpse has been searched.
    func noteLooted(_ key: ReferenceKey) {
        guard
            let seam,
            let state = seam.deathState(of: key), state.isDead, !state.wasLooted,
            let actor = seam.ragdollActor(for: key)
        else { return }
        seam.writeDeathState(state.looted, for: key, in: actor.cell)
    }

    // MARK: - Graph events

    /// Advances the ragdoll state by one actor's drained graph events.
    ///
    /// - Returns: true when this frame's events handed the skeleton over.
    @discardableResult
    func handleGraphEvents(_ names: [String], on key: ReferenceKey) -> Bool {
        var handed = false
        for name in names {
            guard let instant = RagdollGraphNames.handOff(name) else { continue }
            handed = activate(key, instant: instant) || handed
        }
        return handed
    }

    /// Spawns the bodies for one actor, whatever asked for it: the graph's
    /// hand-off, the fallback, or the panel's dev trigger.
    ///
    /// - Returns: true when a ragdoll now exists for `key`.
    @discardableResult
    func activate(_ key: ReferenceKey, instant: Bool) -> Bool {
        guard let seam, !world.isRagdolling(key) else { return false }
        guard let actor = seam.ragdollActor(for: key) else { return false }
        guard
            let instance = RagdollInstance(
                definition: actor.definition,
                animatedBoneMatrices: actor.animatedBoneMatrices,
                actorToWorld: actor.actorToWorld,
                blendDuration: instant ? 0 : blendDuration,
                cell: actor.cell,
                actor: actor.reference,
                key: key,
                velocity: actor.velocity
            )
        else { return false }
        world.add(instance, for: key, in: actor.cell)
        pendingHandOffs.remove(key)
        return true
    }

    /// The dev trigger: kills `key` if it is not dead already, then hands off
    /// without waiting for a graph. What the panel's button calls.
    ///
    /// - Returns: true when a ragdoll now exists for `key`.
    @discardableResult
    func trigger(_ key: ReferenceKey) -> Bool {
        guard let seam else { return false }
        if seam.deathState(of: key)?.isDead != true {
            noteZeroHealth(of: key)
        }
        return world.isRagdolling(key) || activate(key, instant: false)
    }

    // MARK: - Stepping

    /// Advances every live ragdoll and persists whatever came to rest.
    func advance(by frameTime: Float) {
        guard let seam else { return }
        world.advance(by: frameTime, world: seam.ragdollStepWorld)
        for settled in world.drainSettledTransforms() {
            guard
                let state = seam.deathState(of: settled.key),
                let actor = seam.ragdollActor(for: settled.key)
            else { continue }
            var updated = state
            updated.restingTransform = settled.transform
            guard updated != state else { continue }
            seam.writeDeathState(updated, for: settled.key, in: actor.cell)
        }
    }

    /// The pose one actor draws this frame, or nil when it is not ragdolling.
    func boneMatrices(
        for key: ReferenceKey,
        blending animated: [String: float4x4],
        worldToActor: float4x4
    ) -> [String: float4x4]? {
        world.boneMatrices(for: key, blending: animated, worldToActor: worldToActor)
    }

    /// Suspends and resumes stepping without discarding the corpses, which is
    /// what the panel's freeze control drives.
    var isFrozen: Bool {
        get { world.isFrozen }
        set { world.isFrozen = newValue }
    }

    /// Stops simulating the oldest corpses until at most `limit` remain, which
    /// is the combat loop's transient cap reaching the registry (issue #374).
    /// The deaths themselves are the store's and survive; what a trimmed corpse
    /// loses is its remaining motion.
    ///
    /// - Returns: how many stopped simulating.
    @discardableResult
    func trim(to limit: Int) -> Int {
        world.trim(to: limit)
    }

    /// Forgets every live ragdoll and every pending hand-off. The deaths
    /// themselves are the store's and survive.
    func reset() {
        world.removeAll()
        pendingHandOffs.removeAll()
        graphDrivenDeathCount = 0
        fallbackDeathCount = 0
    }
}
