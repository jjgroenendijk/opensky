// What a trainer charges, how often the player may train per level, and the
// refusal notices. UESP "Skyrim:Trainers". See docs/engine/training.md.

import Foundation

nonisolated public struct TrainingSettings: Equatable, Sendable {
    /// `fTrainingMultCost`: gold per skill level for one session.
    public var costMult: Float = 10
    /// `iTrainingExpertCost` and `iTrainingMasterCost`: the cost tier above level
    /// 50 and above 75. Up to 50 the tier is 1.
    public var expertTier = 3
    public var masterTier = 5
    public var cannotTrainAnymoreText = "sCanNotTrainAnymore"
    public var cannotTrainHigherText = "sCanNotTrainHigher"
    public var insufficientGoldText = "sInsufficientGoldToTrain"

    public static let vanilla = Self()
    /// UESP: "You may train up to five times per level." No setting holds it.
    public static let sessionsPerLevel = 5
    /// The constant term of UESP's cost formulas. No setting holds it.
    public static let flatCost: Float = 50

    public init() {}

    /// The gold one session costs at `skillLevel`, the level before training.
    /// UESP gives `n(10b + 5n + 45)` for n sessions; one session is `10b + 50`.
    public func cost(skillLevel: Int) -> Int {
        let level = max(0, skillLevel)
        let tier = level > 75 ? masterTier : (level > 50 ? expertTier : 1)
        let gold = costMult * Float(tier) * Float(level) + Self.flatCost
        return gold.isFinite ? max(0, Int(gold.rounded())) : 0
    }

    /// Why a session is refused, or nil when the player may train.
    public func refusal(
        skillLevel: Int, trainerMaximum: Int, sessionsThisLevel: Int, gold: Int
    ) -> TrainingRefusal? {
        if skillLevel >= trainerMaximum {
            return .trainerLimit
        }
        if sessionsThisLevel >= Self.sessionsPerLevel {
            return .levelUpFirst
        }
        if gold < cost(skillLevel: skillLevel) {
            return .insufficientGold
        }
        return nil
    }

    /// The notice the game shows for `refusal`.
    public func text(for refusal: TrainingRefusal) -> String {
        switch refusal {
        case .trainerLimit: cannotTrainHigherText
        case .levelUpFirst: cannotTrainAnymoreText
        case .insufficientGold: insufficientGoldText
        }
    }

    /// `text` resolves a string setting through the plugin's string table.
    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        store.read("fTrainingMultCost", into: &settings, \.costMult)
        store.read("iTrainingExpertCost", into: &settings, \.expertTier)
        store.read("iTrainingMasterCost", into: &settings, \.masterTier)
        let texts: [(String, WritableKeyPath<Self, String>)] = [
            ("sCanNotTrainAnymore", \.cannotTrainAnymoreText),
            ("sCanNotTrainHigher", \.cannotTrainHigherText),
            ("sInsufficientGoldToTrain", \.insufficientGoldText)
        ]
        for (editorID, keyPath) in texts {
            if let value = store.text(editorID).flatMap({ text($0) }) {
                settings[keyPath: keyPath] = value
            }
        }
        return settings
    }
}

nonisolated public enum TrainingRefusal: Equatable, Sendable {
    case trainerLimit
    case levelUpFirst
    case insufficientGold
}
