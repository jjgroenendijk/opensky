// Quest runtime state as a world-state component (issue #182, roadmap item
// 13.2): the value type that holds one quest's running, stage and objective
// state once anything has touched it.
//
// The component lives here rather than in `WorldStateComponents.swift` for the
// same reason `ReferenceInventoryState` lives beside the inventory code: it
// carries behaviour of its own — the reached-stage set and the objective table —
// rather than being a plain field bag. Only the `WorldStateComponentKind` case
// and the `WorldStateComponentValue` case sit with the rest, so every store
// operation stays generic over the protocol.
//
// Quests are base records rather than placed references, which the store does
// not care about: state is keyed by the QUST record's session-stable
// `ReferenceKey`, exactly as `GlobalStore` keys GLOB overrides, so journalling,
// snapshot ordering and the mutation callbacks apply unchanged.
//
// Full-override model, like inventory: an untouched quest has no component at
// all and re-derives its baseline from plugin data through `baseline(for:)`; the
// first mutation materializes that baseline and everything afterwards edits it.
//
// Two invariants hold for every value of this type, enforced in `init` rather
// than checked at use sites, because they are what make a snapshot of two
// stores that reached the same end state byte-identical:
//
// * `stagesReached` is sorted ascending and free of duplicates.
// * `objectives` is sorted by objective index, holds one entry per index, and
//   never holds an entry whose three flags are all false — that is the state an
//   objective has before anything touches it, so storing it would make two
//   equal worlds compare unequal.
//
// Documented semantics, from the Creation Kit wiki rather than from memory:
//
//   "Current stage" is the *highest* stage ever reached, not the last one set.
//   `GetCurrentStageID` "obtains the highest completed stage in this quest", and
//   the condition function `GetStage` documents the same rule by example: with
//   stages 10, 30 and 75 reached it returns 75 "even when stage 30 is completed
//   after stage 75".
//   (<https://ck.uesp.net/wiki/GetCurrentStageID_-_Quest>,
//   <https://ck.uesp.net/wiki/GetStage>)
//
//   A stage is "done" only if it was explicitly visited. `IsStageDone` "returns
//   false for stages 10, 30 and 50" after setting 0, 40, 20 and 60, "because
//   these stages have not yet been visited" — a lower-numbered stage is not
//   implied by a higher one. That is why the reached set is a set rather than a
//   high-water mark. (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>)
//
//   Setting a stage twice is idempotent for this state: the stage is already in
//   the reached set and the highest reached stage cannot move backwards, so
//   `SetStage(30)` after stage 60 leaves `GetCurrentStageID` at 60 and only
//   turns `IsStageDone(30)` true. (Same page.)
//
//   `CompleteQuest()` "flags this quest as completed" and says nothing about
//   stopping it, so completing leaves the running flag alone here.
//   (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>)
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// Display state of one quest objective, addressed by its QOBJ index.
///
/// The three flags are independent on disk and in Papyrus:
/// `SetObjectiveDisplayed`, `SetObjectiveCompleted` and `SetObjectiveFailed` are
/// three separate natives, each taking its own Bool, and none of them clears
/// another (<https://ck.uesp.net/wiki/SetObjectiveDisplayed_-_Quest> and
/// siblings). They are modelled the same way here.
nonisolated struct QuestObjectiveState: Equatable, Sendable {
    /// QOBJ index this state belongs to.
    let index: UInt16
    /// Shown in the journal.
    var isDisplayed: Bool
    var isCompleted: Bool
    var isFailed: Bool

    init(
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
    var isUntouched: Bool {
        !isDisplayed && !isCompleted && !isFailed
    }
}

/// Failures the quest layer reports.
///
/// Every one of them is a caller mistake rather than malformed input, which is
/// why they are distinct from `ESMError`, and every one is a thrown failure
/// rather than a clamp: a script that sets a stage the quest does not define has
/// a bug, and silently recording it would hide the bug behind a quest that never
/// advances.
nonisolated enum QuestError: Error, Equatable {
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
}

/// Everything the runtime records about one quest.
nonisolated struct QuestRuntimeState: WorldStateComponent {
    /// Whether the quest is running. A quest that has been stopped is not
    /// running even if it was completed first.
    private(set) var isRunning: Bool
    private(set) var isCompleted: Bool
    /// Stage indices ever reached, sorted ascending and unique.
    private(set) var stagesReached: [UInt16]
    /// Objectives whose display state deviates from untouched, sorted by index.
    private(set) var objectives: [QuestObjectiveState]

    /// A quest nothing has started: the baseline of every quest whose DNAM does
    /// not say start-game-enabled.
    static let dormant = QuestRuntimeState()

    static var componentKind: WorldStateComponentKind {
        .quest
    }

    var erased: WorldStateComponentValue {
        .quest(self)
    }

    /// Normalizes on the way in: the reached stages come out sorted and unique,
    /// duplicate objective entries collapse with the last one winning, and an
    /// untouched objective drops out. This initializer is also the save
    /// decoder's entry point, so a corrupt file degrades into a valid state
    /// rather than failing the whole load.
    init(
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

    init?(erased: WorldStateComponentValue) {
        guard case let .quest(value) = erased else { return nil }
        self = value
    }

    /// The state a quest has before anything touches it.
    ///
    /// Only the DNAM `startGameEnabled` flag feeds the baseline. The `completed`
    /// and `failed` bits in the same field are authoring state the Creation Kit
    /// writes about the quest's design, not about a session, so a fresh game
    /// starts every quest uncompleted; see docs/engine/runtime-state.md for the
    /// vanilla start machinery this v1 leaves out.
    static func baseline(for quest: Quest) -> QuestRuntimeState {
        QuestRuntimeState(isRunning: quest.flags.contains(.startGameEnabled))
    }

    // MARK: - Reading

    /// Highest stage ever reached, or nil when the quest has reached none.
    ///
    /// Callers that need the `GetStage` return value use `stageValue`, which
    /// spells the "no stage reached" case as 0 the way the condition function
    /// does.
    var currentStage: UInt16? {
        stagesReached.last
    }

    /// `GetStage`'s return value: the highest stage reached, and 0 for a quest
    /// that has reached none. A quest that has genuinely reached stage 0 is
    /// indistinguishable from one that has reached nothing, which is also true
    /// of the function this mirrors.
    var stageValue: UInt16 {
        currentStage ?? 0
    }

    /// Whether `index` was explicitly visited. A lower stage is never implied by
    /// a higher one (see the file header).
    func isStageDone(_ index: UInt16) -> Bool {
        stagesReached.contains(index)
    }

    /// Display state of one objective; an objective nothing has touched reads as
    /// all-false rather than as nil.
    func objective(_ index: UInt16) -> QuestObjectiveState {
        objectives.first { $0.index == index } ?? QuestObjectiveState(index: index)
    }

    /// True when the state still equals the plugin baseline for `quest`, which
    /// is what makes a reset back to plugin data meaningful.
    func matchesBaseline(of quest: Quest) -> Bool {
        self == Self.baseline(for: quest)
    }

    // MARK: - Mutating

    /// This state with the quest running.
    func starting() -> Self {
        var result = self
        result.isRunning = true
        return result
    }

    /// This state with the quest no longer running. The reached stages and the
    /// completed flag survive, because stopping a quest is not the same as
    /// resetting it.
    func stopping() -> Self {
        var result = self
        result.isRunning = false
        return result
    }

    /// This state with the quest flagged completed, leaving the running flag
    /// alone (see the file header).
    func completing() -> Self {
        var result = self
        result.isCompleted = true
        return result
    }

    /// This state with `index` recorded as reached. Reaching a stage twice
    /// changes nothing, and reaching a lower stage never lowers `currentStage`.
    func reachingStage(_ index: UInt16) -> Self {
        guard !stagesReached.contains(index) else { return self }
        var result = self
        result.stagesReached = (stagesReached + [index]).sorted()
        return result
    }

    func settingObjectiveDisplayed(_ index: UInt16, _ isDisplayed: Bool) -> Self {
        updatingObjective(index) { $0.isDisplayed = isDisplayed }
    }

    func settingObjectiveCompleted(_ index: UInt16, _ isCompleted: Bool) -> Self {
        updatingObjective(index) { $0.isCompleted = isCompleted }
    }

    func settingObjectiveFailed(_ index: UInt16, _ isFailed: Bool) -> Self {
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
