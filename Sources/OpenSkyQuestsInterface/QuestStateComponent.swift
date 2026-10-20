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
    /// The quest defines no alias with this ID.
    case unknownAlias(quest: FormID, alias: UInt32)
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
    /// Set by a stage item's Fail Quest flag. The journal lists the quest as failed.
    public private(set) var isFailed: Bool
    /// The stage whose log entry the journal shows, and the items of it that passed.
    /// "Only the most recent log entry is displayed" (<https://ck.uesp.net/wiki/Quest_Stages_Tab>).
    public private(set) var journalLog: QuestJournalLog?
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
        objectives: [QuestObjectiveState] = [],
        isFailed: Bool = false,
        journalLog: QuestJournalLog? = nil
    ) {
        self.isRunning = isRunning
        self.isCompleted = isCompleted
        self.isFailed = isFailed
        self.journalLog = journalLog
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

    /// This state with the quest flagged failed. Like completing, it does not stop it.
    public func failing() -> Self {
        var result = self
        result.isFailed = true
        return result
    }

    /// Every objective the journal shows, completed ones too, flagged failed
    /// (<https://ck.uesp.net/wiki/FailAllObjectives_-_Quest>).
    public func failingAllObjectives() -> Self {
        var result = self
        result.objectives = objectives.map { objective in
            var failed = objective
            if objective.isDisplayed || objective.isCompleted {
                failed.isFailed = true
            }
            return failed
        }
        return result
    }

    /// The passing stage `items` applied: those with text become the journal's log
    /// entry, any Complete Quest item completes the quest, and any Fail Quest item
    /// fails it and its objectives (<https://ck.uesp.net/wiki/Quest_Stages_Tab>).
    public func applying(_ items: [Int], of stage: Quest.Stage) -> Self {
        let chosen = items.filter(stage.logEntries.indices.contains)
        var state = self
        let written = chosen.filter { stage.logEntries[$0].text != nil }
        if !written.isEmpty {
            state.journalLog = QuestJournalLog(
                stage: stage.index, items: written.map { UInt16(clamping: $0) }
            )
        }
        let flags = chosen.reduce(into: Quest.LogEntry.Flags()) {
            $0.formUnion(stage.logEntries[$1].flags)
        }
        if flags.contains(.completeQuest) {
            state.isCompleted = true
        }
        if flags.contains(.failQuest) {
            state = state.failing().failingAllObjectives()
        }
        return state
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

nonisolated extension Quest.Stage {
    /// The items a stage applies when nothing evaluated their conditions: those with
    /// none, else the first.
    public var defaultItems: [Int] {
        let open = logEntries.indices.filter { logEntries[$0].conditions.isEmpty }
        return open.isEmpty ? Array(logEntries.indices.prefix(1)) : open
    }
}

/// The log entry the journal shows: one stage, and the items of it whose conditions
/// passed, in record order.
nonisolated public struct QuestJournalLog: Equatable, Sendable {
    public let stage: UInt16
    public let items: [UInt16]

    public init(stage: UInt16, items: [UInt16]) {
        self.stage = stage
        self.items = Set(items).sorted()
    }
}

nonisolated extension WorldStateComponentKind {
    /// One quest's running, stage and objective state. Like `spawn` this one does
    /// not modify a placement: it is keyed by a QUST base record's `ReferenceKey`,
    /// the same way `GlobalStore` keys a GLOB override, because a quest is not
    /// placed anywhere and belongs to no cell.
    public static let quest = Self(rawValue: "quest", order: 6, affectsCellBuild: false)
}
