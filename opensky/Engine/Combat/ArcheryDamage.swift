// How much health a landed arrow takes off (issue #196, roadmap item 15.5,
// scope point 4).
//
// Two documented pieces, both quoted rather than paraphrased, and both from
// UESP.
//
// ## The bow and the arrow add
//
// "Skyrim:Archery", section "Detailed Bow Comparison":
//
//     The equation to easily work out your potential dps is
//     (bow damage + arrow damage) / time
//
// so a shot's base damage is the WEAP's plus the AMMO's, and the same page's
// discussion of why an imperial bow out-damages a daedric one with dragonbone
// arrows only works on that reading. The skill and perk terms that multiply it
// are the ordinary weapon-damage formula's — "Skyrim:Weapons", Overview:
//
//     displayed damage = Round[ (base damage + smithing increase)
//                               * (1 + skill/200) * (1 + perk effects)
//                               * (1 + item effects) * (1 + potion effect) ... ]
//
// Every one of those multipliers is M18's: there is no Smithing improvement,
// no perk tree and no enchantment in this engine to read them from, and the
// Archery *skill* is in the same position as melee's Block skill — `ActorValues`
// carries health, magicka and stamina only. So they enter here as one
// `bonusMultiplier` defaulting to 1, which is exactly what the formula reduces
// to for a character with none, and the skill enters as a parameter with a
// documented default rather than as a number invented here.
//
// ## A partial draw does less
//
// "Skyrim:Archery", section "Draw Time and Damage Dealt":
//
//     An arrow can deal 35%, between 50% and 100% damage (non-inclusive), or
//     100% damage. With t = the time the attack button is held in frames
//     (1/60 of a second) the % damage dealt is approximately:
//       35% if t < 50 + 12 / (Speed * WeaponSpeedMult)
//       100% if t > 50 + 52 / (Speed * WeaponSpeedMult)
//       (100/80) * (28 + Speed * WeaponSpeedMult * (t - 50))% otherwise
//
// The page marks the middle branch approximate — "the non-35%/100% formula's
// error is typically between -0.1% and +0.2%. This may be due to floor
// functions or rounding errors" — and that caveat is carried here rather than
// smoothed over: `drawFraction(heldSeconds:speed:)` is the page's formula, and
// nothing in this engine claims it is the shipped one to the last decimal.
//
// Note that `Speed` in that formula is the WEAP DNAM speed, and
// `WeaponSpeedMult` is the graph variable 15.4 already writes from it. With no
// separate multiplier applied they are the same number, so the two collapse to
// one `speed` argument, and a caller with a real multiplier passes the product.
//
// Nothing here reaches the world and nothing here throws. It is arithmetic,
// which is what makes "verify the damage combination" a unit test.
//
// Documented in docs/engine/archery.md.

import Foundation

/// One resolved shot's damage accounting, kept whole so a readout can explain
/// a number rather than just show it.
nonisolated struct ArcheryDamageResult: Equatable, Sendable {
    /// WEAP base damage.
    let bowDamage: Float
    /// AMMO base damage.
    let arrowDamage: Float
    /// The draw-time fraction, `0...1`.
    let drawFraction: Float
    /// What actually comes off health.
    let applied: Float

    /// The two base damages before the draw term, which is what the weapon
    /// sheet in vanilla shows.
    var combinedBase: Float {
        bowDamage + arrowDamage
    }
}

nonisolated enum ArcheryDamage {
    /// The Archery skill a character with no skill table is assumed to have.
    /// UESP "Skyrim:Archery" gives 15 as the starting value for a race with no
    /// Archery bonus; the real per-actor number arrives with the rest of the
    /// actor-value table in M18. The same reasoning and the same default as
    /// `MeleeDamage.defaultBlockSkill`.
    static let defaultArcherySkill: Float = 15

    /// The lowest fraction a released shot can deal, from the page's first
    /// branch.
    static let minimumDrawFraction: Float = 0.35

    /// Frames per second the draw-time formula is written in. The page states
    /// it in frames and says "to calculate using seconds, replace t by 60t".
    static let drawFormulaFrameRate: Float = 60

    /// What one landed arrow takes off the target's health.
    ///
    /// - Parameters:
    ///   - bowDamage: WEAP base damage of the bow that fired it.
    ///   - arrowDamage: AMMO base damage of the arrow.
    ///   - drawFraction: the draw-time term, `0...1`. 1 is a full draw.
    ///   - skill: the shooter's Archery skill.
    ///   - bonusMultiplier: the perk, enchantment and potion terms folded into
    ///     one. 1 for a character with none, which is every character in this
    ///     milestone.
    static func resolve(
        bowDamage: Float,
        arrowDamage: Float,
        drawFraction: Float = 1,
        skill: Float = defaultArcherySkill,
        bonusMultiplier: Float = 1
    ) -> ArcheryDamageResult {
        let bow = clamp(bowDamage)
        let arrow = clamp(arrowDamage)
        let draw = min(max(clamp(drawFraction), 0), 1)
        let skillTerm = 1 + clamp(skill) / 200
        let bonus = bonusMultiplier.isFinite ? max(0, bonusMultiplier) : 1
        let applied = (bow + arrow) * draw * skillTerm * bonus
        return ArcheryDamageResult(
            bowDamage: bow,
            arrowDamage: arrow,
            drawFraction: draw,
            applied: applied.isFinite ? max(0, applied) : 0
        )
    }

    /// The draw-time fraction for a shot released after `heldSeconds`, from
    /// UESP's three-branch formula.
    ///
    /// - Parameters:
    ///   - heldSeconds: how long the attack button was held.
    ///   - speed: WEAP DNAM `speed` times any weapon-speed multiplier. A
    ///     non-positive or non-finite value falls back to 1, which is the
    ///     multiplier a weapon with no speed data would have had anyway.
    static func drawFraction(heldSeconds: Float, speed: Float) -> Float {
        let scale = speed.isFinite && speed > 0 ? speed : 1
        let frames = heldSeconds.isFinite ? max(0, heldSeconds) * drawFormulaFrameRate : 0
        let lower = 50 + 12 / scale
        let upper = 50 + 52 / scale
        if frames < lower {
            return minimumDrawFraction
        }
        if frames > upper {
            return 1
        }
        let percent = (100 / 80) * (28 + scale * (frames - 50))
        return min(max(percent / 100, minimumDrawFraction), 1)
    }

    private static func clamp(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}
