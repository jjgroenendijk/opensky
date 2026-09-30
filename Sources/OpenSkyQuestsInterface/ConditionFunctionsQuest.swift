// Quest-state condition functions, each a pure read of the quest seam. An
// undefined quest is `ConditionFailure.unresolvedQuest`, never a throw. Raw
// stored indices from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: 56
// `GetQuestRunning`, 58 `GetStage`, 59 `GetStageDone`, 543 `GetQuestCompleted`.
// Return rules come from the wiki pages cited at each registration.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installQuest(_ registry: inout ConditionFunctionRegistry) {
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
        // (<https://ck.uesp.net/wiki/GetStageDone>) Only visited stages count
        // (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>). A negative or out-of-range
        // stage answers 0.
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
        // (<https://ck.uesp.net/wiki/GetQuestCompleted>) OpenSky implements the patched
        // behavior, not the old always-0 bug.
        registry.register(ConditionFunction(
            index: 543,
            name: "GetQuestCompleted",
            parameter1: .formID
        ) { call in
            Self.questState(call, index: 543).map { Self.isTrue($0.isCompleted) }
        })
    }

    /// The quest parameter 1 names, or the reason it could not be read: a CIS1
    /// override naming no filled alias is `unresolvedParameter`; a FormID naming no
    /// quest is `unresolvedQuest`.
    public static func questState(
        _ call: ConditionCall,
        index: UInt16
    ) -> Result<QuestRuntimeState, ConditionFailure> {
        guard let parameter = call.parameter1 else {
            return .failure(.unresolvedParameter(index))
        }
        return call.quest(parameter.asFormID)
    }
}

nonisolated extension ConditionCall {
    /// Current state of the quest `id` names, or `.unresolvedQuest`.
    public func quest(_ id: FormID) -> Result<QuestRuntimeState, ConditionFailure> {
        guard let state = context.quests.state(for: id) else {
            return .failure(.unresolvedQuest(id))
        }
        return .success(state)
    }
}
