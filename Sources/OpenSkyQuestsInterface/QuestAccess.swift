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

    /// Every quest whose effective state is running, with the key its state is filed
    /// under, in editor-ID order. Papyrus instantiates scripts for this set.
    func runningQuests() -> [(quest: Quest, key: ReferenceKey)]

    /// The seam condition functions read quest state through: this session's
    /// runtime states over the plugin baselines.
    func resolution() -> QuestResolution

    /// Starts the quest, filling its aliases first. A non-optional alias that will
    /// not fill refuses the start. Starting a running quest writes nothing new.
    /// - Throws: `QuestError.aliasFillFailed`; nothing is written then.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func startQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Stops the quest, keeping its stages and completed flag but clearing its
    /// aliases. Stopping a quest that is not running is a no-op.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func stopQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Flags the quest completed and leaves it running, as `CompleteQuest()` does
    /// (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>).
    /// - Throws: `QuestError.questNotRunning` for a quest that is not running.
    /// - Returns: the state as stored afterwards.
    @discardableResult
    func completeQuest(_ id: FormID) throws -> QuestRuntimeState

    /// Records `index` as reached. Setting a lower stage marks it done but keeps the
    /// current stage (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>). A
    /// `startUpStage` starts the quest; a `shutDownStage` stops it afterwards.
    /// - Throws: `QuestError.unknownStage`, or `QuestError.questNotRunning` for a
    ///   stopped quest and a stage that is not a start-up stage.
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

    /// Fills `quest`'s aliases and stores the table, unless a non-optional alias
    /// could not be filled. A second start on a running quest does not refill.
    /// - Throws: `QuestError.aliasFillFailed`; nothing is written then.
    /// - Returns: the table as stored, and why any alias stayed empty.
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
}
