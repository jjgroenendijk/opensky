// The alchemy rules, pure: which effects two or three ingredients share, how strong
// the skill and the perks make each one, and what the result is worth. Formulas from
// UESP "Skyrim:Alchemy" (<https://en.uesp.net/wiki/Skyrim:Alchemy>) and
// "Skyrim:Alchemy Effects" (<https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>).
// See docs/engine/alchemy.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The alchemy game settings.
nonisolated public struct AlchemySettings: Equatable, Sendable {
    /// `fAlchemySkillFactor` 1.5 is in Skyrim.esm. `fAlchemyIngredientInitMult` is not,
    /// so its engine default 4 (UESP "Skyrim:Alchemy") applies.
    public static let vanilla = AlchemySettings(
        skillFactor: 1.5, ingredientMultiplier: 4, failedSkillUse: 5
    )

    public let skillFactor: Float
    public let ingredientMultiplier: Float
    /// `fWortFailSkillUseMagnitude`: the skill use a failed brew still gives.
    public let failedSkillUse: Float

    public init(skillFactor: Float, ingredientMultiplier: Float, failedSkillUse: Float) {
        self.skillFactor = skillFactor.isFinite ? skillFactor : Self.vanilla.skillFactor
        self.ingredientMultiplier = ingredientMultiplier.isFinite
            ? ingredientMultiplier : Self.vanilla.ingredientMultiplier
        self.failedSkillUse = failedSkillUse.isFinite ? max(0, failedSkillUse) : 0
    }

    public static func resolve(store: GameSettingStore) -> AlchemySettings {
        AlchemySettings(
            skillFactor: float("fAlchemySkillFactor", in: store) ?? vanilla.skillFactor,
            ingredientMultiplier: float("fAlchemyIngredientInitMult", in: store)
                ?? vanilla.ingredientMultiplier,
            failedSkillUse: float("fWortFailSkillUseMagnitude", in: store)
                ?? vanilla.failedSkillUse
        )
    }

    private static func float(_ name: String, in store: GameSettingStore) -> Float? {
        guard
            let resolved = store.setting(editorID: name),
            case let .float(value) = resolved.setting.value
        else { return nil }
        return value
    }
}

/// One carried ingredient as the rules see it.
nonisolated public struct AlchemyIngredient: Equatable, Sendable {
    public let id: FormID
    public let effects: [MagicItemEffect]

    public init(id: FormID, effects: [MagicItemEffect]) {
        self.id = id
        self.effects = effects
    }
}

/// One effect two or more chosen ingredients share.
nonisolated public struct AlchemySharedEffect: Equatable, Sendable {
    public let effect: ResolvedMagicEffect
    /// The entry of the ingredient whose version costs most, which the brew uses.
    public let entry: MagicItemEffect
    /// Each sharing ingredient and the index of this effect in its list.
    public let sources: [FormID: Int]
}

/// One effect of a brew, after the skill and the perks.
nonisolated public struct AlchemyBrewedEffect: Equatable, Sendable {
    public let effect: ResolvedMagicEffect
    public let result: CreatedPotionEffect
    /// The gold the effect adds to the value.
    public let cost: Float
}

/// What brewing the chosen ingredients makes.
nonisolated public struct AlchemyBrew: Equatable, Sendable {
    /// Costliest first, so the first one names the result.
    public let effects: [AlchemyBrewedEffect]
    public let isPoison: Bool
    public let value: Int32
    /// The value at the skill alone, without perks or Fortify Alchemy, which the
    /// skill use counts.
    public let skillValue: Float
    /// What brewing teaches: each ingredient and the indices of its shared effects.
    public let learned: [FormID: [Int]]

    public var primary: AlchemyBrewedEffect? {
        effects.first
    }

    public var createdEffects: [CreatedPotionEffect] {
        effects.map(\.result)
    }
}

/// What the perks of the brewer say about one brew.
nonisolated public struct AlchemyPerks {
    /// Mod Alchemy Effectiveness for one effect, as a multiplier.
    public let effectiveness: (ResolvedMagicEffect, _ isPoison: Bool) -> Float
    /// Purify Alchemy Ingredients: a potion keeps only its good effects, a poison its bad.
    public let purifies: Bool

    public static var none: AlchemyPerks {
        AlchemyPerks(effectiveness: { _, _ in 1 }, purifies: false)
    }

    public init(
        effectiveness: @escaping (ResolvedMagicEffect, Bool) -> Float,
        purifies: Bool
    ) {
        self.effectiveness = effectiveness
        self.purifies = purifies
    }
}

nonisolated public enum AlchemyRules {
    /// The effects at least two of `ingredients` list, in the order they first appear.
    public static func shared(
        _ ingredients: [AlchemyIngredient],
        resolve: (FormID) -> ResolvedMagicEffect?
    ) -> [AlchemySharedEffect] {
        var order: [ResolvedFormID] = []
        var found: [ResolvedFormID: AlchemySharedEffect] = [:]
        for ingredient in ingredients {
            for (index, entry) in ingredient.effects.enumerated() {
                guard let effect = resolve(entry.effect) else { continue }
                guard let known = found[effect.id] else {
                    order.append(effect.id)
                    found[effect.id] = AlchemySharedEffect(
                        effect: effect, entry: entry, sources: [ingredient.id: index]
                    )
                    continue
                }
                var sources = known.sources
                sources[ingredient.id] = sources[ingredient.id] ?? index
                let stronger = baseCost(of: entry, effect) > baseCost(of: known.entry, effect)
                found[effect.id] = AlchemySharedEffect(
                    effect: effect, entry: stronger ? entry : known.entry, sources: sources
                )
            }
        }
        return order.compactMap { found[$0] }.filter { $0.sources.count >= 2 }
    }

    /// `fAlchemyIngredientInitMult * (1 + (fAlchemySkillFactor - 1) * skill / 100)`.
    /// Fortify Alchemy is not added here: the `AlchemySkillBoosts` and `PerkSkillBoosts`
    /// perks apply it through Mod Alchemy Effectiveness.
    public static func powerFactor(skill: Float, settings: AlchemySettings) -> Float {
        settings.ingredientMultiplier * (1 + (settings.skillFactor - 1) * max(0, skill) / 100)
    }

    /// One entry at `power`. Power scales only what the MGEF flags let it scale.
    public static func scaled(
        _ entry: MagicItemEffect, _ effect: ResolvedMagicEffect, power: Float
    ) -> CreatedPotionEffect {
        let flags = effect.effect.data?.flags ?? []
        var magnitude = entry.magnitude
        var duration = Float(entry.duration)
        if flags.contains(.powerAffectsMagnitude) {
            magnitude = (magnitude * power).rounded()
        }
        if flags.contains(.powerAffectsDuration) {
            duration = (duration * power).rounded()
        }
        if flags.contains(.noMagnitude) {
            magnitude = 0
        }
        if flags.contains(.noDuration) {
            duration = 0
        }
        return CreatedPotionEffect(
            effect: entry.effect,
            magnitude: magnitude,
            area: entry.area,
            duration: UInt32(clamping: Int(max(0, duration)))
        )
    }

    /// `floor(BaseCost * (magnitudeFactor * durationFactor) ^ 1.1)`, where a zero
    /// magnitude counts as 1 and the duration counts in tens of seconds.
    public static func cost(of result: CreatedPotionEffect, _ effect: ResolvedMagicEffect)
        -> Float
    {
        let baseCost = effect.effect.data?.baseCost ?? 0
        let magnitude = result.magnitude > 0 ? result.magnitude : 1
        let duration = result.duration > 0 ? Float(result.duration) / 10 : 1
        return (baseCost * pow(magnitude * duration, 1.1)).rounded(.down)
    }

    /// Brews `ingredients`, or nil when they share no effect.
    public static func brew(
        _ ingredients: [AlchemyIngredient],
        resolve: (FormID) -> ResolvedMagicEffect?,
        power: Float,
        perks: AlchemyPerks
    ) -> AlchemyBrew? {
        let shared = shared(ingredients, resolve: resolve)
        let ranked = shared.map { pick in
            (pick, cost(of: scaled(pick.entry, pick.effect, power: power), pick.effect))
        }
        guard let strongest = ranked.max(by: { $0.1 < $1.1 }) else { return nil }
        let isPoison = isHostile(strongest.0.effect)
        let kept = perks.purifies
            ? shared.filter { isHostile($0.effect) == isPoison } : shared
        let effects = kept.map { pick in
            let boosted = power * perks.effectiveness(pick.effect, isPoison)
            let result = scaled(pick.entry, pick.effect, power: boosted)
            return AlchemyBrewedEffect(
                effect: pick.effect, result: result, cost: cost(of: result, pick.effect)
            )
        }.sorted { $0.cost > $1.cost }
        let skillValue = kept.reduce(Float(0)) { total, pick in
            total + cost(of: scaled(pick.entry, pick.effect, power: power), pick.effect)
        }
        return AlchemyBrew(
            effects: effects,
            isPoison: isPoison,
            value: Int32(clamping: Int(effects.reduce(Float(0)) { $0 + $1.cost })),
            skillValue: skillValue,
            learned: learned(from: shared)
        )
    }

    public static func isHostile(_ effect: ResolvedMagicEffect) -> Bool {
        effect.effect.data?.flags.contains(.hostile) == true
    }

    private static func baseCost(of entry: MagicItemEffect, _ effect: ResolvedMagicEffect)
        -> Float
    {
        cost(of: scaled(entry, effect, power: 1), effect)
    }

    private static func learned(from shared: [AlchemySharedEffect]) -> [FormID: [Int]] {
        var learned: [FormID: [Int]] = [:]
        for pick in shared {
            for (ingredient, index) in pick.sources {
                learned[ingredient, default: []].append(index)
            }
        }
        return learned.mapValues { $0.sorted() }
    }
}
