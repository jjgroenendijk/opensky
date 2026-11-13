// What one alchemy action did, as a readout line. The game's own notices come from
// `AlchemyTexts`, read from the load order's strings.

import Foundation
import OpenSkyGameData
public import OpenSkyInventoryInterface

/// The game strings alchemy shows. The fallbacks are OpenSky's wording.
nonisolated public struct AlchemyTexts: Equatable, Sendable {
    public static let vanilla = AlchemyTexts(
        potionPrefix: "Potion of", poisonPrefix: "Poison of",
        failed: "You failed to create a potion."
    )

    /// `sCreatedPotionNamePrefix`.
    public let potionPrefix: String
    /// `sCreatedPoisonNamePrefix`.
    public let poisonPrefix: String
    /// `sPotionCreationFailed`.
    public let failed: String
    /// `sCreated`, before the made item.
    public var created = "Created"
    /// `sDiscoveredEffects`, the heading of the effects a brew taught.
    public var discoveredEffects = "Discovered effects"
    /// `sDiscoveredIngredientEffectEating`: `%s` is the effect, then the ingredient.
    public var discoveredByEating = "Discovered %s in %s"

    public init(potionPrefix: String, poisonPrefix: String, failed: String) {
        self.potionPrefix = potionPrefix
        self.poisonPrefix = poisonPrefix
        self.failed = failed
    }

    /// The brew notice: `<sCreated> (<count>) <name>` for more than one, then the effects
    /// the brew taught under `<sDiscoveredEffects>:`.
    public func brewText(count: Int32, name: String, discovered: [String]) -> String {
        let made = count > 1 ? "\(created) (\(count)) \(name)" : "\(created) \(name)"
        guard !discovered.isEmpty else { return made }
        return ([made, "\(discoveredEffects):"] + discovered).joined(separator: "\n")
    }

    /// One HUD notice per effect that eating `ingredient` taught.
    public func eatingNotices(ingredient: String, effects: [String]) -> [String] {
        effects.map { SettingTextFormat.fill(discoveredByEating, [$0, ingredient]) }
    }

    /// The made item's name: the prefix and the name of its costliest effect.
    public func name(isPoison: Bool, effect: String) -> String {
        let prefix = (isPoison ? poisonPrefix : potionPrefix)
            .trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? effect : "\(prefix) \(effect)"
    }
}

nonisolated extension AlchemyActionOutcome {
    public var text: String {
        switch self {
        case .idle: "No alchemy action yet."
        case .unavailable: InventoryCore.noRuntimeText
        case .noLab: "No alchemy lab is open."
        case let .notAnIngredient(name): "\(name) is no ingredient."
        case let .noneCarried(name): "The player carries no \(name)."
        case let .tooMany(limit): "A potion takes at most \(limit) ingredients."
        case let .picked(name, preview): "Added \(name). \(preview)"
        case let .dropped(name, preview): "Removed \(name). \(preview)"
        case .cleared: "Cleared the chosen ingredients."
        case .needsTwo: "Choose at least two ingredients."
        case let .brewed(count, item, value, _): "Made \(count) × \(item), worth \(value) gold."
        case let .failed(text): text
        case let .learned(ingredient, effects) where effects.isEmpty:
            "Ate \(ingredient): no new effect learned."
        case let .learned(ingredient, effects):
            "Ate \(ingredient): learned \(effects.joined(separator: ", "))."
        case let .poisoned(weapon, poison, doses):
            "Applied \(poison) to \(weapon): \(doses) hit(s)."
        case .noWeapon: PoisonText.noWeapon.fallback
        case .alreadyPoisoned: PoisonText.alreadyPoisoned.fallback
        case .cannotPoison: PoisonText.cannotPoison.fallback
        case let .notAPoison(name): "\(name) is no poison."
        case let .brewFailed(reason): "Brew failed: \(reason)"
        }
    }
}
