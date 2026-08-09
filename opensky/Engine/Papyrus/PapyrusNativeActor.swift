// The `Actor` family (issues #375 and #424, roadmap items 15.8 and 16.7): the
// scripting-facing surface of 15.3's actor values and of the fights 16.7's
// combat AI runs.
//
// Policy is the `ObjectReference` family's, unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`; a headless runtime,
// a handle with no world identity, or a key that names no actor this session
// tracks is a failure with a reason rather than a guess, and the interpreter
// substitutes the call's declared default so the script keeps running.
//
// Signatures follow the Creation Kit wiki's Actor script reference, cited at
// each registration.
//
// ## What is deliberately absent, and why
//
// `SetActorValue` is **not** registered. The wiki is explicit that it "sets the
// base value ... Any modifiers are left intact", and that "While GetActorValue
// returns the current value, SetActorValue sets the base value." OpenSky has no
// base-value override store: maximums are re-derived from RACE, CLAS and NPC_
// on every read precisely so a save cannot carry a number a changed load order
// no longer authors (see docs/engine/actor-values.md). `ActorValueRuntime.set`
// writes the *current* value, which is `ForceActorValue`'s job and not this
// one's. Registering it against the wrong store would make every script that
// buffs an NPC's maximum health silently move its current health instead, so it
// stays an unimplemented native, counted by name in the tally, until a base
// override exists. `ModActorValue` and `ForceActorValue` are absent for the
// same reason and are M18's with the magic-effect layer.
//
// `SetRelationshipRank` and the faction natives are absent with the factions
// themselves: 16.7 keeps `ActorHostility`'s two cases and adds no relationship
// store for them to write.
//
// `GetActorValuePercentage` is spelled with the long suffix here because that
// is the native; `GetAVPercentage` is a Papyrus-level wrapper around it, as are
// `GetAV`, `GetBaseAV`, `DamageAV` and `RestoreAV`, so they need no
// registration of their own.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installActor(into registry: inout PapyrusNativeRegistry) {
        installActorValueReads(into: &registry)
        installActorValueWrites(into: &registry)
        installActorStatus(into: &registry)
        installActorCombat(into: &registry)
    }

    /// `StartCombat(Actor akTarget)` and `StopCombat()`.
    ///
    /// "Starts combat between this actor and the target actor."
    /// (<https://www.creationkit.com/index.php?title=StartCombat_-_Actor>)
    /// "Stops this actor from fighting."
    /// (<https://www.creationkit.com/index.php?title=StopCombat_-_Actor>)
    ///
    /// Both were deliberately unregistered through M15, because hostility was
    /// read and never written from script and no AI had a reason to call them.
    /// They route through `CombatLoopRuntime` rather than writing
    /// `ActorCombatState` directly, so a script's fight enters by the same door
    /// the player's does: hostility through the world-state store, the same
    /// behavior machine engaged, and the same hand-back to the 16.5 package when
    /// it stops.
    ///
    /// `StartCombat` names a target, and OpenSky accepts only the player.
    /// Actor-versus-actor combat is out of 16.7's scope — `ActorHostility` has
    /// two cases and both are about the player — so a script that names anybody
    /// else takes a tallied failure naming the reason rather than a fight that
    /// silently does not happen. `StopCombat` takes no argument.
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

    /// `float GetActorValue(string)`, `float GetBaseActorValue(string)` and
    /// `float GetActorValuePercentage(string)`.
    ///
    /// "Gets the specified actor value from the actor ... This function returns
    /// the current value as opposed to the base (maximum) value."
    /// (<https://www.creationkit.com/index.php?title=GetActorValue_-_Actor>)
    /// "Gets the base value of the specified actor value."
    /// (<https://www.creationkit.com/index.php?title=GetBaseActorValue_-_Actor>)
    /// "Gets the specified actor value from the actor as a percentage of its
    /// maximum value (from 0 to 1)."
    /// (<https://www.creationkit.com/index.php?title=GetActorValuePercentage_-_Actor>)
    ///
    /// The base value is this engine's re-derived maximum. Nothing buffs a
    /// maximum yet, so base and maximum are the same number; when magic effects
    /// arrive they will separate, and the percentage divides by the maximum
    /// rather than by the base for that reason.
    private static func installActorValueReads(
        into registry: inout PapyrusNativeRegistry
    ) {
        let reads: [(String, @Sendable (PapyrusActorState, ActorValueKind) -> Float)] = [
            ("GetActorValue", { state, kind in state.current[kind] }),
            ("GetBaseActorValue", { state, kind in state.maximums[kind] }),
            ("GetActorValuePercentage", { state, kind in
                state.current.fractions(of: state.maximums)[kind]
            })
        ]
        for (functionName, read) in reads {
            registry.register(PapyrusNativeFunction(
                scriptName: "Actor",
                functionName: functionName
            ) { call, context in
                guard let actor = actorTarget(call, context) else {
                    return needsActor(call)
                }
                guard let kind = actorValueKind(call, at: 0) else {
                    return unstoredActorValue(call, at: 0)
                }
                guard let state = actor.world.actorState(for: actor.key) else {
                    return needsActor(call)
                }
                return .returned(.float(read(state, kind)))
            })
        }
    }

    /// `DamageActorValue(string, float)` and `RestoreActorValue(string, float)`.
    ///
    /// "Negative numbers will be converted to positive so -100 and 100 will
    /// have the same effect."
    /// (<https://www.creationkit.com/index.php?title=DamageActorValue_-_Actor>,
    /// and the same sentence on the Restore page), which is why both take the
    /// magnitude rather than rejecting a negative argument.
    ///
    /// A damage that empties health becomes a death inside the bridge, on the
    /// same call, so a script that damages an actor to zero and immediately
    /// asks `IsDead()` gets the answer the player can see.
    private static func installActorValueWrites(
        into registry: inout PapyrusNativeRegistry
    ) {
        let writes: [(
            String,
            @Sendable (PapyrusWorldAccess, ActorValueKind, Float, ReferenceKey) -> Void
        )] = [
            ("DamageActorValue", { world, kind, amount, key in
                world.damageActorValue(kind, by: amount, on: key)
            }),
            ("RestoreActorValue", { world, kind, amount, key in
                world.restoreActorValue(kind, by: amount, on: key)
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
                guard let kind = actorValueKind(call, at: 0) else {
                    return unstoredActorValue(call, at: 0)
                }
                guard let amount = float(call, at: 1), amount.isFinite else {
                    return failure(call, "\(functionName) needs a finite amount")
                }
                write(actor.world, kind, abs(amount), actor.key)
                return .returned(.none)
            })
        }
    }

    /// `bool IsDead()`, `bool IsInCombat()`, `bool IsWeaponDrawn()` and
    /// `Kill(Actor akKiller = None)`.
    ///
    /// "Is this actor currently dead?"
    /// (<https://www.creationkit.com/index.php?title=IsDead_-_Actor>) reads the
    /// death latch, not health, which is what makes it agree with the corpse on
    /// screen.
    ///
    /// "Is this actor currently in combat?"
    /// (<https://www.creationkit.com/index.php?title=IsInCombat_-_Actor>) is
    /// 16.7's behavior phase rather than stored hostility: an actor that hates
    /// the player but has not noticed them is not in a fight, an actor still
    /// searching for a target it lost is, and a dead one never is.
    ///
    /// "Has this actor drawn his weapon and/or spell?"
    /// (<https://www.creationkit.com/index.php?title=IsWeaponDrawn_-_Actor>)
    /// can only be answered for an actor whose draw state something observes,
    /// which today is the player alone. Every other actor fails with a reason
    /// and is counted, because "sheathed" would be an invented fact.
    ///
    /// "Kills this actor with the passed-in actor being the culprit."
    /// (<https://www.creationkit.com/index.php?title=Kill_-_Actor>) The killer
    /// is argument 0 and may legitimately be `None`.
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
    static func actorTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext
    ) -> (world: PapyrusWorldAccess, key: ReferenceKey)? {
        worldTarget(call, context)
    }

    /// The single failure an `Actor` native returns when it has no world, no
    /// world identity for its receiver, or no actor behind that identity.
    static func needsActor(_ call: PapyrusNativeCall) -> PapyrusNativeResult {
        failure(
            call,
            "\(call.functionName) needs a world runtime and an actor receiver"
        )
    }

    /// The stored actor value argument `index` names, or nil when the argument
    /// is missing, is not a string, or names a value this engine does not
    /// store.
    static func actorValueKind(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> ActorValueKind? {
        guard let name = string(call, at: index) else { return nil }
        return ActorValueIdentity.kind(named: name)
    }

    /// The failure for an actor-value name OpenSky has no store for.
    ///
    /// It names the value rather than only the function, so the tally's
    /// per-function counts can be read alongside a log that says *which* actor
    /// value the corpus keeps asking for — which is the number that decides
    /// what to store next.
    static func unstoredActorValue(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> PapyrusNativeResult {
        let name = string(call, at: index) ?? "<missing>"
        return failure(
            call,
            "\(call.functionName) has no store for actor value \"\(name)\""
        )
    }

    /// Argument `index` as an object handle, or nil for a missing argument and
    /// for Papyrus `None` alike — which `Kill(akKiller = None)` relies on.
    static func objectArgument(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> PapyrusObjectHandle? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .object(handle) = call.arguments[index] else { return nil }
        return handle
    }
}
