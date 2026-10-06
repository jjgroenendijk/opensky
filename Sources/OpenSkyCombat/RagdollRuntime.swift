// Death and ragdoll activation. Order per frame: `noteZeroHealth(_:)` writes
// the death and raises the death events; the graph steps;
// `handleGraphEvents(_:on:)` spawns the bodies on the hand-off; `advance(by:)`
// steps ragdolls and stores rest poses. An actor with no graph hands off at
// once, and the runtime counts those. See docs/engine/ragdoll.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyWorldState
import simd

/// One actor the runtime can kill and ragdoll.
nonisolated public struct RagdollActor: Sendable {
    public let key: ReferenceKey
    public let cell: CellSceneLocation
    /// The ACHR this ragdoll stands for, for query attribution.
    public let reference: FormID
    /// The ragdoll the actor's skeleton carries.
    public let definition: RagdollDefinition
    /// The skeleton-world matrices the animation currently holds, in the actor's
    /// own space.
    public let animatedBoneMatrices: [float4x4]
    /// Actor space to world space.
    public let actorToWorld: float4x4
    /// How fast the whole actor was moving when it died, so a corpse keeps its
    /// momentum.
    public let velocity: SIMD3<Float>

    public init(
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
public protocol RagdollWorldSeam: AnyObject {
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

    /// Queues `OnDying(akKiller)` and `OnDeath(akKiller)` on the scripts attached to
    /// `key`. Called inside the death latch, so each fires exactly once.
    /// - Returns: how many events were queued; 0 without a script VM.
    @discardableResult
    func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int
}

nonisolated extension RagdollWorldSeam {
    /// A world with no script layer behind it queues nothing, which is what
    /// every acceptance fake and every synthetic scene genuinely is.
    @discardableResult
    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        0
    }
}

@MainActor
public final class RagdollRuntime: DeathReporting {
    public private(set) var world = RagdollWorld()
    /// Deaths whose graph took the death events and is expected to hand off.
    public private(set) var pendingHandOffs: Set<ReferenceKey> = []
    /// How many deaths the graph drove, and how many the fallback had to.
    public private(set) var graphDrivenDeathCount = 0
    public private(set) var fallbackDeathCount = 0
    /// `OnDying` and `OnDeath` events this runtime's deaths queued, counted together.
    /// Zero without a script VM or for a corpse with no scripts.
    public private(set) var deathEventsQueued = 0

    /// The blend the controlling `hkbRigidBodyRagdollControlsModifier` asks for,
    /// published by the behavior evaluator when it runs one. Vanilla's
    /// `DriveRagdollRB` in `0_master.hkx` carries 0.5 seconds; this is the
    /// default a session with no evaluated modifier falls back to, and it is
    /// that same value rather than an invented one.
    public var blendDuration: Float = HKBRigidBodyRagdollControlsModifier.vanillaBlendDuration

    private weak var seam: (any RagdollWorldSeam)?

    public init(seam: (any RagdollWorldSeam)? = nil) {
        self.seam = seam
    }

    /// Attaches (or detaches) the session this runtime resolves against.
    public func attach(seam: (any RagdollWorldSeam)?) {
        self.seam = seam
        reset()
    }

    // MARK: - Death

    /// One actor's health reached zero. Idempotent, so a per-frame sweep can call it.
    /// Every death path arrives here, so `OnDying` and `OnDeath` fire once.
    /// - Parameter killer: who caused the death, or nil (the `akKiller` default).
    /// - Returns: true when this call killed the actor.
    @discardableResult
    public func noteZeroHealth(of key: ReferenceKey, killer: ReferenceKey? = nil) -> Bool {
        guard let seam, seam.deathState(of: key)?.isDead != true else { return false }
        guard let actor = seam.ragdollActor(for: key) else { return false }
        seam.writeDeathState(.justDied, for: key, in: actor.cell)
        deathEventsQueued += seam.queueActorDeathEvents(for: key, killer: killer)
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
    public func isDead(_ key: ReferenceKey) -> Bool {
        seam?.deathState(of: key)?.isDead ?? false
    }

    /// Whether activating `key` should open a container over its corpse rather
    /// than talk to it.
    public func opensAsCorpse(_ key: ReferenceKey) -> Bool {
        isDead(key)
    }

    /// Records that `key`'s corpse has been searched.
    public func noteLooted(_ key: ReferenceKey) {
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
    public func handleGraphEvents(_ names: [String], on key: ReferenceKey) -> Bool {
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
    public func activate(_ key: ReferenceKey, instant: Bool) -> Bool {
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
    public func trigger(_ key: ReferenceKey) -> Bool {
        guard let seam else { return false }
        if seam.deathState(of: key)?.isDead != true {
            noteZeroHealth(of: key)
        }
        return world.isRagdolling(key) || activate(key, instant: false)
    }

    // MARK: - Stepping

    /// Advances every live ragdoll and persists whatever came to rest.
    public func advance(by frameTime: Float) {
        guard let seam else { return }
        world.advance(by: frameTime, world: seam.ragdollStepWorld)
        for settled in world.drainSettledTransforms() {
            guard
                let state = seam.deathState(of: settled.key),
                let actor = seam.ragdollActor(for: settled.key)
            else { continue }
            var updated = state
            updated.restingTransform = ReferenceTransformOverride(placement: settled.placement)
            guard updated != state else { continue }
            seam.writeDeathState(updated, for: settled.key, in: actor.cell)
        }
    }

    /// Suspends and resumes stepping without discarding the corpses, which is
    /// what the panel's freeze control drives.
    public var isFrozen: Bool {
        get { world.isFrozen }
        set { world.isFrozen = newValue }
    }

    /// Whether a ragdoll's own bones may touch each other; the panel's
    /// self-collision control drives it.
    public var isSelfCollisionEnabled: Bool {
        get { world.isSelfCollisionEnabled }
        set { world.isSelfCollisionEnabled = newValue }
    }

    /// Stops simulating the oldest corpses until at most `limit` remain. The deaths
    /// stay in the store; a trimmed corpse only loses its motion.
    /// - Returns: how many stopped simulating.
    @discardableResult
    public func trim(to limit: Int) -> Int {
        world.trim(to: limit)
    }

    /// Stops simulating every corpse whose cell left `resident`. The death and its
    /// resting transform stay in the store.
    /// - Returns: how many stopped simulating.
    @discardableResult
    public func retainRagdolls(in resident: Set<CellSceneLocation>) -> Int {
        world.retainCells(resident)
    }

    /// Forgets every live ragdoll and every pending hand-off. The deaths
    /// themselves are the store's and survive.
    public func reset() {
        world.removeAll()
        pendingHandOffs.removeAll()
        graphDrivenDeathCount = 0
        fallbackDeathCount = 0
        deathEventsQueued = 0
    }
}
