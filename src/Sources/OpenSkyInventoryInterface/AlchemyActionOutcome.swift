import Foundation

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
    /// `discovered` names the effects the brew taught.
    case brewed(count: Int32, item: String, value: Int32, discovered: [String])
    case failed(String)
    case learned(ingredient: String, effects: [String])
    case poisoned(weapon: String, poison: String, doses: Int32)
    case noWeapon
    case alreadyPoisoned
    case cannotPoison
    case notAPoison(String)
    case brewFailed(reason: String)
}
