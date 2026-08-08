// The world seam melee combat resolves a hit through (issue #195, roadmap item
// 15.4), and the intent and status values on either side of it.
//
// One protocol rather than a bag of optional closures. `MeleeCombatRuntime`
// asks five questions and performs three actions, and every one of them is
// something the session already knows how to answer — where the player is
// standing, which actors are resident, what the ground is made of, how to take
// health off a reference, how to play a positional sound, how to raise an event
// on a graph. Naming them together is what lets the acceptance tests drive the
// whole runtime against a fake world with no renderer, no window, and no game
// data, which is what "deterministic tests" in the issue's acceptance means.
//
// The seam is deliberately narrow in one direction: the runtime never mutates
// the world except through these three calls, and it never reads a clock. A
// swing's whole trajectory through the engine is (intent in) -> (events in) ->
// (these calls out).
//
// Documented in docs/engine/melee-combat.md.

import simd

/// Who is swinging, and from where.
nonisolated struct MeleeAttacker: Equatable, Sendable {
    /// The attacker's reference, so a swing can never hit its own owner.
    let key: ReferenceKey
    /// Capsule bottom, world space.
    let feet: SIMD3<Float>
    let capsule: PlayerCapsule
    /// Facing yaw in radians, in the locomotion bridge's convention.
    let facing: Float
    /// The actor's scale, which multiplies reach. 1 for the player, whose XSCL
    /// this engine does not read.
    let scale: Float

    init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        facing: Float,
        scale: Float = 1
    ) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
        self.facing = facing
        self.scale = scale
    }
}

/// One frame of melee intent, filled from the drained camera input beside
/// `LocomotionIntent` and held across the fixed steps that frame drives.
nonisolated struct MeleeIntent: Equatable, Sendable {
    /// One attack press, consumed by the first step that can act on it.
    var attack = false
    /// Block key held. A level, not an edge, exactly like sprint.
    var block = false
    /// One draw/sheath press, consumed the same way as an attack.
    var toggleWeaponDrawn = false

    static let still = MeleeIntent()
}

/// One landed hit, kept for the panel's last-hit trace.
nonisolated struct MeleeHitRecord: Equatable, Sendable {
    let target: ReferenceKey
    /// How far along the swing contact was found, world units.
    let distance: Float
    let position: SIMD3<Float>
    let damage: MeleeDamageResult
    /// The impact sound that played, or nil where the chain named none.
    let sound: FormID?
    /// Whether the target's graph was told to stagger.
    let staggered: Bool
    /// Which swing landed it, so two hits from one swing are visibly one swing.
    let swingID: Int
}

/// Everything `MeleeCombatRuntime` needs from the session around it.
@MainActor
protocol MeleeCombatWorld: ScriptHitReporting {
    /// Where the player is standing and which way they face, this frame.
    var meleeAttacker: MeleeAttacker { get }

    /// Every actor a swing could reach. Actors only — the caller's filter, not
    /// the runtime's, because only the session knows what is an ACHR.
    func meleeTargets() -> [MeleeTarget]

    /// The MATT type of what was struck at `position`, or nil where it names
    /// none. Feeds the IPCT lookup exactly as the ground material feeds a
    /// footstep's.
    func meleeMaterial(at position: SIMD3<Float>) -> FormID?

    /// What `target` is blocking with, or nil when it is not blocking.
    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind?

    /// Takes `amount` off `target`'s health.
    ///
    /// - Returns: true when the damage was actually applied, so a hit on a
    ///   reference with no actor-value state is reported rather than silently
    ///   counted as a hit that did nothing.
    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool

    /// Plays one resolved impact at the contact point.
    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)

    /// Raises one census-named event on a graph: the player's when `target` is
    /// nil, otherwise that actor's.
    ///
    /// - Returns: true when a graph declared the name. A target with no graph
    ///   attached answers false, which is how a stagger that could not be
    ///   played becomes visible in the trace instead of being assumed.
    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool

    /// Writes one census-named variable on the player's graph.
    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String)
}
