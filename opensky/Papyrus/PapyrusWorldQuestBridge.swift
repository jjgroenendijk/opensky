// The quest half of the native-to-world seam (issue #322): what a `Quest`
// native is allowed to ask of the session, and the nonisolated hops the native
// bodies actually call.
//
// It is a protocol of its own that `PapyrusWorldBridge` refines, rather than
// nine more methods on that protocol, for the reason the file split in
// `PapyrusNativeObjectReference*.swift` exists: quests are a subsystem with
// their own vocabulary — stages, objectives, running-ness — and a test that
// only cares about quests should be able to read this list on its own.
//
// Every operation is expressed in `ReferenceKey`, because that is the identity
// a Papyrus handle resolves to. Turning it into the QUST record's FormID is
// `QuestStore`'s job on the far side, so nothing on the script side ever holds
// a load-order-relative number.
//
// Failures are thrown `QuestError`s, exactly as `QuestRuntime` throws them: a
// script asking about a quest this session does not define, or setting a stage
// the record does not declare, gets a native failure it can see in the tally
// rather than a zero it would go on to act upon.

import Foundation

/// Failures the seam itself reports, as opposed to the `QuestError`s the quest
/// layer throws once a quest has been named.
nonisolated enum PapyrusQuestBridgeError: Error, Equatable {
    /// The session has no quest index behind it — a synthetic scene, or an
    /// install whose plugins carry no QUST group. Distinct from
    /// `QuestError.unknownQuest`, which means the index exists and does not
    /// define this quest.
    case noQuestData
}

/// Quest state and mutations a Papyrus native may perform.
@MainActor
protocol PapyrusWorldQuestBridge: AnyObject {
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

/// Nonisolated hops for the quest operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of
/// the check.
nonisolated extension PapyrusWorldAccess {
    func questState(for key: ReferenceKey) throws -> QuestRuntimeState {
        try MainActor.assumeIsolated { try bridge.questState(for: key) }
    }

    @discardableResult
    func startQuest(for key: ReferenceKey) throws -> Bool {
        try MainActor.assumeIsolated { try bridge.startQuest(for: key) }
    }

    func stopQuest(for key: ReferenceKey) throws {
        try MainActor.assumeIsolated { try bridge.stopQuest(for: key) }
    }

    func completeQuest(for key: ReferenceKey) throws {
        try MainActor.assumeIsolated { try bridge.completeQuest(for: key) }
    }

    @discardableResult
    func setQuestStage(_ stage: UInt16, for key: ReferenceKey) throws -> Bool {
        try MainActor.assumeIsolated { try bridge.setQuestStage(stage, for: key) }
    }

    func setQuestObjectiveDisplayed(
        _ objective: UInt16, _ isDisplayed: Bool, for key: ReferenceKey
    ) throws {
        try MainActor.assumeIsolated {
            try bridge.setQuestObjectiveDisplayed(objective, isDisplayed, for: key)
        }
    }

    func setQuestObjectiveCompleted(
        _ objective: UInt16, _ isCompleted: Bool, for key: ReferenceKey
    ) throws {
        try MainActor.assumeIsolated {
            try bridge.setQuestObjectiveCompleted(objective, isCompleted, for: key)
        }
    }

    func setQuestObjectiveFailed(
        _ objective: UInt16, _ isFailed: Bool, for key: ReferenceKey
    ) throws {
        try MainActor.assumeIsolated {
            try bridge.setQuestObjectiveFailed(objective, isFailed, for: key)
        }
    }
}
