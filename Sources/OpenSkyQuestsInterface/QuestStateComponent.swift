// One quest's running, stage, and objective state as a world-state component,
// keyed by the QUST record's `ReferenceKey`. An untouched quest has no component.
// The stage rules from the Creation Kit wiki are in docs/engine/quest-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// Display state of one quest objective, by QOBJ index. The three flags are
/// independent, like the `SetObjectiveDisplayed`, `SetObjectiveCompleted`, and
/// `SetObjectiveFailed` natives (<https://ck.uesp.net/wiki/SetObjectiveDisplayed_-_Quest>).
nonisolated public struct QuestObjectiveState: Equatable, Sendable {
    /// QOBJ index this state belongs to.
    public let index: UInt16
    /// Shown in the journal.
    public var isDisplayed: Bool
    public var isCompleted: Bool
    public var isFailed: Bool

    public init(
        index: UInt16,
        isDisplayed: Bool = false,
        isCompleted: Bool = false,
        isFailed: Bool = false
    ) {
        self.index = index
        self.isDisplayed = isDisplayed
        self.isCompleted = isCompleted
        self.isFailed = isFailed
    }

    /// True when nothing has touched this objective, which is the state a quest
    /// implicitly gives every objective it defines.
    public var isUntouched: Bool {
        !isDisplayed && !isCompleted && !isFailed
    }
}

/// Failures the quest layer reports. Each is a caller mistake, so it throws
/// rather than clamps.
nonisolated public enum QuestError: Error, Equatable {
    /// No loaded plugin defines a QUST with this FormID.
    case unknownQuest(FormID)
    /// The QUST record exists but its FormID does not resolve to a
    /// session-stable `ReferenceKey`, so there is nowhere to key state.
    case unresolvedQuestKey(FormID)
    /// The quest defines no stage with this index.
    case unknownStage(quest: FormID, stage: UInt16)
    /// The quest defines no objective with this index.
    case unknownObjective(quest: FormID, objective: UInt16)
    /// A mutation that only means something on a running quest.
    case questNotRunning(FormID)
    /// The quest could not start because a non-optional alias stayed empty; carries
    /// the alias IDs in list order (<https://ck.uesp.net/wiki/Alias>). An alias
    /// empty because OpenSky lacks its fill type is not reported here; see
    /// `QuestAliasFiller`.
    case aliasFillFailed(quest: FormID, aliases: [UInt32])
}

/// Everything the runtime records about one quest.
nonisolated public struct QuestRuntimeState: WorldStateComponent, Sendable {
    /// Whether the quest is running. A quest that has been stopped is not
    /// running even if it was completed first.
    public private(set) var isRunning: Bool
    public private(set) var isCompleted: Bool
    /// Stage indices ever reached, sorted ascending and unique.
    public private(set) var stagesReached: [UInt16]
    /// Objectives whose display state deviates from untouched, sorted by index.
    public private(set) var objectives: [QuestObjectiveState]

    /// A quest nothing has started: the baseline of every quest whose DNAM does
    /// not say start-game-enabled.
    public static let dormant = QuestRuntimeState()

    public static var componentKind: WorldStateComponentKind {
        .quest
    }

    /// Normalizes on the way in: the reached stages come out sorted and unique,
    /// duplicate objective entries collapse with the last one winning, and an
    /// untouched objective drops out. This initializer is also the save
    /// decoder's entry point, so a corrupt file degrades into a valid state
    /// rather than failing the whole load.
    public init(
        isRunning: Bool = false,
        isCompleted: Bool = false,
        stagesReached: [UInt16] = [],
        objectives: [QuestObjectiveState] = []
    ) {
        self.isRunning = isRunning
        self.isCompleted = isCompleted
        self.stagesReached = Set(stagesReached).sorted()
        var byIndex: [UInt16: QuestObjectiveState] = [:]
        for objective in objectives where !objective.isUntouched {
            byIndex[objective.index] = objective
        }
        self.objectives = byIndex.keys.sorted().compactMap { byIndex[$0] }
    }

    /// The state a quest has before anything touches it. Only DNAM
    /// `startGameEnabled` feeds it; the completed and failed bits are authoring
    /// state. See docs/engine/quest-state.md.
    public static func baseline(for quest: Quest) -> QuestRuntimeState {
        QuestRuntimeState(isRunning: quest.flags.contains(.startGameEnabled))
    }

    // MARK: - Reading

    /// Highest stage ever reached, or nil when the quest has reached none.
    ///
    /// Callers that need the `GetStage` return value use `stageValue`, which
    /// spells the "no stage reached" case as 0 the way the condition function
    /// does.
    public var currentStage: UInt16? {
        stagesReached.last
    }

    /// `GetStage`'s return value: the highest stage reached, and 0 for a quest
    /// that has reached none. A quest that has genuinely reached stage 0 is
    /// indistinguishable from one that has reached nothing, which is also true
    /// of the function this mirrors.
    public var stageValue: UInt16 {
        currentStage ?? 0
    }

    /// Whether `index` was explicitly visited. A lower stage is never implied by
    /// a higher one (`IsStageDone`).
    public func isStageDone(_ index: UInt16) -> Bool {
        stagesReached.contains(index)
    }

    /// Display state of one objective; an objective nothing has touched reads as
    /// all-false rather than as nil.
    public func objective(_ index: UInt16) -> QuestObjectiveState {
        objectives.first { $0.index == index } ?? QuestObjectiveState(index: index)
    }

    // MARK: - Mutating

    /// This state with the quest running.
    public func starting() -> Self {
        var result = self
        result.isRunning = true
        return result
    }

    /// This state with the quest no longer running. The reached stages and the
    /// completed flag survive, because stopping a quest is not the same as
    /// resetting it.
    public func stopping() -> Self {
        var result = self
        result.isRunning = false
        return result
    }

    /// This state with the quest flagged completed. `CompleteQuest()` does not
    /// stop a quest, so the running flag stays.
    public func completing() -> Self {
        var result = self
        result.isCompleted = true
        return result
    }

    /// This state with `index` recorded as reached. Reaching a stage twice
    /// changes nothing, and reaching a lower stage never lowers `currentStage`.
    public func reachingStage(_ index: UInt16) -> Self {
        guard !stagesReached.contains(index) else { return self }
        var result = self
        result.stagesReached = (stagesReached + [index]).sorted()
        return result
    }

    public func settingObjectiveDisplayed(_ index: UInt16, _ isDisplayed: Bool) -> Self {
        updatingObjective(index) { $0.isDisplayed = isDisplayed }
    }

    public func settingObjectiveCompleted(_ index: UInt16, _ isCompleted: Bool) -> Self {
        updatingObjective(index) { $0.isCompleted = isCompleted }
    }

    public func settingObjectiveFailed(_ index: UInt16, _ isFailed: Bool) -> Self {
        updatingObjective(index) { $0.isFailed = isFailed }
    }

    // MARK: - Private

    /// Applies `change` to one objective and re-normalizes, which is what drops
    /// an entry whose last flag was just cleared.
    private func updatingObjective(
        _ index: UInt16,
        _ change: (inout QuestObjectiveState) -> Void
    ) -> Self {
        var updated = objective(index)
        change(&updated)
        var result = self
        result.objectives = objectives.filter { $0.index != index }
        if !updated.isUntouched {
            let position = result.objectives.firstIndex { $0.index > index }
            result.objectives.insert(updated, at: position ?? result.objectives.endIndex)
        }
        return result
    }
}

nonisolated extension WorldStateComponentKind {
    /// One quest's running, stage and objective state. Like `spawn` this one does
    /// not modify a placement: it is keyed by a QUST base record's `ReferenceKey`,
    /// the same way `GlobalStore` keys a GLOB override, because a quest is not
    /// placed anywhere and belongs to no cell.
    public static let quest = Self(rawValue: "quest", order: 6)
}
