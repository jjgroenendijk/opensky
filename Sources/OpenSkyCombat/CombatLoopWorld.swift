// The world seam the combat loop drives through, and the values on either side.
// One protocol, so the acceptance chain can drive the loop against a fake world.
// The runtime changes the world only through these calls and never reads a
// clock. See docs/engine/combat.md.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// One resident actor as the combat loop sees it.
///
/// A flat observation rather than a live handle, so the runtime cannot reach
/// past what it was given and a test can hand it a literal.
nonisolated public struct CombatActorObservation: Equatable, Sendable {
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    public let capsule: PlayerCapsule
    /// Facing yaw in radians, in the locomotion bridge's convention. Used to
    /// aim its own hit volume.
    public let facing: Float
    /// The actor's scale, which multiplies its reach.
    public let scale: Float
    /// Whether `ActorDeathState` has latched. A dead actor is never a combat
    /// target and never attacks.
    public let isDead: Bool
    /// FULL name, editor ID, or key and base form, formatted only when read.
    public let label: ActorLabel

    public var name: String {
        label.text
    }

    public init(
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
        label = ActorLabel(name)
    }

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        facing: Float,
        scale: Float,
        isDead: Bool,
        label: ActorLabel
    ) {
        self.key = key
        self.feet = feet
        capsule = .standard
        self.facing = facing
        self.scale = scale
        self.isDead = isDead
        self.label = label
    }
}

/// How many of each transient combat object are live right now.
nonisolated public struct CombatTransientCounts: Equatable, Sendable {
    public var liveProjectiles = 0
    public var stuckProjectiles = 0
    public var activeRagdolls = 0
    public var awakeBodies = 0

    public static let none = CombatTransientCounts()

    public init(
        liveProjectiles: Int = 0,
        stuckProjectiles: Int = 0,
        activeRagdolls: Int = 0,
        awakeBodies: Int = 0
    ) {
        self.liveProjectiles = liveProjectiles
        self.stuckProjectiles = stuckProjectiles
        self.activeRagdolls = activeRagdolls
        self.awakeBodies = awakeBodies
    }
}

/// Everything `CombatLoopRuntime` needs from the session around it.
@MainActor
public protocol CombatLoopWorld: ScriptHitReporting, SkillUseReporting {
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
    /// call melee and archery make, so an NPC's blows and the player's reach
    /// health by one path.
    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool

    /// What `key` is blocking with, or nil when it is not blocking.
    ///
    /// The player answers from the melee runtime's own guard state. Every other
    /// actor answers from its combat behavior machine, which is 16.7's second
    /// scope point: a blocked hit in either direction goes through the same
    /// pinned 15.4 formula, and neither side has a damage path of its own.
    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind?

    /// The blocker's fortify and perk multiplier for an incoming blow, which is
    /// `MeleeDamage`'s `bonusMultiplier`. Defaults to 1.
    func combatBlockMultiplier(of key: ReferenceKey) -> Float

    /// What `observer` currently makes of `target`, projected from 16.6's
    /// detection pair state.
    ///
    /// The seam is observer-and-target rather than "is the player detected",
    /// because `StartCombat` may name a target that is not the player and the
    /// machine has to be told the truth about whichever one it was given.
    func combatAwareness(
        of observer: ReferenceKey, toward target: ReferenceKey
    ) -> CombatAwareness

    /// `key`'s current health over its re-derived maximum, 0 through 1.
    ///
    /// A fraction rather than the two numbers, because the one decision that
    /// reads it — whether to break off — is stated as a fraction and computing
    /// it at the call site would let two callers disagree about the same actor.
    func combatHealthFraction(of key: ReferenceKey) -> Float

    /// The profile `key` swings with, which sizes its reach and its damage.
    func combatWeapon(of key: ReferenceKey) -> MeleeWeaponProfile

    /// The numbers of `key`'s resolved CSTY combat style, or nil when it has none.
    func combatStyle(of key: ReferenceKey) -> CombatStyleTuning?

    /// What `key` could cast right now and what it can pay for. The session holds
    /// the spellbook and magicka. A world with no caster runtime answers `.none`, so
    /// every actor fights with its hands.
    func combatCasting(of key: ReferenceKey) -> CombatCastingProfile

    /// Starts `option`'s cast in `key`'s hand, through the player's `CasterRuntime`.
    /// - Returns: false when the cast was refused (unknown spell, dropped record, not
    ///   enough magicka). The machine then swings instead.
    @discardableResult
    func beginCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool

    /// Lets go of the cast `key` is holding: the magicka is spent and the 19.8
    /// delivery happens, aimed at whatever the actor is fighting.
    ///
    /// - Returns: whether a spell actually left the hand.
    @discardableResult
    func releaseCombatCast(_ option: CombatSpellOption, by key: ReferenceKey) -> Bool

    /// Drops a cast in flight without casting it, for an actor that staggered,
    /// broke off or gave up mid-charge.
    func cancelCombatCast(by key: ReferenceKey)

    /// Sends `key` walking to `point` through the NPC mover.
    /// - Returns: true when a path was found and the mover took it. False for an
    ///   unreachable point or a full mover cap; the machine then tries another point.
    @discardableResult
    func moveCombatActor(_ key: ReferenceKey, to point: SIMD3<Float>) -> Bool

    /// Stops `key` where it stands, which is what an actor does when it is in
    /// reach, blocking, staggered or done fighting.
    func stopCombatMovement(of key: ReferenceKey)

    /// Hands `key` back to its 16.5 package, re-selecting one immediately rather
    /// than at the next scheduled boundary. Called on the step pursuit ends,
    /// which is the milestone gate's "resume" line.
    func resumeCombatPackage(for key: ReferenceKey)

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

nonisolated extension CombatLoopWorld {
    /// A session with no fortify and no perk surface blocks by the base
    /// formula, which is the value the term had before either existed.
    public func combatBlockMultiplier(of key: ReferenceKey) -> Float {
        1
    }

    /// A session that resolves no combat styles fights with the base settings.
    public func combatStyle(of key: ReferenceKey) -> CombatStyleTuning? {
        nil
    }
}
