// Actor-state condition functions: pure reads of the `actors` seam. Indices are
// raw (the Creation Kit adds 4096), from xEdit wbDefinitionsTES5.pas: 14
// GetActorValue, 46 GetDead, 80 GetLevel, 263 IsWeaponOut, 277 GetBaseActorValue,
// 323 GetCombatState, 640 GetActorValuePercent. An unknown actor-value index is
// `.unresolvedParameter`; an actor with no state is `.unavailableActorState`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installActor(_ registry: inout ConditionFunctionRegistry) {
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

        // "0 - no weapon drawn. 1 - only fists out. 2 - a weapon in either hand."
        // (<https://www.creationkit.com/index.php?title=IsWeaponOut>) 1 is
        // unreachable here (`ActorConditionState.weaponOutValue`). An unobserved
        // draw state is `.unavailableActorState`, not 0.
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

        installLevelAndBaseValue(&registry)
    }

    /// Vanilla perk requirements use these: `Armsman20` reads
    /// `GetBaseActorValue One-Handed >= 20` (`openskycli record Armsman20`).
    public static func installLevelAndBaseValue(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the current, unmodified value of the specified stat", the
        // base rather than the total (<https://ck.uesp.net/wiki/GetActorValue>
        // contrasts the two). What the actor's records author plus whatever an
        // explicit base write has moved it by, and never a fortify modifier —
        // which is what makes a perk requirement something a potion cannot buy.
        registry.register(ConditionFunction(
            index: 277,
            name: "GetBaseActorValue",
            parameter1: .integer
        ) { call in
            Self.actorValue(call, index: 277) { state, value in state.baseValue(at: value) }
        })

        // "Gets the actor's current level."
        // (<https://www.creationkit.com/index.php?title=GetLevel_-_Actor>)
        // The derived level for an NPC — its ACBS word, or the `PC Level Mult`
        // scaling of the player's — and the character level for the player.
        registry.register(ConditionFunction(
            index: 80,
            name: "GetLevel"
        ) { call in
            call.actorState().map { Float($0.level) }
        })
    }

    /// One actor-value read for the run-on's actor and the value parameter 1
    /// names. `ptActorValue` is a signed index; a negative or out-of-table one is
    /// `.unresolvedParameter`, so no zero is acted on.
    public static func actorValue(
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

nonisolated extension ConditionCall {
    /// Actor state for the run-on reference, or `.unavailableActorState`. A run-on
    /// that names nothing stays `.unresolvedReference`: that gap is not about actors.
    public func actorState() -> Result<ActorConditionState, ConditionFailure> {
        referenceKey().flatMap { key in
            guard let state = context.actors.state(for: key) else {
                return .failure(.unavailableActorState)
            }
            return .success(state)
        }
    }
}
