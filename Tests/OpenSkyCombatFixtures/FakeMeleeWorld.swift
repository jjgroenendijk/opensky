@testable import OpenSkyActorsInterface
@testable import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
@testable import OpenSkyProgressionInterface
import simd

/// A `MeleeCombatWorld` that records rather than acts, so the runtime can be
/// driven with no renderer, no window, and no game data.
@MainActor
public final class FakeMeleeWorld: MeleeCombatWorld {
    public var attacker = MeleeAttacker(key: .generated(0), feet: SIMD3<Float>(), facing: 0)
    public var targets: [MeleeTarget] = []
    public var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    public var material: FormID?
    /// The fortify multiplier the runtime asks for. 1 is what the
    /// formula reduces to for a character with no fortify effect.
    public var attackMultiplier: Float = 1

    /// Skill uses the runtime reported, recorded rather than
    /// converted.
    public private(set) var skillUses: [SkillUseEvent] = []

    public init() {}

    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    public private(set) var damage: [ReferenceKey: Float] = [:]
    public private(set) var raised: [String] = []
    public private(set) var raisedOnTarget: [ReferenceKey: [String]] = [:]
    public private(set) var variables: [String: BehaviorVariableValue] = [:]
    public private(set) var impacts: [ResolvedMeleeImpact] = []
    /// Enchanted hits the runtime handed out, recorded rather than
    /// applied: what the melee suites need is that the swing reached the seam with
    /// the struck target and the contact point, and `EnchantmentRuntimeTests` asks
    /// what applying one does against a real effect runtime.
    public private(set) var enchantedHits: [WeaponEnchantmentHit] = []
    /// Variable names written before the first event of the session was
    /// raised, so a test can pin the write-then-raise order.
    public private(set) var writesBeforeFirstRaise: Set<String> = []

    public var meleeAttacker: MeleeAttacker {
        attacker
    }

    public func meleeTargets() -> [MeleeTarget] {
        targets
    }

    public func meleeMaterial() -> FormID? {
        material
    }

    public func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        blocks[target]
    }

    public func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        attackMultiplier
    }

    @discardableResult
    public func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        enchantedHits.append(hit)
        return WeaponEnchantmentReport(
            name: hit.profile.name,
            charge: hit.profile.fullCharge,
            didFire: true,
            entryCount: hit.profile.entries.count,
            storedCount: 0,
            adjustments: []
        )
    }

    @discardableResult
    public func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        damage[target, default: 0] += amount
        return true
    }

    public func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        impacts.append(impact)
    }

    @discardableResult
    public func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let target else {
            raised.append(name)
            return true
        }
        raisedOnTarget[target, default: []].append(name)
        return true
    }

    public func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
        if raised.isEmpty, raisedOnTarget.isEmpty {
            writesBeforeFirstRaise.insert(name)
        }
    }
}
