// The crime natives (issue #504, roadmap item 21.5): the `Faction` crime-gold
// family and the two `Actor` alarms, over 21.5's crime runtime.
//
// Policy is the `Actor` and perk families', unchanged: `self` arrives as
// `PapyrusNativeCall.receiver` and becomes a `ReferenceKey`; a headless
// runtime, a handle with no world identity, or a session with no crime data is
// a failure with a reason rather than a guess, and the interpreter substitutes
// the call's declared default so the script keeps running.
//
// Every signature below is quoted from the Creation Kit wiki at the
// registration site rather than recalled, because a Papyrus signature is an
// interface a mod's compiled bytecode already agrees with: a wrong argument
// count is a script that stops working, not a number that reads slightly off.
//
// Two declared siblings are deliberately absent — `GetCrimeGoldViolent` and
// `GetCrimeGoldNonViolent`, plus `SetCrimeGoldViolent` — for the reason their
// condition-function counterparts are: `CrimeLedgerState` holds one bounty per
// faction, and answering a violent-only question from a combined total would be
// a convincing wrong number rather than a measurable gap. An unimplemented
// native is counted by name in `PapyrusNativeLog`, which is what ranks the next
// one to build.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/crime.md.

import Foundation

nonisolated extension PapyrusNativeFunctions {
    static func installCrime(into registry: inout PapyrusNativeRegistry) {
        installFactionCrimeGold(into: &registry)
        installCrimeAlarms(into: &registry)
    }

    /// The `Faction` crime-gold trio.
    private static func installFactionCrimeGold(into registry: inout PapyrusNativeRegistry) {
        // "Get the amount of crime gold on this faction that the player needs
        // to pay." — `int Function GetCrimeGold() native`
        // (<https://ck.uesp.net/wiki/GetCrimeGold_-_Faction>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "GetCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let gold = world.crimeGold(of: faction) else {
                    return failure(call, "GetCrimeGold needs a session with a crime runtime")
                }
                return .returned(.integer(Int32(clamping: gold)))
            }
        })

        // "Modifies the amount of crime gold on this faction." —
        // `Function ModCrimeGold(int aiAmount, bool abViolent = False) native`
        // (<https://ck.uesp.net/wiki/ModCrimeGold_-_Faction>). `abViolent` is
        // accepted and ignored; see `PapyrusWorldCrimeBridge`.
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "ModCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let amount = integer(call, at: 0) else {
                    return failure(call, "ModCrimeGold needs an integer amount")
                }
                guard world.modifyCrimeGold(of: faction, by: Int(amount)) != nil else {
                    return failure(call, "ModCrimeGold needs a session with a crime runtime")
                }
                return .returned(.none)
            }
        })

        // "Set the amount of non-violent crime gold on this faction." —
        // `Function SetCrimeGold(int aiGold) native`
        // (<https://ck.uesp.net/wiki/SetCrimeGold_-_Faction>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "SetCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let gold = integer(call, at: 0) else {
                    return failure(call, "SetCrimeGold needs an integer amount")
                }
                guard world.setCrimeGold(of: faction, to: Int(gold)) != nil else {
                    return failure(call, "SetCrimeGold needs a session with a crime runtime")
                }
                return .returned(.none)
            }
        })
    }

    /// The two `Actor` alarms.
    private static func installCrimeAlarms(into registry: inout PapyrusNativeRegistry) {
        // "Have this actor behave as if he was assaulted by the player." —
        // `Function SendAssaultAlarm() native`
        // (<https://ck.uesp.net/wiki/SendAssaultAlarm_-_Actor>). No arguments,
        // so the criminal is the player by declaration.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "SendAssaultAlarm"
        ) { call, context in
            guard let actor = actorTarget(call, context) else { return needsActor(call) }
            guard
                actor.world.sendAssaultAlarm(
                    witness: actor.key, criminal: actor.world.playerKey
                ) != nil
            else {
                return failure(call, "SendAssaultAlarm needs a session with a crime runtime")
            }
            return .returned(.none)
        })

        // "Have this actor pretend he caught the specified criminal
        // trespassing." —
        // `Function SendTrespassAlarm(Actor akCriminal) native`
        // (<https://ck.uesp.net/wiki/SendTrespassAlarm_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "SendTrespassAlarm"
        ) { call, context in
            guard let actor = actorTarget(call, context) else { return needsActor(call) }
            guard
                let handle = objectArgument(call, at: 0),
                let criminal = actor.world.referenceKey(for: handle)
            else {
                return failure(call, "SendTrespassAlarm needs a criminal actor argument")
            }
            guard
                actor.world.sendTrespassAlarm(witness: actor.key, criminal: criminal) != nil
            else {
                return failure(call, "SendTrespassAlarm needs a session with a crime runtime")
            }
            return .returned(.none)
        })
    }

    /// A `Faction` native: resolve the receiver to the FACT's world identity,
    /// then run `body`.
    ///
    /// A `Faction` script's `self` is a form rather than a placed reference, and
    /// this engine addresses a FACT by the same `ReferenceKey` its memberships
    /// and its ledger rows are keyed by — so the receiver resolves exactly as an
    /// `Actor` receiver does and needs no separate lookup.
    private static func factionTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (PapyrusWorldAccess, ReferenceKey) -> PapyrusNativeResult
    ) -> PapyrusNativeResult {
        guard let target = worldTarget(call, context) else {
            return failure(
                call,
                "\(call.functionName) needs a world runtime and a faction receiver"
            )
        }
        return body(target.world, target.key)
    }
}
