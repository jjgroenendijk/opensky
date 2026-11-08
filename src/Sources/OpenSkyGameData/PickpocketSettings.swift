// The pickpocket chance, from UESP "Skyrim:Pickpocket": both skills, the gold or the
// weight taken, and a penalty when the target sees the thief, clamped to the minimum
// and maximum. Values are the defaults on <https://ck.uesp.net/wiki/Category:Settings>.
// See docs/engine/pickpocket.md.

import Foundation

nonisolated public struct PickpocketSettings: Equatable, Sendable {
    public var actorSkillBase: Float = 20
    public var actorSkillMult: Float = 1
    public var targetSkillBase: Float = 20
    public var targetSkillMult: Float = -0.25
    public var amountBase: Float = 0
    public var amountMult: Float = -0.1
    public var weightBase: Float = 0
    public var weightMult: Float = -4
    public var detectedPenalty: Float = 25
    public var minimumChance: Float = 0
    public var maximumChance: Float = 90

    public static let vanilla = PickpocketSettings()

    public init() {}

    public static func resolve(store: GameSettingStore) -> PickpocketSettings {
        var settings = vanilla
        store.read("fPickPocketActorSkillBase", into: &settings, \.actorSkillBase)
        store.read("fPickPocketActorSkillMult", into: &settings, \.actorSkillMult)
        store.read("fPickPocketTargetSkillBase", into: &settings, \.targetSkillBase)
        store.read("fPickPocketTargetSkillMult", into: &settings, \.targetSkillMult)
        store.read("fPickPocketAmountBase", into: &settings, \.amountBase)
        store.read("fPickPocketAmountMult", into: &settings, \.amountMult)
        store.read("fPickPocketWeightBase", into: &settings, \.weightBase)
        store.read("fPickPocketWeightMult", into: &settings, \.weightMult)
        store.read("fPickPocketDetected", into: &settings, \.detectedPenalty)
        store.read("fPickPocketMinChance", into: &settings, \.minimumChance)
        store.read("fPickPocketMaxChance", into: &settings, \.maximumChance)
        return settings
    }

    /// The chance in percent before perks. `gold` is the coins taken, zero for an item.
    public func baseChance(_ attempt: PickpocketAttempt) -> Float {
        var chance = (actorSkillBase + attempt.thiefSkill) * actorSkillMult
            + (targetSkillBase + attempt.targetSkill) * targetSkillMult
        chance += amountBase + Float(attempt.gold) * amountMult
        chance += weightBase + attempt.weight * weightMult
        if attempt.detected {
            chance -= detectedPenalty
        }
        return chance.isFinite ? chance : minimumChance
    }

    /// `chance` after perks, held between the two limits.
    public func clamped(_ chance: Float) -> Float {
        guard chance.isFinite else { return minimumChance }
        return min(maximumChance, max(minimumChance, chance))
    }
}

/// One take from a living actor's pocket.
nonisolated public struct PickpocketAttempt: Equatable, Sendable {
    public var thiefSkill: Float
    public var targetSkill: Float
    public var gold: Int32
    /// The whole weight taken.
    public var weight: Float
    public var detected: Bool

    public init(
        thiefSkill: Float, targetSkill: Float, gold: Int32 = 0, weight: Float = 0,
        detected: Bool = false
    ) {
        self.thiefSkill = thiefSkill
        self.targetSkill = targetSkill
        self.gold = gold
        self.weight = weight
        self.detected = detected
    }
}
