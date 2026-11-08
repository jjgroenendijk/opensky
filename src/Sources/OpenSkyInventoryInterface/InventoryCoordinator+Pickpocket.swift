import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// What one pickpocket take did.
nonisolated public enum PickpocketOutcome: Equatable, Sendable {
    case took(item: String, chance: Int)
    case placed(item: String, chance: Int)
    /// The Poisoned perk: a placed poison lands on the target instead.
    case poisoned(item: String, chance: Int)
    /// The roll failed: the target noticed and the crime was reported.
    case caught(item: String, chance: Int, bounty: Int32)
    /// An equipped item needs a Can Pickpocket Equipped Item perk.
    case equipped(String)
    case failed(String)
    case unavailable

    public var wasCaught: Bool {
        if case .caught = self {
            return true
        }
        return false
    }
}
