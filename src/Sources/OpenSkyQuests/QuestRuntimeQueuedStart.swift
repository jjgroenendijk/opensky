// The start a script asks for: the request waits in a queue, and the quest fills
// its aliases, resets, and runs its start-up stages on later frames.
// See docs/engine/quest-state.md, "Starting a quest".

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyQuestsInterface
import OpenSkyWorldState

/// The cached list behind `pendingStarts()`.
private struct QuestPendingStartList {
    let starts: [QuestPendingStart]
}

extension QuestRuntime {
    @discardableResult
    public func queueStart(
        _ id: FormID, stage: UInt16?, objective: UInt16?
    ) throws -> QuestRuntimeState {
        let next = (pendingStarts().map(\.start.order).max() ?? 0) &+ 1
        return try change(id) { $0.queueingStart(order: next, stage: stage, objective: objective) }
    }

    public func pendingStarts() -> [QuestPendingStart] {
        store.derived(QuestPendingStartList.self, from: quests) {
            var found: [QuestPendingStart] = []
            for entry in runtimeQuests() where entry.state.start.phase != .idle {
                guard let key = quests.key(for: entry.quest.formID) else { continue }
                found.append(QuestPendingStart(
                    quest: entry.quest, key: key, start: entry.state.start
                ))
            }
            return QuestPendingStartList(starts: found.sorted { $0.start.order < $1.start.order })
        }.starts
    }

    @discardableResult
    public func prepareStart(_ id: FormID) throws -> QuestRuntimeState {
        guard let quest = quests.quest(id) else { throw QuestError.unknownQuest(id) }
        guard let key = quests.key(for: id) else { throw QuestError.unresolvedQuestKey(id) }
        do {
            try fillAliases(of: quest, key: key, event: nil)
        } catch {
            clearAliases(key: key)
            _ = try change(id) { $0.cancellingStart() }
            throw error
        }
        return try change(id) { $0.preparedForStart() }
    }

    @discardableResult
    public func beginStartUp(_ id: FormID) throws -> QuestRuntimeState {
        try change(id) { $0.startingUp() }
    }

    @discardableResult
    public func finishStart(_ id: FormID) throws -> QuestRuntimeState {
        try change(id) { $0.finishingStart() }
    }

    private func change(
        _ id: FormID, _ body: (QuestRuntimeState) -> QuestRuntimeState
    ) throws -> QuestRuntimeState {
        guard quests.quest(id) != nil else { throw QuestError.unknownQuest(id) }
        guard let key = quests.key(for: id) else { throw QuestError.unresolvedQuestKey(id) }
        let updated = try body(state(of: id))
        store.set(updated, for: key)
        return updated
    }
}
