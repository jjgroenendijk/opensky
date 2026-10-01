// What casting teaches. Skill uses accrue per effect (<https://ck.uesp.net/wiki/Magic_Effect>),
// so a two-school spell feeds both. The base is the spell's cost before perk discounts;
// a maintained cast reports what it drained that step (UESP Skyrim:Leveling).
// See docs/engine/skill-advancement.md and docs/engine/spellcasting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

extension CasterRuntime {
    /// Reports one cast's skill uses, one per effect that names a magic skill.
    ///
    /// - Parameters:
    ///   - amount: the magicka the use is measured in — the spell's authored
    ///     base cost for a fire-and-forget cast, the magicka drained for one
    ///     step of a maintained one.
    public func noteSkillUse(of spell: ResolvedSpell, amount: Float, caster: ActorValueHolder) {
        guard let world, amount.isFinite, amount > 0 else { return }
        for entry in spell.effects {
            guard let data = entry.effect?.effect.data else { continue }
            guard ActorValueIdentity.isSkill(index: data.magicSkill) else { continue }
            let multiplier = data.skillUsageMultiplier.isFinite
                ? max(0, data.skillUsageMultiplier) : 0
            guard multiplier > 0 else { continue }
            world.reportSkillUse(SkillUseEvent(
                actor: caster.key,
                action: .spellEffect(skill: data.magicSkill),
                amount: amount * multiplier
            ))
        }
    }

    /// The spell's authored base cost, which is what a cast is worth in skill
    /// uses regardless of what the caster was charged.
    public func baseSkillUseAmount(of spell: ResolvedSpell) -> Float {
        Float(spell.cost.cost)
    }
}
