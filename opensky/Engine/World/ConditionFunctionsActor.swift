// Actor-state condition functions (issue #375, roadmap item 15.8), split out of
// `ConditionFunctions` the way `ConditionFunctionsQuest` is.
//
// These five were waiting on two subsystems rather than one: 15.3's actor-value
// store and 15.7's combat state. With both in place each is a pure read of the
// `actors` seam on `ConditionContext`, with no world, no clock and no store
// behind it — which is what lets the whole family be driven from a literal in a
// test.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. They come from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas, whose
// condition-function table lists:
//
//   (Index:  14; Name: 'GetActorValue'; ParamType1: ptActorValue)
//   (Index:  46; Name: 'GetDead')
//   (Index: 263; Name: 'IsWeaponOut')
//   (Index: 323; Name: 'GetCombatState')
//   (Index: 640; Name: 'GetActorValuePercent'; ParamType1: ptActorValue)
//
// Return semantics come from the Creation Kit wiki pages cited at each
// registration. `ptActorValue` is an index into the vanilla actor-value table,
// which `ActorValueIdentity` carries with its own citation.
//
// Two misses are distinct on purpose and stay distinct in the tally. An
// actor-value parameter that names no vanilla actor value is
// `.unresolvedParameter`, keyed by function index, because the *parameter* is
// what could not be read. A reference the actor seam carries no state for at
// all is `.unavailableActorState`. Since item 19.5 stored the whole table
// (issue #468), the first bucket counts only genuinely unknown indices rather
// than the 161 values that had no store; the second still says the evaluation
// context was not wired.

import Foundation

nonisolated extension ConditionFunctions {
    static func installActor(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the current, modified value of the specified stat."
        // (<https://ck.uesp.net/wiki/GetActorValue>)
        registry.register(ConditionFunction(
            index: 14,
            name: "GetActorValue",
            parameter1: .integer
        ) { call in
            Self.actorValue(call, index: 14) { state, value in state.value(at: value) }
        })

        // "Returns the current value of the indicated Actor Value as a
        // percentage of its maximum. The return value will be between 0 and 1."
        // (<https://ck.uesp.net/wiki/GetActorValuePercent>) A zero or negative
        // maximum reads as 0 rather than dividing, which is the same rule
        // `ActorValues.fractions(of:)` already applies to the HUD meters.
        registry.register(ConditionFunction(
            index: 640,
            name: "GetActorValuePercent",
            parameter1: .integer
        ) { call in
            Self.actorValue(call, index: 640) { state, value in
                state.fraction(at: value)
            }
        })

        // "Returns 1 if the object reference is dead." The same page records
        // why this is the reliable question: "This is more accurate than
        // checking the actor's health because there are circumstances when the
        // actor can die without losing all of their health."
        // (<https://ck.uesp.net/wiki/GetDead>) OpenSky reads the death latch
        // rather than health for exactly that reason.
        registry.register(ConditionFunction(
            index: 46,
            name: "GetDead"
        ) { call in
            call.actorState().map { Self.isTrue($0.isDead) }
        })

        // "0 - If the Actor does not have a weapon drawn. 1 - If the Actor has
        // only his fists out. 2 - If the Actor has a weapon in either hand."
        // (<https://www.creationkit.com/index.php?title=IsWeaponOut>) Three
        // returns rather than a bool, and OpenSky produces two of them; see
        // `ActorConditionState.weaponOutValue` for why 1 is unreachable.
        //
        // An actor whose draw state nothing in this session observes is
        // `.unavailableActorState` rather than 0: "sheathed" is a fact about an
        // actor and nothing here knows it.
        registry.register(ConditionFunction(
            index: 263,
            name: "IsWeaponOut"
        ) { call in
            call.actorState().flatMap { state in
                guard let value = state.weaponOutValue else {
                    return .failure(.unavailableActorState)
                }
                return .success(value)
            }
        })

        // "Gets the actor's current combat state ... 0: Not in combat, 1: In
        // combat, 2: Searching."
        // (<https://www.creationkit.com/index.php?title=GetCombatState>)
        // All three are reachable as of 16.7: searching is the phase a fighting
        // actor enters when 16.6 detection loses the target.
        registry.register(ConditionFunction(
            index: 323,
            name: "GetCombatState"
        ) { call in
            call.actorState().map(\.combatStateValue)
        })
    }

    /// One actor-value read: resolve the run-on's actor, then let `read` answer
    /// for the actor value parameter 1 names.
    ///
    /// Parameter 1 is `ptActorValue`, a signed index rather than a FormID.
    /// Since 19.5 every index the vanilla table carries is readable, so
    /// `.unresolvedParameter` is left for a negative or out-of-table number
    /// alone — a parameter that names no actor value at all, where the function
    /// has no number to compare and a zero would be acted upon.
    static func actorValue(
        _ call: ConditionCall,
        index: UInt16,
        read: (ActorConditionState, Int32) -> Float?
    ) -> Result<Float, ConditionFailure> {
        guard
            let parameter = call.parameter1,
            ActorValueIdentity.isVanilla(index: parameter.asInt32)
        else {
            return .failure(.unresolvedParameter(index))
        }
        return call.actorState().flatMap { state in
            guard let value = read(state, parameter.asInt32) else {
                return .failure(.unresolvedParameter(index))
            }
            return .success(value)
        }
    }
}
