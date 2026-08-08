// The world seam the combat loop drives through (issue #374, roadmap item
// 15.7), and the values on either side of it.
//
// One protocol rather than a bag of closures, for the reason `MeleeCombatWorld`
// is one: every question here is something the session already knows how to
// answer — where the player is standing, which actors are resident and alive,
// what hostility the world-state store holds for one of them, how to take
// health off a reference, how to raise a graph event, how many transient
// objects are live. Naming them together is what lets the acceptance chain
// drive the whole loop against a fake world with no renderer, no window and no
// game data.
//
// The seam is deliberately narrow in one direction: the runtime mutates the
// world only through the calls declared here, and it never reads a clock. A
// fight's whole trajectory through the engine is (hostility in) -> (fixed steps)
// -> (these calls out).
//
// Documented in docs/engine/combat.md.

import simd

/// One resident actor as the combat loop sees it.
///
/// A flat observation rather than a live handle, so the runtime cannot reach
/// past what it was given and a test can hand it a literal.
nonisolated struct CombatActorObservation: Equatable, Sendable {
    let key: ReferenceKey
    /// Capsule bottom, world space.
    let feet: SIMD3<Float>
    let capsule: PlayerCapsule
    /// Facing yaw in radians, in the locomotion bridge's convention. Used to
    /// aim the dev target's own hit volume.
    let facing: Float
    /// The actor's scale, which multiplies its reach.
    let scale: Float
    /// Whether `ActorDeathState` has latched. A dead actor is never a combat
    /// target and never attacks.
    let isDead: Bool
    /// FULL name when one resolves, else the editor ID, else the FormID. Never
    /// empty, so a readout line always names something.
    let name: String

    init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        facing: Float = 0,
        scale: Float = 1,
        isDead: Bool = false,
        name: String = "—"
    ) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
        self.facing = facing
        self.scale = scale
        self.isDead = isDead
        self.name = name
    }

    /// This actor as a melee target, so the dev target's swing runs through the
    /// same 15.4 detector the player's does.
    var meleeTarget: MeleeTarget {
        MeleeTarget(key: key, feet: feet, capsule: capsule)
    }
}

/// Which single-clip animation the dev target should play.
///
/// Three cases rather than a free-form clip name because NPC playback in this
/// milestone is one clip at a time (`ActorAnimationPlayback`) and the engine
/// picks which; a name would let a caller ask for something no rig carries.
nonisolated enum CombatActorClip: String, Equatable, Sendable, CaseIterable {
    case attack
    case stagger
    case hitReaction
}

/// How many of each transient combat object are live right now.
nonisolated struct CombatTransientCounts: Equatable, Sendable {
    var liveProjectiles = 0
    var stuckProjectiles = 0
    var activeRagdolls = 0
    var awakeBodies = 0

    static let none = CombatTransientCounts()
}

/// Everything `CombatLoopRuntime` needs from the session around it.
@MainActor
protocol CombatLoopWorld: AnyObject {
    /// Where the player is standing and which way they face, this frame.
    var combatPlayer: MeleeAttacker { get }

    /// Every resident actor, in `ReferenceKey` order. Actors only — the
    /// caller's filter, not the runtime's, because only the session knows what
    /// is an ACHR.
    func combatActors() -> [CombatActorObservation]

    /// `key`'s stored regard for the player, neutral when it carries none.
    func combatHostility(of key: ReferenceKey) -> ActorHostility

    /// Writes `key`'s regard for the player through `WorldStateStore`, so the
    /// journal, the dirty counts and the save see it.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    func setCombatHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool

    /// Takes `amount` off `key`'s health, reporting whether it landed. The same
    /// call melee and archery make, so the dev target's blows and the player's
    /// reach health by one path.
    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool

    /// What `key` is blocking with, or nil when it is not blocking. The player
    /// answers from the melee runtime's own guard state, which is what makes a
    /// blocked incoming hit go through the pinned 15.4 formula.
    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind?

    /// Raises one census-named event on a graph: the player's when `target` is
    /// nil, otherwise that actor's.
    ///
    /// - Returns: true when a graph declared the name. An actor with no graph
    ///   attached answers false, which is how a reaction that could not be
    ///   played becomes visible in the readout instead of being assumed.
    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool

    /// Writes one census-named variable on the player's graph.
    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String)

    /// Plays one single-clip reaction on a resident actor.
    ///
    /// - Returns: true when playback took the clip. False is the honest answer
    ///   for an actor whose rig carries no such animation, and the readout says
    ///   so rather than claiming a reaction the player cannot see.
    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool

    /// How many transient combat objects are live right now.
    var combatTransients: CombatTransientCounts { get }

    /// Brings each transient population back inside `limits`, oldest first.
    ///
    /// - Returns: how many of each kind were removed.
    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts

    /// Drops every transient that cannot survive a reload: arrows in flight and
    /// ragdolls still falling. Called on save and on load, which is what makes
    /// a fight saved mid-swing resume consistently.
    func despawnCombatTransients()

    /// Tells the music director whether the player is in combat, so entering
    /// combat selects the combat MUSC and leaving it returns to the previous
    /// selection.
    func setCombatMusicActive(_ active: Bool)
}
