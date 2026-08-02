// Quest-state condition functions (issue #182), split out of
// `ConditionFunctions` the way `ConditionFunctionsTime` is.
//
// These four were the top of the #251 demand list waiting on quests to exist,
// and they are honest to register now that `QuestRuntimeState` holds the state
// they read: each is a pure read of the quest seam on `ConditionContext`, with
// no world, no clock and no reference needed. A QUST parameter naming a quest
// nothing defines is a reason-tagged `ConditionFailure.unresolvedQuest` and a
// `ConditionTally` bucket, never a throw and never a comparison against zero.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. They come from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, whose
// condition-function table lists:
//
//   (Index:  56; Name: 'GetQuestRunning'; ParamType1: ptQuest)
//   (Index:  58; Name: 'GetStage'; ParamType1: ptQuest)
//   (Index:  59; Name: 'GetStageDone'; ParamType1: ptQuest; ParamType2: ptQuestStage)
//   (Index: 543; Name: 'GetQuestCompleted'; ParamType1: ptQuest)
//
// Return semantics come from the Creation Kit wiki's condition-function pages,
// cited at each registration.

import Foundation

nonisolated extension ConditionFunctions {
    static func installQuest(_ registry: inout ConditionFunctionRegistry) {
        // "Gets the highest completed quest stage. For example, if stages 10,
        // 30, and 75 were completed, GetStage would return 75."
        // (<https://ck.uesp.net/wiki/GetStage>) A quest that has reached no
        // stage returns 0, which `QuestRuntimeState.stageValue` spells.
        registry.register(ConditionFunction(
            index: 58,
            name: "GetStage",
            parameter1: .formID
        ) { call in
            Self.questState(call, index: 58).map { Float($0.stageValue) }
        })

        // "Returns 1 if the specified stage has been completed, 0 otherwise."
        // (<https://ck.uesp.net/wiki/GetStageDone>) "Done" means explicitly
        // visited, so a lower stage is never implied by a higher one
        // (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>).
        //
        // Parameter 2 is `ptQuestStage`, an integer stage index rather than a
        // FormID. A negative or out-of-range value cannot name a stage — stage
        // indices are uint16 on disk — so it answers 0 rather than failing:
        // "no such stage has been done" is a real answer, not a coverage gap.
        registry.register(ConditionFunction(
            index: 59,
            name: "GetStageDone",
            parameter1: .formID,
            parameter2: .integer
        ) { call in
            guard let stage = call.parameter2 else {
                return .failure(.unresolvedParameter(59))
            }
            return Self.questState(call, index: 59).map { state in
                guard let index = UInt16(exactly: stage.asInt32) else { return 0 }
                return Self.isTrue(state.isStageDone(index))
            }
        })

        // "Returns 1 if the quest if currently running, 0 if it is not."
        // (<https://ck.uesp.net/wiki/GetQuestRunning>)
        registry.register(ConditionFunction(
            index: 56,
            name: "GetQuestRunning",
            parameter1: .formID
        ) { call in
            Self.questState(call, index: 56).map { Self.isTrue($0.isRunning) }
        })

        // "Returns 0 if a quest has not yet been completed, 1 if it has."
        // (<https://ck.uesp.net/wiki/GetQuestCompleted>) The same page records
        // that the original engine returned 0 unconditionally until patch
        // 1.9.32; OpenSky implements the fixed behaviour, so a plugin authored
        // around the bug — the page suggests `GetStageDone` on the last stage
        // instead — still evaluates correctly, while one that relied on the
        // broken return does not. That trade is deliberate: reproducing a
        // documented, patched bug would make every correct condition wrong.
        registry.register(ConditionFunction(
            index: 543,
            name: "GetQuestCompleted",
            parameter1: .formID
        ) { call in
            Self.questState(call, index: 543).map { Self.isTrue($0.isCompleted) }
        })
    }

    /// The quest parameter 1 names, or the reason it could not be read.
    ///
    /// Two different failures live here and stay distinct: a CIS1 name override
    /// means the parameter itself is unreadable (`unresolvedParameter`, since
    /// the alias table is not resolved yet), while a readable FormID that names
    /// no quest is `unresolvedQuest`.
    static func questState(
        _ call: ConditionCall,
        index: UInt16
    ) -> Result<QuestRuntimeState, ConditionFailure> {
        guard let parameter = call.parameter1 else {
            return .failure(.unresolvedParameter(index))
        }
        return call.quest(parameter.asFormID)
    }
}
