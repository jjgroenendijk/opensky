// The world seam melee combat resolves a hit through, and the intent and status
// values on either side. One protocol, so tests can drive the runtime against a
// fake world. The runtime changes the world only through these calls and never
// reads a clock. See docs/engine/melee-combat.md.

public import OpenSkyActorsInterface
public import OpenSkyBehavior
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyProgressionInterface
import simd

/// One landed hit, kept for the readout's last-hit trace.
nonisolated public struct MeleeHitRecord: Equatable, Sendable {
    let target: ReferenceKey
    let damage: MeleeDamageResult
    /// Whether the target's graph was told to stagger.
    let staggered: Bool
    /// A swing, power attack, bash, or power bash.
    let kind: MeleeStrikeKind

    init(
        target: ReferenceKey,
        damage: MeleeDamageResult,
        staggered: Bool,
        kind: MeleeStrikeKind = .normal
    ) {
        self.target = target
        self.damage = damage
        self.staggered = staggered
        self.kind = kind
    }
}

/// Everything `MeleeCombatRuntime` needs from the session around it.
///
/// `WeaponEnchantmentApplying` is refined rather than duplicated: an enchanted
/// blade and an enchanted arrow apply through one implementation, exactly as
/// `reportScriptHit` is implemented once for melee, archery and the combat loop.
@MainActor
public protocol MeleeCombatWorld: ScriptHitReporting, SkillUseReporting, WeaponEnchantmentApplying,
    ImpactMaterialReading
{
    /// Where the player is standing and which way they face, this frame.
    var meleeAttacker: MeleeAttacker { get }

    /// The attacker's fortify multiplier for a swing with `handType`, which is
    /// `MeleeDamage`'s `attackMultiplier`. The session answers; without actor values
    /// it answers 1.
    func meleeAttackMultiplier(handType: CombatHandType) -> Float

    /// Every actor a swing could reach. Actors only — the caller's filter, not
    /// the runtime's, because only the session knows what is an ACHR.
    /// The destructible objects within `radius` of `center` a swing can strike.
    func meleeDestructibles(within radius: Float, of center: SIMD3<Float>) -> [MeleeTarget]
    /// Deals a swing's damage to a destructible object.
    func damageMeleeDestructible(_ object: ReferenceKey, amount: Float)
    func meleeTargets() -> [MeleeTarget]

    /// What `target` is blocking with, or nil when it is not blocking.
    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind?

    /// The blocker's fortify and perk multiplier, which is `MeleeDamage`'s
    /// `bonusMultiplier`. The session answers; the default 1 means no Fortify Block
    /// and no blocking perk.
    func meleeBlockMultiplier(of target: ReferenceKey) -> Float

    /// The skill, sneak-attack, armour, and perk terms of the player's `blow` on `target`.
    func meleeStrike(_ blow: CombatBlow, on target: ReferenceKey) -> WeaponStrike
    /// Whether `blow` strikes every actor in its arc rather than the nearest one.
    func meleeSweeps(_ blow: CombatBlow) -> Bool
    /// Lands the spell a perk applies when `blow` hits `target`.
    func applyMeleeHitSpell(_ blow: CombatBlow, on target: ReferenceKey)
    /// The stamina a power attack with `weapon` costs, after perks.
    func meleePowerAttackStamina(_ cost: Float, weapon: FormID?) -> Float
    /// The `ATKD` values of the player's attack that `event` starts, or nil.
    func meleeAttackData(event: String) -> RaceAttack.Properties?

    /// Charges `blocker` the stamina a blocked blow costs.
    func applyBlockStamina(_ damage: MeleeDamageResult, to blocker: ReferenceKey)

    /// Takes `cost` off the player's stamina. False, and nothing taken, below one point.
    func payMeleeStamina(_ cost: Float) -> Bool
    /// Whether the player owns the Power Bash perk.
    func canPowerBash() -> Bool
    /// The player's Block skill, and the base rating of its shield or nil without one.
    func meleeBashSource() -> (blockSkill: Float, shieldRating: Float?)
    /// The load-order identity of `weapon`, which a skill use names as its object.
    func meleeResolvedWeapon(_ weapon: FormID?) -> ResolvedFormID?

    /// Takes `amount` off `target`'s health.
    ///
    /// - Returns: true when the damage was actually applied, so a hit on a
    ///   reference with no actor-value state is reported rather than silently
    ///   counted as a hit that did nothing.
    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool
    /// The same at the contact point, which picks the body part struck.
    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey, at point: SIMD3<Float>) -> Bool

    /// Plays one resolved impact at the contact point.
    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)
    /// The default blood of a hit on an actor whose impact data resolved nothing.
    func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool)

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

    /// Writes one census-named variable on `target`'s graph, or the player's when nil.
    func writeCombatVariable(
        _ value: BehaviorVariableValue, named name: String, on target: ReferenceKey?
    )

    /// The Block skill of the blocker, which scales the blocked fraction.
    func meleeBlockSkill(of target: ReferenceKey) -> Float

    /// What the stagger magnitude reads of the player's attack that `event` starts.
    func meleeHitFacts(on target: ReferenceKey, event: String, weaponStagger: Float)
        -> HitReactionFacts
    /// Keeps one hit and its reaction for the readout.
    func noteHitReaction(_ report: HitReactionReport)

    /// Starts a paired kill move on `target` in place of the swing. False plays the swing.
    func startMeleeKillMove(on target: ReferenceKey, damage: Float, action: String) -> Bool
}

extension MeleeCombatWorld {
    public func noteHitReaction(_: HitReactionReport) {}

    public func meleeDestructibles(within _: Float, of _: SIMD3<Float>) -> [MeleeTarget] {
        []
    }

    /// A world with no races and no actor values reads the weapon's own stagger.
    public func meleeHitFacts(
        on _: ReferenceKey, event _: String, weaponStagger: Float
    ) -> HitReactionFacts {
        var facts = HitReactionFacts()
        facts.attackStagger = weaponStagger
        return facts
    }

    /// A world with no actor graphs writes only the player's.
    public func writeCombatVariable(
        _ value: BehaviorVariableValue, named name: String, on target: ReferenceKey?
    ) {
        guard target == nil || target == .player else { return }
        writeCombatVariable(value, named: name)
    }
}

nonisolated extension MeleeCombatWorld {
    public func meleeBlockSkill(of _: ReferenceKey) -> Float {
        MeleeDamage.defaultBlockSkill
    }

    /// A session with no fortify and no perk surface blocks by the base
    /// formula, which is the value the term had before either existed.
    public func meleeBlockMultiplier(of target: ReferenceKey) -> Float {
        1
    }

    /// A session with no skills and no armour scales nothing.
    public func meleeStrike(_: CombatBlow, on _: ReferenceKey) -> WeaponStrike {
        .plain
    }

    /// Without perks a swing strikes the nearest actor alone.
    public func meleeSweeps(_: CombatBlow) -> Bool {
        false
    }

    public func applyMeleeHitSpell(_: CombatBlow, on _: ReferenceKey) {}

    public func showDefaultBlood(on _: ReferenceKey, at _: SIMD3<Float>, melee _: Bool) {}

    public func meleePowerAttackStamina(_ cost: Float, weapon _: FormID?) -> Float {
        cost
    }

    /// A session with no races has no attack data.
    public func meleeAttackData(event _: String) -> RaceAttack.Properties? {
        nil
    }

    /// A session with no stamina pays nothing to block.
    public func applyBlockStamina(_: MeleeDamageResult, to _: ReferenceKey) {}

    /// A session with no stamina pays for every power attack.
    public func payMeleeStamina(_: Float) -> Bool {
        true
    }

    /// A session with no perks owns none.
    public func canPowerBash() -> Bool {
        false
    }

    public func meleeBashSource() -> (blockSkill: Float, shieldRating: Float?) {
        (MeleeDamage.defaultBlockSkill, nil)
    }

    public func meleeResolvedWeapon(_: FormID?) -> ResolvedFormID? {
        nil
    }
}

/// Melee and archery read a struck actor's material through this one seam, so a
/// session that is both worlds has one implementation.
@MainActor
public protocol ImpactMaterialReading {
    /// The MATT an actor's body counts as when struck: its race's `NAM4`.
    func impactMaterial(of target: ReferenceKey) -> FormID?
}

extension ImpactMaterialReading {
    /// No material: the impact data set's default entry plays.
    public func impactMaterial(of _: ReferenceKey) -> FormID? {
        nil
    }
}

/// A world without body parts lands a hit the same at any point.
extension MeleeCombatWorld {
    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey, at _: SIMD3<Float>) -> Bool {
        applyMeleeDamage(amount, to: target)
    }
}
