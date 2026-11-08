// Fakes for the perk and progression coordinator suites. Every answer is a
// stored value and every call is recorded.

import OpenSkyActorsInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface

@MainActor
final class FakeProgressionWorld: PerkWorld, ProgressionWorld {
    var residents: [ReferenceKey: ActorValueHolder] = [:]
    var worn = WornArmorProfile.none
    /// What the player's active magic effects grant.
    var effectPerks: Set<ReferenceKey> = []
    private(set) var changeCount = 0
    private(set) var reconciled: [ReferenceKey] = []
    private(set) var wornArmorReads: [ReferenceKey] = []
    private(set) var questStages: [QuestStageSet] = []

    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder? {
        key == .player ? .player : residents[key]
    }

    func actorValue(at _: Int32, on _: ActorValueHolder) -> Float? {
        nil
    }

    func perksChanged(_: PerkRuntime) {
        changeCount += 1
    }

    func perksFromActiveEffects(on holder: ActorValueHolder) -> Set<ReferenceKey> {
        holder.key == .player ? effectPerks : []
    }

    func setPerkQuestStage(_ stage: UInt16, quest: FormID, fromPlugin plugin: String) {
        questStages.append(QuestStageSet(stage: stage, quest: quest, plugin: plugin))
    }

    func reconcileAbilities(on holder: ActorValueHolder, perks _: PerkRuntime) {
        reconciled.append(holder.key)
    }

    func wornArmor(of key: ReferenceKey) -> WornArmorProfile {
        wornArmorReads.append(key)
        return worn
    }

    func conditionContext() -> ConditionContext {
        ConditionContext()
    }

    func conditionText(_ condition: Condition) -> String {
        "function \(condition.functionIndex)"
    }

    var trainer: TrainerOffer?
    var gold = 0
    private(set) var paid: [Int] = []

    func nearestTrainer() -> TrainerOffer? {
        trainer
    }

    func playerGold() -> Int {
        gold
    }

    func payTrainer(_ amount: Int, to _: ReferenceKey) -> Bool {
        guard gold >= amount else { return false }
        gold -= amount
        paid.append(amount)
        return true
    }
}

/// One quest stage a perk set.
struct QuestStageSet {
    let stage: UInt16
    let quest: FormID
    let plugin: String
}
