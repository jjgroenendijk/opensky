// How an NPC rates a spell for a fight: each effect scores through a fixed table of
// archetype, actor value, hostility, and delivery, and the spell scores their sum.
// See docs/engine/ai-spell-use.md#how-the-game-rates-a-spell.

import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public enum NPCSpellRating {
    /// One row of the game's rating table.
    struct Entry: Equatable {
        let archetypes: Set<UInt32>
        /// The primary actor value the row needs, or nil for any.
        let actorValue: Int32?
        let hostile: Bool
        let targetsSelf: Bool
        let weight: Float
        /// True: the row rates the magnitude; false: the effect's cost.
        let usesMagnitude: Bool
    }

    /// One spell effect, as the rating reads it.
    struct RatedEffect: Equatable {
        var archetype: UInt32 = 0
        var actorValue: Int32 = -1
        var secondActorValue: Int32 = -1
        var secondActorValueWeight: Float = 0
        var hostile = false
        var noMagnitude = false
        var noDuration = false
        var magnitude: Float = 0
        var duration: Float = 0
        var cost: Float = 0
        var taperWeight: Float = 0
        var taperDuration: Float = 0
        var scriptAIScore: Float = 0
    }

    /// Value modifier rows also cover absorb, dual value modifier, accumulate
    /// magnitude, and peak value modifier.
    static let valueModifiers: Set<UInt32> = [0, 4, 5, 32, 34]
    static let script: UInt32 = 1
    static let dualValueModifier: UInt32 = 5
    /// `fCombatMagicConcentrationScoreDuration`.
    static let concentrationDuration: Float = 3
    /// `fCombatRangedDistance`: a spell that reaches farther scores
    /// `fCombatInventoryRangedScoreMult` (2) times as much.
    static let rangedDistance: Float = 1024
    static let rangedScoreMultiplier: Float = 2

    static let table: [Entry] = [
        row(valueModifiers, 24, 1, [.hostile]),
        row(valueModifiers, 25, 0.5, [.hostile]),
        row(valueModifiers, 26, 0.33, [.hostile]),
        row([33], nil, 10, [.hostile]),
        row([9], nil, 10, [.hostile]),
        row([10], nil, 10, [.hostile]),
        row([42], 1, 5, [.hostile]),
        row([24], 1, 3, [.hostile]),
        row([21], 53, 20, [.hostile, .ratesCost]),
        row([1], nil, 1, [.hostile, .ratesCost]),
        row(valueModifiers, 24, 1, [.targetsSelf]),
        row(valueModifiers, 25, 0.33, [.targetsSelf]),
        row(valueModifiers, 26, 0.1, [.targetsSelf]),
        row(valueModifiers, 63, 1, [.targetsSelf]),
        row([18], nil, 1, [.targetsSelf, .ratesCost]),
        row([18], nil, 1, [.ratesCost]),
        row([35], nil, 1, [.targetsSelf]),
        row([12], nil, 1, [.targetsSelf, .ratesCost]),
        row([11], 54, 1, [.targetsSelf, .ratesCost]),
        row([17], nil, 1, [.targetsSelf, .ratesCost]),
        row(valueModifiers, 39, 1, [.targetsSelf]),
        row([22], nil, 10, []),
        row([1], nil, 1, [.targetsSelf, .ratesCost])
    ]

    /// What a row matches on, and whether it rates the effect's cost.
    struct RowFlags: OptionSet {
        let rawValue: UInt8
        static let hostile = Self(rawValue: 1)
        static let targetsSelf = Self(rawValue: 2)
        static let ratesCost = Self(rawValue: 4)
    }

    private static func row(
        _ archetypes: Set<UInt32>, _ actorValue: Int32?, _ weight: Float, _ flags: RowFlags
    ) -> Entry {
        Entry(
            archetypes: archetypes, actorValue: actorValue, hostile: flags.contains(.hostile),
            targetsSelf: flags.contains(.targetsSelf), weight: weight,
            usesMagnitude: !flags.contains(.ratesCost)
        )
    }

    /// The score the choice compares: the sum of the effect scores, twice as much for a
    /// spell that reaches past `rangedDistance`. The target's resistances are left out.
    public static func score(of spell: ResolvedSpell, range: Float) -> Float {
        let targetsSelf = spell.data?.delivery == .selfTarget
        let concentration = spell.data?.castingType == .concentration
        let total = spell.effects.compactMap(rated).reduce(0) { total, effect in
            total + score(of: effect, targetsSelf: targetsSelf, concentration: concentration)
        }
        return range > rangedDistance ? total * rangedScoreMultiplier : total
    }

    static func rated(_ effect: ResolvedSpellEffect) -> RatedEffect? {
        guard let data = effect.effect?.effect.data else { return nil }
        return RatedEffect(
            archetype: data.archetype.number,
            actorValue: data.relatedActorValue,
            secondActorValue: data.secondActorValue,
            secondActorValueWeight: data.secondActorValueWeight,
            hostile: data.flags.contains(.hostile),
            noMagnitude: data.flags.contains(.noMagnitude),
            noDuration: data.flags.contains(.noDuration),
            magnitude: effect.item.magnitude,
            duration: Float(effect.item.duration),
            cost: effect.cost,
            taperWeight: data.taperWeight,
            taperDuration: data.taperDuration,
            scriptAIScore: data.scriptAIScore
        )
    }

    /// One effect, and a dual value modifier's second actor value beside it.
    static func score(of effect: RatedEffect, targetsSelf: Bool, concentration: Bool) -> Float {
        let delivery = (targetsSelf: targetsSelf, concentration: concentration)
        var total = part(effect, actorValue: effect.actorValue, share: 1, delivery: delivery)
        if effect.archetype == dualValueModifier {
            total += part(
                effect, actorValue: effect.secondActorValue,
                share: effect.secondActorValueWeight, delivery: delivery
            )
        }
        return total.isFinite ? total : 0
    }

    private static func part(
        _ effect: RatedEffect, actorValue: Int32, share: Float,
        delivery: (targetsSelf: Bool, concentration: Bool)
    ) -> Float {
        guard let entry = table.first(where: {
            $0.archetypes.contains(effect.archetype) && $0.hostile == effect.hostile
                && $0.targetsSelf == delivery.targetsSelf
                && ($0.actorValue.map { $0 == actorValue } ?? true)
        }) else { return 0 }
        if effect.archetype == script {
            return effect.scriptAIScore * entry.weight
        }
        let magnitude = effect.noMagnitude ? 0 : effect.magnitude
        let value = (entry.usesMagnitude ? magnitude : effect.cost) * share
        return value * duration(of: effect, concentration: delivery.concentration) * entry.weight
    }

    /// Concentration counts as 3 s; otherwise the duration, at least 1, plus half the
    /// taper for an effect with both a duration and a magnitude.
    static func duration(of effect: RatedEffect, concentration: Bool) -> Float {
        guard !concentration else { return concentrationDuration }
        var seconds = max(effect.duration, 1)
        if !effect.noDuration, !effect.noMagnitude {
            seconds += effect.taperDuration * effect.taperWeight * 0.5
        }
        return seconds
    }
}
