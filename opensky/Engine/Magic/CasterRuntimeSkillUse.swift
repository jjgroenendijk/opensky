// What casting teaches the caster (issue #498, roadmap item 20.5).
//
// A satellite of `CasterRuntime` so that type stays under the strict-lint body
// cap, and along a real seam: everything in the parent decides whether a cast
// happens and what it costs, and this is the one thing a cast that already
// happened hands to progression.
//
// ## Per effect, not per spell
//
// The Creation Kit states both halves of this on the MGEF: "Magic Skill: The
// Skill associated with the effect. The skill can modify the Power, Duration,
// or Cost of the effect, and will accumulate Skill Uses from it", and "Skill
// Usage Mult: For Spells, a multiplier to the Skill Uses (which feed into
// advancing the effect's Magic Skill, above) that casting this effect will give
// the player" (<https://ck.uesp.net/wiki/Magic_Effect>).
//
// So the unit that accumulates skill uses is the effect, not the spell, and a
// spell whose effects name two schools feeds both. The base amount is the
// spell's own magicka cost — "Base Magicka Cost of the Spell"
// (<https://en.uesp.net/wiki/Skyrim:Leveling>) — before any perk discount, so a
// perk that halves what a spell costs does not halve what it teaches.
//
// A maintained cast reports what it actually drained in that step instead,
// which is the same page's reading of a spell paid for by the second ("1 base
// XP per Magicka used on non-healing spells").
//
// Documented in docs/engine/skill-advancement.md and docs/engine/magic.md.

import Foundation

extension CasterRuntime {
    /// Reports one cast's skill uses, one per effect that names a magic skill.
    ///
    /// - Parameters:
    ///   - amount: the magicka the use is measured in — the spell's authored
    ///     base cost for a fire-and-forget cast, the magicka drained for one
    ///     step of a maintained one.
    func noteSkillUse(of spell: ResolvedSpell, amount: Float, caster: ActorValueHolder) {
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
    func baseSkillUseAmount(of spell: ResolvedSpell) -> Float {
        Float(spell.cost.cost)
    }
}
