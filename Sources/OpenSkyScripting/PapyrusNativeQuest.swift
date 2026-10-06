// The `Quest` native family. The receiver resolves to the QUST record's
// `ReferenceKey`, and each native is one `PapyrusWorldBridge` call; `QuestRuntime`
// owns the stage and objective rules. Both the native and the `Quest.psc`
// wrapper names are registered, because either can arrive.
//
// Documented in docs/engine/papyrus-quests.md, with the natives left out on purpose.

import Foundation
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installQuest(into registry: inout PapyrusNativeRegistry) {
        installQuestReads(into: &registry)
        installQuestRunState(into: &registry)
        installQuestStages(into: &registry)
        installQuestObjectives(into: &registry)
    }

    /// `bool IsRunning()`, `bool IsCompleted()`, `int GetCurrentStageID()` and
    /// `bool IsStageDone(int aiStage)`, with their wrapper spellings. Each is
    /// answered by `QuestRuntimeState`
    /// (<https://ck.uesp.net/wiki/GetCurrentStageID_-_Quest>).
    private static func installQuestReads(
        into registry: inout PapyrusNativeRegistry
    ) {
        register(&registry, ["IsRunning"]) { _, state in
            .returned(.boolean(state.isRunning))
        }
        register(&registry, ["IsCompleted"]) { _, state in
            .returned(.boolean(state.isCompleted))
        }
        register(&registry, ["GetCurrentStageID", "GetStage"]) { _, state in
            .returned(.integer(Int32(state.stageValue)))
        }
        register(&registry, ["IsStageDone", "GetStageDone"]) { call, state in
            guard let stage = stageArgument(call, at: 0) else {
                return failure(call, "\(call.functionName) needs a stage index")
            }
            return .returned(.boolean(state.isStageDone(stage)))
        }
    }

    /// `bool Start()`, `Stop()` and `CompleteQuest()`
    /// (<https://ck.uesp.net/wiki/Start_-_Quest>). Only `Start` returns a value.
    private static func installQuestRunState(
        into registry: inout PapyrusNativeRegistry
    ) {
        registerMutation(&registry, ["Start"]) { _, world, key in
            try .returned(.boolean(world.startQuest(for: key)))
        }
        registerMutation(&registry, ["Stop"]) { _, world, key in
            try world.stopQuest(for: key)
            return .returned(.none)
        }
        registerMutation(&registry, ["CompleteQuest"]) { _, world, key in
            try world.completeQuest(for: key)
            return .returned(.none)
        }
    }

    /// `bool SetCurrentStageID(int aiStage)` and its `SetStage` wrapper
    /// (<https://ck.uesp.net/wiki/SetStage_-_Quest>). An unknown stage is a native
    /// failure, so the script gets the documented false and the tally records it.
    private static func installQuestStages(
        into registry: inout PapyrusNativeRegistry
    ) {
        registerMutation(&registry, ["SetCurrentStageID", "SetStage"]) { call, world, key in
            guard let stage = stageArgument(call, at: 0) else {
                return failure(call, "\(call.functionName) needs a stage index")
            }
            return try .returned(.boolean(world.setQuestStage(stage, for: key)))
        }
    }

    /// `SetObjectiveDisplayed(int aiObjective, bool abDisplayed = true, bool
    /// abForce = false)` and the completed and failed setters, each changing only
    /// its own flag. `abForce` only re-announces in the journal UI, so it is ignored.
    private static func installQuestObjectives(
        into registry: inout PapyrusNativeRegistry
    ) {
        registerMutation(&registry, ["SetObjectiveDisplayed"]) { call, world, key in
            guard let objective = stageArgument(call, at: 0) else {
                return failure(call, "\(call.functionName) needs an objective index")
            }
            try world.setQuestObjectiveDisplayed(
                objective, flag(call, at: 1), for: key
            )
            return .returned(.none)
        }
        registerMutation(&registry, ["SetObjectiveCompleted"]) { call, world, key in
            guard let objective = stageArgument(call, at: 0) else {
                return failure(call, "\(call.functionName) needs an objective index")
            }
            try world.setQuestObjectiveCompleted(
                objective, flag(call, at: 1), for: key
            )
            return .returned(.none)
        }
        registerMutation(&registry, ["SetObjectiveFailed"]) { call, world, key in
            guard let objective = stageArgument(call, at: 0) else {
                return failure(call, "\(call.functionName) needs an objective index")
            }
            try world.setQuestObjectiveFailed(
                objective, flag(call, at: 1), for: key
            )
            return .returned(.none)
        }
        // Completes the objectives the quest has shown; one never shown has no journal row.
        registerMutation(&registry, ["CompleteAllObjectives"]) { _, world, key in
            for objective in try world.questState(for: key).objectives.map(\.index) {
                try world.setQuestObjectiveCompleted(objective, true, for: key)
            }
            return .returned(.none)
        }
    }

    /// Registers a read that only needs the receiver's quest state, under
    /// every spelling `names` gives.
    private static func register(
        _ registry: inout PapyrusNativeRegistry,
        _ names: [String],
        _ body: @escaping @MainActor @Sendable (
            PapyrusNativeCall, QuestRuntimeState
        ) -> PapyrusNativeResult
    ) {
        registerMutation(&registry, names) { call, world, key in
            try body(call, world.questState(for: key))
        }
    }

    /// Registers a quest native under every spelling `names` gives, funnelling
    /// the two shared failures — no world receiver, and a thrown quest error —
    /// through one place so no quest native can report one of them differently.
    private static func registerMutation(
        _ registry: inout PapyrusNativeRegistry,
        _ names: [String],
        _ body: @escaping @MainActor @Sendable (
            PapyrusNativeCall, any PapyrusWorldBridge, ReferenceKey
        ) throws -> PapyrusNativeResult
    ) {
        for name in names {
            registry.register(PapyrusNativeFunction(
                scriptName: "Quest",
                functionName: name
            ) { call, context in
                guard let target = worldTarget(call, context) else {
                    return needsWorld(call)
                }
                do {
                    return try body(call, target.world, target.key)
                } catch {
                    return failure(
                        call,
                        "\(call.functionName) refused: \(String(describing: error))"
                    )
                }
            })
        }
    }

    /// A stage or objective index argument. Both are `int` in Papyrus and
    /// `UInt16` on disk, so a negative or out-of-range number names no stage
    /// the record can declare and is refused rather than wrapped.
    private static func stageArgument(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> UInt16? {
        guard let raw = integer(call, at: index) else { return nil }
        return UInt16(exactly: raw)
    }

    /// An optional Bool argument, defaulting to true — which is the default
    /// every one of the three objective setters declares.
    private static func flag(_ call: PapyrusNativeCall, at index: Int) -> Bool {
        guard call.arguments.indices.contains(index) else { return true }
        return switch call.arguments[index] {
        case let .boolean(value): value
        case let .integer(value): value != 0
        default: true
        }
    }
}
