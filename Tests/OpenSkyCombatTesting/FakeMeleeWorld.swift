// A copy of the fake in OpenSkyCombatTests. Both test targets need it, and a
// testing library cannot hold it, because it conforms to an implementation protocol.

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
final class FakeMeleeWorld: MeleeCombatWorld {
    var attacker = MeleeAttacker(key: .generated(0), feet: SIMD3<Float>(), facing: 0)
    var targets: [MeleeTarget] = []
    var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    var material: FormID?
    /// The fortify multiplier the runtime asks for (issue #472). 1 is what the
    /// formula reduces to for a character with no fortify effect.
    var attackMultiplier: Float = 1

    /// Skill uses the runtime reported (issue #498), recorded rather than
    /// converted.
    private(set) var skillUses: [SkillUseEvent] = []

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        skillUses.append(use)
        return 0
    }

    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var raised: [String] = []
    private(set) var raisedOnTarget: [ReferenceKey: [String]] = [:]
    private(set) var variables: [String: BehaviorVariableValue] = [:]
    private(set) var impacts: [ResolvedMeleeImpact] = []
    /// Enchanted hits the runtime handed out (issue #472), recorded rather than
    /// applied: what the melee suites need is that the swing reached the seam with
    /// the struck target and the contact point, and `EnchantmentRuntimeTests` asks
    /// what applying one does against a real effect runtime.
    private(set) var enchantedHits: [WeaponEnchantmentHit] = []
    /// Variable names written before the first event of the session was
    /// raised, so a test can pin the write-then-raise order.
    private(set) var writesBeforeFirstRaise: Set<String> = []

    var meleeAttacker: MeleeAttacker {
        attacker
    }

    func meleeTargets() -> [MeleeTarget] {
        targets
    }

    func meleeMaterial(at position: SIMD3<Float>) -> FormID? {
        material
    }

    func meleeBlock(of target: ReferenceKey) -> MeleeBlockKind? {
        blocks[target]
    }

    func meleeAttackMultiplier(handType: CombatHandType) -> Float {
        attackMultiplier
    }

    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport? {
        enchantedHits.append(hit)
        return WeaponEnchantmentReport(
            item: hit.profile.item,
            name: hit.profile.name,
            charge: hit.profile.fullCharge,
            didFire: true,
            entryCount: hit.profile.entries.count,
            storedCount: 0,
            adjustments: []
        )
    }

    @discardableResult
    func applyMeleeDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        damage[target, default: 0] += amount
        return true
    }

    func playMeleeImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>) {
        impacts.append(impact)
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        guard let target else {
            raised.append(name)
            return true
        }
        raisedOnTarget[target, default: []].append(name)
        return true
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
        if raised.isEmpty, raisedOnTarget.isEmpty {
            writesBeforeFirstRaise.insert(name)
        }
    }
}
