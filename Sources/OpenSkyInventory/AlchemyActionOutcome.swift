// What one alchemy action did, as a readout line. The game's own notices come from
// `AlchemyTexts`, read from the load order's strings.

import Foundation

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

    public init(potionPrefix: String, poisonPrefix: String, failed: String) {
        self.potionPrefix = potionPrefix
        self.poisonPrefix = poisonPrefix
        self.failed = failed
    }

    /// The made item's name: the prefix and the name of its costliest effect.
    public func name(isPoison: Bool, effect: String) -> String {
        let prefix = (isPoison ? poisonPrefix : potionPrefix)
            .trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? effect : "\(prefix) \(effect)"
    }
}

nonisolated public enum AlchemyActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noLab
    case notAnIngredient(String)
    case noneCarried(String)
    case tooMany(limit: Int)
    case picked(String, preview: String)
    case dropped(String, preview: String)
    case cleared
    case needsTwo
    case brewed(count: Int32, item: String, value: Int32)
    case failed(String)
    case learned(ingredient: String, effects: [String])
    case poisoned(weapon: String, poison: String, doses: Int32)
    case noWeapon
    case notAPoison(String)
    case brewFailed(reason: String)

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
        case let .brewed(count, item, value): "Made \(count) × \(item), worth \(value) gold."
        case let .failed(text): text
        case let .learned(ingredient, effects) where effects.isEmpty:
            "Ate \(ingredient): no new effect learned."
        case let .learned(ingredient, effects):
            "Ate \(ingredient): learned \(effects.joined(separator: ", "))."
        case let .poisoned(weapon, poison, doses):
            "Applied \(poison) to \(weapon): \(doses) hit(s)."
        case .noWeapon: "No weapon is drawn to poison."
        case let .notAPoison(name): "\(name) is no poison."
        case let .brewFailed(reason): "Brew failed: \(reason)"
        }
    }
}
