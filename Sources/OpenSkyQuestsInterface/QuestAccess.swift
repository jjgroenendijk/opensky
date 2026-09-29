// The seam scripts and the journal menu reach quests through. `QuestRuntime`
// conforms, and the composition root hands it over as this protocol.

import OpenSkyFormatsESM
import OpenSkyGameData

/// Quest stages, objectives, and aliases over the world-state store.
@MainActor
public protocol QuestAccess {
    /// Plugin-side index every mutation validates against and takes its
    /// session-stable keys from.
    var quests: QuestStore { get }

    /// The quest's effective state: its runtime component when it has one, its
    /// re-derived plugin baseline when it does not.
    ///
    /// - Throws: `QuestError.unknownQuest` when no loaded plugin defines it,
    ///   `QuestError.unresolvedQuestKey` when its FormID does not resolve.
    func state(of id: FormID) throws -> QuestRuntimeState

    /// Every quest whose effective state is running — runtime states over
    /// plugin baselines — paired with the key its state is filed under, in
    /// editor-ID order.
    ///
    /// This is the set the Papyrus side instantiates scripts for (issue #322):
    /// at session wire-up it is the start-game-enabled quests, and after a
    /// save is restored it is whatever that save recorded.
    func runningQuests() -> [(quest: Quest, key: ReferenceKey)]

    /// The seam condition functions read quest state through: this session's
    /// runtime states over the plugin baselines.
    func resolution() -> QuestResolution

    /// Starts the quest, filling its aliases first. Starting one that already
    /// runs is a no-op that still materializes nothing new, because the write
    /// is skipped when the state is unchanged.
    ///
    /// The alias fill comes first and can refuse the start outright: a quest
    /// whose non-optional alias will not fill "will fail to start" (issue
    /// #183, `QuestAliasFiller`), and a half-started quest whose scripts hold
    /// empty aliases is the state that rule exists to prevent.
    ///
    /// - Throws: `QuestError.aliasFillFailed` when a non-optional alias stayed
    ///   empty, in which case neither the table nor the running flag is written.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func startQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Stops the quest, keeping its reached stages and its completed flag:
    /// stopping is not resetting. Its alias table is *not* kept — an alias is a
    /// live pointer into the world, and the Creation Kit fills one only while
    /// the quest runs. Stopping a quest that is not running is a no-op rather
    /// than a failure — unlike the mutations that only mean something while it
    /// runs, "stop this" is already satisfied.
    ///
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func stopQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Flags the quest completed, leaving it running: `CompleteQuest()` is
    /// documented as flagging completion and nothing else
    /// (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>). A quest is usually
    /// stopped afterwards by a shut-down stage.
    ///
    /// - Throws: `QuestError.questNotRunning` for a quest that is not running.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func completeQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Records `index` as reached.
    ///
    /// Idempotent per the documented `IsStageDone` semantics: setting a stage
    /// that was already reached changes nothing, and setting a stage lower than
    /// the current one leaves the current stage where it was while making the
    /// lower stage report done
    /// (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>).
    ///
    /// Stage record flags are honoured because they are plain record data: a
    /// stage flagged `startUpStage` starts the quest, which is also the only way
    /// a stage may be set on a quest that is not running, and one flagged
    /// `shutDownStage` stops it afterwards. A stage index may legally appear
    /// more than once in a QUST, so the flags of every matching stage are
    /// unioned rather than taken from the first.
    ///
    /// - Throws: `QuestError.unknownStage` when the quest defines no such
    ///   stage, `QuestError.questNotRunning` when it is not running and the
    ///   stage is not a start-up stage.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setStage(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState

    /// Shows or hides one objective in the journal.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveDisplayed(
        _ index: UInt16,
        _ isDisplayed: Bool,
        on id: FormID
    ) throws -> QuestRuntimeState

    /// Flags one objective completed, or clears that flag.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveCompleted(
        _ index: UInt16,
        _ isCompleted: Bool,
        on id: FormID
    ) throws -> QuestRuntimeState

    /// Flags one objective failed, or clears that flag.
    ///
    /// - Throws: `QuestError.unknownObjective`, `QuestError.questNotRunning`.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func setObjectiveFailed(
        _ index: UInt16,
        _ isFailed: Bool,
        on id: FormID
    ) throws -> QuestRuntimeState

    /// Filled aliases of the quest `id` names. An untouched or stopped quest
    /// reads as the empty table rather than as nil, exactly as an untouched
    /// objective reads as all-false.
    ///
    /// - Throws: `QuestError.unknownQuest`, `QuestError.unresolvedQuestKey`.
    func aliasState(of id: FormID) throws -> QuestAliasState

    /// The seam conditions read alias fills through, built the same way
    /// `resolution()` builds the quest-state seam.
    func aliasResolution() -> QuestAliasResolution

    /// Fills `quest`'s aliases and stores the table, unless a non-optional
    /// alias could not be filled.
    ///
    /// Idempotent for a quest whose table is already non-empty: the Creation
    /// Kit fills on the transition into running, so a second `Start` on a
    /// running quest must not re-point aliases its scripts are already holding.
    ///
    /// - Throws: `QuestError.aliasFillFailed` when a non-optional alias stayed
    ///   empty, in which case nothing is written.
    /// - Returns: the table as stored, and the reasons any alias stayed empty.
    @discardableResult
    func fillAliases(of quest: Quest, key: ReferenceKey) throws -> QuestAliasFillResult
}

extension QuestAccess {
    /// Shows one objective in the journal.
    @discardableResult
    public func setObjectiveDisplayed(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState {
        try setObjectiveDisplayed(index, true, on: id)
    }

    /// Flags one objective completed.
    @discardableResult
    public func setObjectiveCompleted(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState {
        try setObjectiveCompleted(index, true, on: id)
    }

    /// Flags one objective failed.
    @discardableResult
    public func setObjectiveFailed(_ index: UInt16, on id: FormID) throws -> QuestRuntimeState {
        try setObjectiveFailed(index, true, on: id)
    }
}
