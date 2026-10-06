// The world seam melee combat resolves a hit through, and the intent and status
// values on either side. One protocol, so tests can drive the runtime against a
// fake world. The runtime changes the world only through these calls and never
// reads a clock. See docs/engine/melee-combat.md.

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// Who is swinging, and from where.
nonisolated public struct MeleeAttacker: Equatable, Sendable {
    /// The attacker's reference, so a swing can never hit its own owner.
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    public let capsule: PlayerCapsule
    /// Facing yaw in radians, in the locomotion bridge's convention.
    public let facing: Float
    /// The actor's scale, which multiplies reach. 1 for the player, whose XSCL
    /// this engine does not read.
    public let scale: Float

    public init(
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

/// One landed hit, kept for the panel's last-hit trace.
nonisolated public struct MeleeHitRecord: Equatable, Sendable {
    public let target: ReferenceKey
    /// How far along the swing contact was found, world units.
    public let distance: Float
    public let damage: MeleeDamageResult
    /// The impact sound that played, or nil where the chain named none.
    public let sound: FormID?
    /// Whether the target's graph was told to stagger.
    public let staggered: Bool
    /// What the weapon's enchantment did, or nil when the weapon has none or this
    /// session cannot apply one.
    public let enchantment: WeaponEnchantmentReport?

    public init(
        target: ReferenceKey,
        distance: Float,
        damage: MeleeDamageResult,
        sound: FormID?,
        staggered: Bool,
        enchantment: WeaponEnchantmentReport? = nil
    ) {
        self.target = target
        self.distance = distance
        self.damage = damage
        self.sound = sound
        self.staggered = staggered
        self.enchantment = enchantment
    }
}

/// Everything `MeleeCombatRuntime` needs from the session around it.
///
/// `WeaponEnchantmentApplying` is refined rather than duplicated: an enchanted
/// blade and an enchanted arrow apply through one implementation, exactly as
/// `reportScriptHit` is implemented once for melee, archery and the combat loop.
@MainActor
public protocol MeleeCombatWorld: ScriptHitReporting, SkillUseReporting, WeaponEnchantmentApplying {
    /// Where the player is standing and which way they face, this frame.
    var meleeAttacker: MeleeAttacker { get }

    /// The attacker's fortify multiplier for a swing with `handType`, which is
    /// `MeleeDamage`'s `attackMultiplier`. The session answers; without actor values
    /// it answers 1.
    func meleeAttackMultiplier(handType: CombatHandType) -> Float

    /// Every actor a swing could reach. Actors only — the caller's filter, not
    /// the runtime's, because only the session knows what is an ACHR.
    func meleeTargets() -> [MeleeTarget]

    /// What `target` is blocking with, or nil when it is not blocking.
    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind?

    /// The blocker's fortify and perk multiplier, which is `MeleeDamage`'s
    /// `bonusMultiplier`. The session answers; the default 1 means no Fortify Block
    /// and no blocking perk.
    func meleeBlockMultiplier(of target: ReferenceKey) -> Float

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

nonisolated extension MeleeCombatWorld {
    /// A session with no fortify and no perk surface blocks by the base
    /// formula, which is the value the term had before either existed.
    public func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        1
    }
}
