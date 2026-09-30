// The `Actor` natives: actor values and combat for scripts. `self` becomes a
// `ReferenceKey`; a headless runtime or an unknown actor fails with a reason,
// and the interpreter uses the declared default. `SetActorValue`,
// `ModActorValue`, and `ForceActorValue` live in `PapyrusNativeActorValues.swift`.
// `GetAV` and similar are Papyrus wrappers and need no registration.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

nonisolated extension PapyrusNativeFunctions {
    public static func installActor(into registry: inout PapyrusNativeRegistry) {
        installActorValueReads(into: &registry)
        installActorValueWrites(into: &registry)
        installActorValueWriteNatives(into: &registry)
        installActorStatus(into: &registry)
        installActorCombat(into: &registry)
    }

    /// `StartCombat(Actor akTarget)` and `StopCombat()`
    /// (<https://www.creationkit.com/index.php?title=StartCombat_-_Actor>). Both go
    /// through `CombatLoopRuntime`, like the player's fights. OpenSky accepts only
    /// the player as target; another target is a tallied failure.
    private static func installActorCombat(into registry: inout PapyrusNativeRegistry) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "StartCombat"
        ) { call, context in
            guard let actor = actorTarget(call, context) else {
                return needsActor(call)
            }
            guard
                let handle = objectArgument(call, at: 0),
                let target = actor.world.referenceKey(for: handle)
            else {
                return failure(call, "StartCombat needs a target actor")
            }
            guard actor.world.startActorCombat(actor.key, target: target) else {
                return failure(
                    call,
                    "StartCombat fights the player alone; OpenSky simulates no "
                        + "actor-versus-actor combat"
                )
            }
            return .returned(.none)
        })
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "StopCombat"
        ) { call, context in
            guard let actor = actorTarget(call, context) else {
                return needsActor(call)
            }
            actor.world.stopActorCombat(actor.key)
            return .returned(.none)
        })
    }

    /// `float GetActorValue(string)`, `float GetBaseActorValue(string)`, and
    /// `float GetActorValuePercentage(string)`
    /// (<https://www.creationkit.com/index.php?title=GetActorValue_-_Actor>). The
    /// base is the re-derived maximum; the percentage divides by the maximum.
    private static func installActorValueReads(
        into registry: inout PapyrusNativeRegistry
    ) {
        let reads: [(String, @Sendable (PapyrusActorState, Int32) -> Float?)] = [
            ("GetActorValue", { state, index in state.value(at: index) }),
            ("GetBaseActorValue", { state, index in state.baseValue(at: index) }),
            ("GetActorValuePercentage", { state, index in state.fraction(at: index) })
        ]
        for (functionName, read) in reads {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: functionName
            ) { call, context in
                guard let actor = actorTarget(call, context) else {
                    return needsActor(call)
                }
                guard let index = actorValueIndex(call, at: 0) else {
                    return unknownActorValue(call, at: 0)
                }
                guard let state = actor.world.actorState(for: actor.key) else {
                    return needsActor(call)
                }
                guard let value = read(state, index) else {
                    return unknownActorValue(call, at: 0)
                }
                return .returned(.float(value))
            })
        }
    }

    /// `DamageActorValue(string, float)` and `RestoreActorValue(string, float)`.
    /// Negative amounts act as positive, as the wiki says
    /// (<https://www.creationkit.com/index.php?title=DamageActorValue_-_Actor>). Damage
    /// to zero health becomes a death in the same call.
    private static func installActorValueWrites(
        into registry: inout PapyrusNativeRegistry
    ) {
        let writes: [(
            String,
            @Sendable (PapyrusWorldAccess, Int32, Float, ReferenceKey) -> Void
        )] = [
            ("DamageActorValue", { world, index, amount, key in
                world.damageActorValue(at: index, by: amount, on: key)
            }),
            ("RestoreActorValue", { world, index, amount, key in
                world.restoreActorValue(at: index, by: amount, on: key)
            })
        ]
        for (functionName, write) in writes {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: functionName
            ) { call, context in
                guard let actor = actorTarget(call, context) else {
                    return needsActor(call)
                }
                guard let index = actorValueIndex(call, at: 0) else {
                    return unknownActorValue(call, at: 0)
                }
                guard let amount = float(call, at: 1), amount.isFinite else {
                    return failure(call, "\(functionName) needs a finite amount")
                }
                write(actor.world, index, abs(amount), actor.key)
                return .returned(.none)
            })
        }
    }

    /// `bool IsDead()`, `bool IsInCombat()`, `bool IsWeaponDrawn()`, and
    /// `Kill(Actor akKiller = None)`. `IsDead` reads the death latch.
    /// `IsInCombat` reads the behavior phase, so searching counts.
    /// `IsWeaponDrawn` answers only for the player; others fail with a reason. The
    /// killer may be `None` (<https://www.creationkit.com/index.php?title=Kill_-_Actor>).
    private static func installActorStatus(
        into registry: inout PapyrusNativeRegistry
    ) {
        let flags: [(String, @Sendable (PapyrusActorState) -> Bool?)] = [
            ("IsDead", { $0.isDead }),
            ("IsInCombat", { $0.isInCombat }),
            ("IsWeaponDrawn", { $0.weaponDrawState?.isWeaponInHand })
        ]
        for (functionName, read) in flags {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: functionName
            ) { call, context in
                guard
                    let actor = actorTarget(call, context),
                    let state = actor.world.actorState(for: actor.key)
                else {
                    return needsActor(call)
                }
                guard let value = read(state) else {
                    return failure(
                        call,
                        "\(functionName) needs an actor whose weapon state this "
                            + "session observes"
                    )
                }
                return .returned(.boolean(value))
            })
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "Kill"
        ) { call, context in
            guard let actor = actorTarget(call, context) else {
                return needsActor(call)
            }
            let killer = objectArgument(call, at: 0)
                .flatMap { actor.world.referenceKey(for: $0) }
            actor.world.killActor(actor.key, killer: killer)
            return .returned(.none)
        })
    }

    // MARK: - Shared

    /// The world façade plus the world identity of `self`, for an `Actor`
    /// method. Identical in shape to `worldTarget(_:_:)`; named separately so
    /// the failure it produces can say "actor" rather than "reference".
    public static func actorTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: PapyrusWorldAccess, key: ReferenceKey)? {
        worldTarget(call, context)
    }

    /// The single failure an `Actor` native returns when it has no world, no
    /// world identity for its receiver, or no actor behind that identity.
    public static func needsActor(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a world runtime and an actor receiver"
        )
    }

    /// The vanilla actor-value index the string argument at `index` names, or nil
    /// when it is missing, not a string, or no vanilla name. Papyrus synonyms such
    /// as `Marksman` are not aliased.
    public static func actorValueIndex(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> Int32? {
        guard let name = string(call, at: index) else { return nil }
        return ActorValueIdentity.index(named: name)
    }

    /// The failure for an actor-value name that names no vanilla actor value.
    ///
    /// It names the value rather than only the function, so the tally's
    /// per-function counts can be read alongside a log that says *which* name
    /// the corpus keeps asking for — which is the number that decides whether
    /// the table is missing an alias.
    public static func unknownActorValue(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> PapyrusNativeResult {
        let name = string(call, at: index) ?? "<missing>"
        return failure(
            call,
            "\(call.functionName) knows no actor value named \"\(name)\""
        )
    }

    /// Argument `index` as an object handle, or nil for a missing argument and
    /// for Papyrus `None` alike — which `Kill(akKiller = None)` relies on.
    public static func objectArgument(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> PapyrusObjectHandle? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .object(handle) = call.arguments[index] else { return nil }
        return handle
    }
}
