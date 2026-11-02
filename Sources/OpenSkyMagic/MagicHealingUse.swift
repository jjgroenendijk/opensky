// Restoration experience from healing. UESP "Skyrim:Leveling": Restoration gives "1 base XP
// damage healed by healing spells" and "1 base XP per Magicka used on non-healing spells".
// The effect runtime notes the health it restored; the coordinator reports it.
// See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Health one healing effect gave back, already scaled by the effect's skill usage factor.
nonisolated public struct MagicHealingUse: Equatable, Sendable {
    public let caster: ReferenceKey
    public let skill: Int32
    public let amount: Float

    public init(caster: ReferenceKey, skill: Int32, amount: Float) {
        self.caster = caster
        self.skill = skill
        self.amount = amount
    }
}

nonisolated extension MagicEffectData {
    /// A healing effect: a beneficial value modifier on Health in a magic school. It
    /// earns experience by the health it restores, not by the magicka it costs.
    public var isHealing: Bool {
        archetype == .valueModifier
            && relatedActorValue == ActorValueIdentity.index(named: "Health")
            && !flags.contains(.detrimental)
            && ActorValueIdentity.isSkill(index: magicSkill)
    }
}

extension ActiveEffectRuntime {
    /// Restores `amount` of `index` on `target` and notes what a healing effect gave back.
    mutating func restore(
        _ amount: Float,
        at index: Int32,
        on target: ActorValueHolder,
        effect: ReferenceKey,
        caster: ReferenceKey?
    ) {
        let before = values.value(at: index, on: target) ?? 0
        values.restore(at: index, by: amount, on: target)
        guard
            let caster,
            let data = effects.effect(key: effect)?.effect.data, data.isHealing,
            index == data.relatedActorValue
        else { return }
        let healed = max(0, (values.value(at: index, on: target) ?? before) - before)
        let factor = data.skillUsageMultiplier
        let scaled = healed * (factor.isFinite ? max(0, factor) : 0)
        guard scaled > 0 else { return }
        healing.append(MagicHealingUse(caster: caster, skill: data.magicSkill, amount: scaled))
    }
}
