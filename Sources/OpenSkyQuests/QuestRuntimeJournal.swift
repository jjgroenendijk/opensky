// What the journal adds to quest state: which quests the player tracks, and the
// misc stats a completion counts. See docs/engine/journal.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

extension QuestRuntime {
    public func isTracked(_ id: FormID) -> Bool {
        guard let key = quests.key(for: id) else { return false }
        return store.component(QuestTrackingState.self, for: key)?.isTracked ?? false
    }

    /// Tracked quests that run, in editor-ID order.
    public func trackedQuests() -> [Quest] {
        runningQuests().compactMap { entry in
            store.component(QuestTrackingState.self, for: entry.key)?.isTracked == true
                ? entry.quest : nil
        }
    }

    public func setTracked(_ id: FormID, _ isTracked: Bool) {
        guard let key = quests.key(for: id) else { return }
        store.set(QuestTrackingState(isTracked: isTracked), for: key)
    }

    /// A journal quest is tracked when it first shows an objective, as a new quest
    /// is in the game. An untracked quest stays untracked.
    func trackOnFirstObjective(_ id: FormID) {
        guard
            let quest = quests.quest(id), quest.kind != .none,
            let key = quests.key(for: id),
            store.component(QuestTrackingState.self, for: key) == nil
        else { return }
        store.set(QuestTrackingState(isTracked: true), for: key)
    }

    /// A journal quest counts once, under "Quests Completed" and its type's stat.
    func countCompletion(of quest: Quest) {
        guard quest.kind != .none else { return }
        store.incrementMiscStat(MiscStats.questsCompleted)
        if let name = MiscStats.completionStat(for: quest.kind) {
            store.incrementMiscStat(name)
        }
    }
}

nonisolated extension MiscStats {
    /// The per-type stat a completion counts. Misc quests count their objectives.
    public static func completionStat(for kind: Quest.Kind) -> String? {
        switch kind {
        case .mainQuest: "Main Quests Completed"
        case .sideQuests: "Side Quests Completed"
        case .companionQuests: "The Companions Quests Completed"
        case .magesGuild: "College of Winterhold Quests Completed"
        case .thievesGuild: "Thieves' Guild Quests Completed"
        case .darkBrotherhood: "The Dark Brotherhood Quests Completed"
        case .civilWar: "Civil War Quests Completed"
        case .daedricQuests: "Daedric Quests Completed"
        case .vampire: "Dawnguard Quests Completed"
        case .dragonborn: "Dragonborn Quests Completed"
        case .none, .miscellaneous, .unknown: nil
        }
    }
}
