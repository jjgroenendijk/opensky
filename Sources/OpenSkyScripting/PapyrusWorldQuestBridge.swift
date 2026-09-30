// The quest half of the native-to-world seam, in `ReferenceKey` terms;
// `QuestStore` maps keys to FormIDs. Failures are thrown `QuestError`s, which
// the tally shows.

import Foundation
import OpenSkyFormatsESM
import OpenSkyQuestsInterface

/// Failures the seam itself reports, as opposed to the `QuestError`s the quest
/// layer throws once a quest has been named.
nonisolated public enum PapyrusQuestBridgeError: Error, Equatable {
    /// The session has no quest index behind it — a synthetic scene, or an
    /// install whose plugins carry no QUST group. Distinct from
    /// `QuestError.unknownQuest`, which means the index exists and does not
    /// define this quest.
    case noQuestData
}

/// Quest state and mutations a Papyrus native may perform.
@MainActor
public protocol PapyrusWorldQuestBridge: AnyObject, Sendable {
    /// Effective state of the quest `key` names: its runtime component when it
    /// has one, its plugin baseline when it does not.
    func questState(for key: ReferenceKey) throws -> QuestRuntimeState

    /// Starts the quest. Starting one that already runs is a no-op.
    ///
    /// - Returns: true when the quest is running afterwards, which is the
    ///   `bool Function Start()` return value.
    @discardableResult
    func startQuest(for key: ReferenceKey) throws -> Bool

    /// Stops the quest and retires its script instances.
    func stopQuest(for key: ReferenceKey) throws

    /// Flags the quest completed, leaving it running.
    func completeQuest(for key: ReferenceKey) throws

    /// Sets one stage and runs that stage's fragments.
    ///
    /// - Returns: true when the stage was set, which is
    ///   `bool Function SetCurrentStageID(int)`'s return value.
    @discardableResult
    func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool

    /// Shows or hides one journal objective.
    func setQuestObjectiveDisplayed(
        _ objective: UInt16, _ isDisplayed: Bool, for key: ReferenceKey
    ) throws

    /// Flags one objective completed, or clears that flag.
    func setQuestObjectiveCompleted(
        _ objective: UInt16, _ isCompleted: Bool, for key: ReferenceKey
    ) throws

    /// Flags one objective failed, or clears that flag.
    func setQuestObjectiveFailed(
        _ objective: UInt16, _ isFailed: Bool, for key: ReferenceKey
    ) throws
}
