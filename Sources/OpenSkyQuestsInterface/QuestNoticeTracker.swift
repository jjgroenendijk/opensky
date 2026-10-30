// The quest changes the HUD announces: a quest's first shown objective starts it, a new
// objective is shown, and a quest completes or fails. It compares quest states between
// frames. See docs/engine/journal.md#hud-notices.

import Foundation
import OpenSkyFormatsESM

/// One quest change the HUD shows.
nonisolated public enum QuestNotice: Equatable, Sendable {
    case started(FormID)
    case objectiveShown(FormID, objective: UInt16)
    case completed(FormID)
    case failed(FormID)

    public var quest: FormID {
        switch self {
        case let .started(id), let .objectiveShown(id, _), let .completed(id), let .failed(id):
            id
        }
    }
}

nonisolated public struct QuestNoticeTracker: Equatable, Sendable {
    private var known: [FormID: QuestRuntimeState] = [:]
    private var primed = false

    public init() {}

    /// The changes since the last call, in quest order. The first call only records,
    /// so a loaded save announces nothing.
    public mutating func notices(
        in states: [(quest: Quest, state: QuestRuntimeState)]
    ) -> [QuestNotice] {
        var notices: [QuestNotice] = []
        var next: [FormID: QuestRuntimeState] = [:]
        for (quest, state) in states {
            next[quest.formID] = state
            guard primed, quest.kind != .none, known[quest.formID] != state else { continue }
            notices += Self.changes(
                of: quest, from: known[quest.formID] ?? .baseline(for: quest), to: state
            )
        }
        known = next
        primed = true
        return notices
    }

    /// Forgets every quest, so the next call only records. A load calls it.
    public mutating func reset() {
        known = [:]
        primed = false
    }

    static func changes(
        of quest: Quest, from old: QuestRuntimeState, to new: QuestRuntimeState
    ) -> [QuestNotice] {
        let id = quest.formID
        if new.isFailed, !old.isFailed {
            return [.failed(id)]
        }
        if new.isCompleted, !old.isCompleted {
            return [.completed(id)]
        }
        let shown = Set(old.objectives.filter(\.isDisplayed).map(\.index))
        let added = new.objectives.filter { $0.isDisplayed && !shown.contains($0.index) }
        guard !added.isEmpty else { return [] }
        // A misc quest has no row of its own, so only its objective shows.
        let starts = shown.isEmpty && quest.kind != .miscellaneous && !new.isCompleted
        return (starts ? [.started(id)] : []) + added
            .map { .objectiveShown(id, objective: $0.index) }
    }
}
