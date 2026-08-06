// The `Quest` native family (issue #322): the script side of the #182 quest
// state and the #322 stage fragments.
//
// A quest reaches script code the same way a `GlobalVariable` does — as a VMAD
// object property, or as `self` inside a quest script — so the receiver handle
// resolves to the QUST record's `ReferenceKey` and everything below is one
// `PapyrusWorldAccess` call. Nothing here writes state directly; the seam in
// `PapyrusWorldStateBridgeQuests.swift` runs every mutation through
// `QuestRuntime`, so the stage and objective rules stay in one place.
//
// Signatures and semantics come from the Creation Kit wiki's Quest script
// reference, cited per function. Two names exist for three of these because
// the shipped `Quest.psc` declares a native and a thin wrapper around it —
// `SetCurrentStageID`/`SetStage`, `GetCurrentStageID`/`GetStage` and
// `IsStageDone`/`GetStageDone`. Both spellings are registered because both can
// arrive: with the install's `Quest.pex` in the library the wrapper runs as
// ordinary bytecode and calls the native, and without it the wrapper name
// itself dispatches here. They are the same function either way.
//
// Deliberately absent, and left to the unimplemented tally rather than stubbed:
// `Reset` (needs alias fill, #183), `IsObjectiveDisplayed`/`IsObjectiveCompleted`
// (the state exists, but the vanilla returns also fold in objective *targets*,
// which #183 owns), `IsStarting`/`IsStopping` (both name the latent window
// between a start or stop request and its completion, and OpenSky's mutations
// are immediate, so there is no honest moment for either to be true),
// `GetAlias`/`GetAliasedRef` and `SetActive` (#183 and M17). A quest script
// calling one of those is visibly missing in the Scripts readout rather than
// silently wrong.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installQuest(into registry: inout PapyrusNativeRegistry) {
        installQuestReads(into: &registry)
        installQuestRunState(into: &registry)
        installQuestStages(into: &registry)
        installQuestObjectives(into: &registry)
    }

    /// `bool IsRunning()`, `bool IsCompleted()`, `int GetCurrentStageID()` and
    /// `bool IsStageDone(int aiStage)`, with their wrapper spellings.
    ///
    /// `GetCurrentStageID` "obtains the highest completed stage in this quest"
    /// (<https://ck.uesp.net/wiki/GetCurrentStageID_-_Quest>) and
    /// `IsStageDone` "obtains whether the specified stage is done or not"
    /// (<https://ck.uesp.net/wiki/GetStageDone_-_Quest>) — both of which
    /// `QuestRuntimeState` already answers by those rules.
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

    /// `bool Start()`, `Stop()` and `CompleteQuest()`.
    ///
    /// `Start` returns "true if the quest was successfully started"
    /// (<https://ck.uesp.net/wiki/Start_-_Quest>); `Stop` "stops the quest"
    /// (<https://ck.uesp.net/wiki/Stop_-_Quest>) and `CompleteQuest` "flags
    /// this quest as completed"
    /// (<https://ck.uesp.net/wiki/CompleteQuest_-_Quest>), neither returning
    /// anything.
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

    /// `bool SetCurrentStageID(int aiStage)` and its `SetStage` wrapper, which
    /// return true when the stage exists and was set, false otherwise
    /// (<https://ck.uesp.net/wiki/SetStage_-_Quest>).
    ///
    /// A stage the quest does not declare is `QuestError.unknownStage`, which
    /// the shared handler turns into a native failure. The interpreter then
    /// substitutes the call's declared default — false for this signature —
    /// so the script sees exactly the documented return while the tally still
    /// records that something asked for a stage that does not exist.
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
    /// abForce = false)` and the completed and failed setters, each taking its
    /// own Bool and clearing none of the others
    /// (<https://ck.uesp.net/wiki/SetObjectiveDisplayed_-_Quest> and
    /// siblings).
    ///
    /// `abForce` is accepted and ignored: it forces the journal to re-announce
    /// an objective that was already displayed, which is a UI effect the
    /// journal (#184) owns and which changes no stored state.
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
    }

    /// Registers a read that only needs the receiver's quest state, under
    /// every spelling `names` gives.
    private static func register(
        _ registry: inout PapyrusNativeRegistry,
        _ names: [String],
        _ body: @escaping @Sendable (
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
        _ body: @escaping @Sendable (
            PapyrusNativeCall, PapyrusWorldAccess, ReferenceKey
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
