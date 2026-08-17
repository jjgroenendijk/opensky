// Reading an actor's resistance as a fraction (issue #468, roadmap item 19.5):
// the one place the cap and the composition rule live, so items 19.8 and 19.9
// call a function rather than each re-deriving a formula.
//
// ## What a resistance actor value holds
//
// Percentage points. `Resist Fire` 85 means 85% of incoming fire damage is
// removed. MGEF names the value an effect is resisted by in its DATA
// "Resistance Actor Value" field (`MagicEffect.resistanceActorValue`), which is
// why the query below takes an index rather than an enumeration of damage
// types: the record picks the actor value, and any of them may appear.
//
// ## The cap
//
// 85%, and only for the player:
//
//   "Similar to Resist Fire, Resist Frost, and Resist Shock, Resist Magic is
//   capped at 85%. The cap only applies to you; followers and enemies with
//   100% resistance are truly immune."
//   (<https://en.uesp.net/wiki/Skyrim:Resist_Magic>)
//
//   "Resist Poison is capped at 85%; i.e., you cannot gain poison immunity."
//   (<https://en.uesp.net/wiki/Skyrim:Resist_Poison>)
//
// Resist Disease is the exception and is not capped at 85: "Resist Disease 100%
// provides disease immunity ... values above 100% provide no additional
// benefit." (<https://en.uesp.net/wiki/Skyrim:Resist_Disease>)
//
// The cap is an OpenSky constant, not a game setting, and that is a probed fact
// rather than an omission: the local install's whole resolved game-setting
// table carries no resistance cap under any editor ID (2026-08-16,
// `openskycli gmst list` — 1649 settings, the only two matching "resist" are
// the strings `sMagicEffectResisted` and `sNormalWeaponsResisted`). A plugin
// cannot move this number, so it is stated here with its source the way
// `DetectionSettings` states its own constants.
//
// ## The composition rule
//
// Resist Magic and the elemental resistance both apply, multiplicatively, magic
// first: "Damage reduction from Resist Fire, Resist Frost, and Resist Shock is
// applied after damage reduction from Resist Magic ... a 100-point Fire Damage
// spell would deal only 15 points of damage with Resist Magic 85%; Resist Fire
// 85% would then reduce the 15 points by a further 85% to 2.25 points of final
// damage, resulting in 97.75% total resistance."
// (<https://en.uesp.net/wiki/Skyrim:Resist_Magic>)
//
// ## What is deliberately not here
//
// `Damage Resist` (index 39) is an armor rating, not a percentage: UESP's armor
// formula turns it into a damage reduction with its own 80% cap, which the
// install does carry as a game setting (`fMaxArmorRating = 80`). Feeding it to
// a percentage query would read 40 points of armor as 40% resistance, so it is
// rejected here and belongs with the armor formula when that lands.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// The caps a resistance query applies.
nonisolated struct ActorResistanceSettings: Equatable, Sendable {
    /// Largest fraction of damage the *player* may resist through a capped
    /// resistance. 0.85 per the two UESP pages quoted above.
    var playerCapFraction: Float
    /// Largest fraction anyone may resist through an uncapped resistance —
    /// total immunity, which is what a 100% NPC resistance grants.
    var immunityFraction: Float

    static let documentedDefaults = ActorResistanceSettings(
        playerCapFraction: 0.85,
        immunityFraction: 1
    )
}

nonisolated enum ActorResistance {
    /// The resistance actor values that hold a percentage, and are therefore
    /// readable as a fraction by the query below.
    static let percentageIndices: Set<Int32> = [
        ActorValueIndex.poisonResist,
        ActorValueIndex.resistFire,
        ActorValueIndex.resistShock,
        ActorValueIndex.resistFrost,
        ActorValueIndex.resistMagic,
        ActorValueIndex.resistDisease
    ]

    /// Whether `index` names a percentage resistance.
    static func isPercentage(index: Int32) -> Bool {
        percentageIndices.contains(index)
    }

    /// Whether the 85% cap applies to `index`, which every percentage
    /// resistance but disease answers yes to.
    static func isCapped(index: Int32) -> Bool {
        isPercentage(index: index) && index != ActorValueIndex.resistDisease
    }

    /// The fraction of damage `percentagePoints` removes, with the cap for
    /// `index` applied.
    ///
    /// **Negative points are a weakness and pass through negative**, which is
    /// the whole of the weakness mechanic (issue #471): UESP words Weakness to
    /// Fire as "Target is `<mag>`% weaker to fire damage"
    /// (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>) and vanilla authors
    /// it as a detrimental Value Modifier on `Resist Fire`, so a target at -30
    /// points reads -0.3 here and takes 130% damage through the multiplier
    /// below. There is no floor, because no source states one; the cap bounds
    /// the resistant end alone.
    ///
    /// - Parameter isPlayer: whether the actor is the player. The 85% cap
    ///   applies to nobody else, so an atronach's 100% fire resistance really
    ///   is immunity.
    static func fraction(
        percentagePoints: Float,
        at index: Int32,
        isPlayer: Bool,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float {
        guard percentagePoints.isFinite else { return 0 }
        let cap = isPlayer && isCapped(index: index)
            ? settings.playerCapFraction
            : settings.immunityFraction
        return min(percentagePoints / 100, max(0, cap))
    }
}

extension ActorValueRuntime {
    /// The fraction of incoming damage `holder`'s resistance at `index`
    /// removes, capped.
    ///
    /// - Returns: nil when `index` is not a percentage resistance, which
    ///   includes `Damage Resist` and every non-resistance actor value. A
    ///   caller that gets nil has an effect whose resistance the armor formula
    ///   or no formula at all answers, and must not treat it as zero
    ///   resistance without saying so.
    func resistanceFraction(
        at index: Int32,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float? {
        guard
            ActorResistance.isPercentage(index: index),
            let points = value(at: index, on: holder)
        else { return nil }
        return ActorResistance.fraction(
            percentagePoints: points,
            at: index,
            isPlayer: holder.subject == .player,
            settings: settings
        )
    }

    /// What one point of magic damage of `element`'s school is multiplied by
    /// before it reaches `holder`: Resist Magic first, then the element's own
    /// resistance, exactly as UESP states the order.
    ///
    /// - Parameter element: the MGEF's resistance actor value, or nil for an
    ///   effect that names none. A `nil` element still pays Resist Magic, which
    ///   is what makes a school-less magic effect resistible at all.
    /// - Returns: 1 when nothing resists, 0 when the actor is immune, and above
    ///   1 for a weakness — a negative resistance multiplies damage up, and two
    ///   weaknesses compound, which is what UESP's "Weakness to fire is
    ///   strengthened by weakness to magic" describes
    ///   (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>).
    func magicDamageMultiplier(
        element: Int32?,
        on holder: ActorValueHolder,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float {
        let magic = resistanceFraction(
            at: ActorValueIndex.resistMagic,
            on: holder,
            settings: settings
        ) ?? 0
        let elemental = element.flatMap { index -> Float? in
            // Resist Magic is already applied; an effect that names it as its
            // own resistance must not pay it twice.
            guard index != ActorValueIndex.resistMagic else { return nil }
            return resistanceFraction(at: index, on: holder, settings: settings)
        } ?? 0
        return (1 - magic) * (1 - elemental)
    }
}
