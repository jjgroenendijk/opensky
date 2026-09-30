// The crime natives: the `Faction` crime-gold family and the two `Actor` alarms.
// A missing world or crime runtime is a failure with a reason. Signatures are
// quoted from the Creation Kit wiki, because compiled mod bytecode depends on them.
//
// Documented in docs/engine/papyrus-activation.md, docs/engine/crime.md, and
// docs/engine/bounty-ledger.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    public static func installCrime(into registry: inout PapyrusNativeRegistry) {
        installFactionCrimeGold(into: &registry)
        installCrimeAlarms(into: &registry)
    }

    /// The `Faction` crime-gold family.
    private static func installFactionCrimeGold(into registry: inout PapyrusNativeRegistry) {
        // "Get the amount of crime gold on this faction that the player needs
        // to pay." — `int Function GetCrimeGold() native`
        // (<https://ck.uesp.net/wiki/GetCrimeGold_-_Faction>)
        registerCrimeGoldReader("GetCrimeGold", violent: nil, into: &registry)
        // `int Function GetCrimeGoldViolent() native` — "the amount of crime
        // gold on this faction that the player needs to pay for violent
        // crimes" (<https://ck.uesp.net/wiki/GetCrimeGoldViolent_-_Faction>)
        registerCrimeGoldReader("GetCrimeGoldViolent", violent: true, into: &registry)
        // `int Function GetCrimeGoldNonViolent() native` — the same "for
        // non-violent crimes"
        // (<https://ck.uesp.net/wiki/GetCrimeGoldNonViolent_-_Faction>)
        registerCrimeGoldReader("GetCrimeGoldNonViolent", violent: false, into: &registry)

        // "Modifies the amount of crime gold on this faction." —
        // `Function ModCrimeGold(int aiAmount, bool abViolent = False) native`
        // (<https://ck.uesp.net/wiki/ModCrimeGold_-_Faction>): `abViolent`
        // "when true, modifies violent crime gold; otherwise affects
        // non-violent crime gold".
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "ModCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let amount = integer(call, at: 0) else {
                    return failure(call, "ModCrimeGold needs an integer amount")
                }
                let violent = boolean(call, at: 1, default: false)
                guard
                    world.modifyCrimeGold(of: faction, by: Int(amount), violent: violent) != nil
                else {
                    return failure(call, "ModCrimeGold needs a session with a crime runtime")
                }
                return .returned(.none)
            }
        })

        // "Set the amount of non-violent crime gold on this faction." —
        // `Function SetCrimeGold(int aiGold) native`
        // (<https://ck.uesp.net/wiki/SetCrimeGold_-_Faction>)
        registerCrimeGoldSetter("SetCrimeGold", violent: false, into: &registry)
        // "Sets the violent crime gold on this faction." —
        // `Function SetCrimeGoldViolent(int aiGold) native`
        // (<https://ck.uesp.net/wiki/SetCrimeGoldViolent_-_Faction>)
        registerCrimeGoldSetter("SetCrimeGoldViolent", violent: true, into: &registry)
    }

    /// A no-argument reader: the whole bounty when `violent` is nil, one half
    /// otherwise.
    private static func registerCrimeGoldReader(
        _ name: String,
        violent: Bool?,
        into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: name
        ) { call, context in
            factionTarget(call, context) { world, faction in
                let gold = if let violent {
                    world.crimeGold(of: faction, violent: violent)
                } else {
                    world.crimeGold(of: faction)
                }
                guard let gold else {
                    return failure(call, "\(name) needs a session with a crime runtime")
                }
                return .returned(.integer(Int32(clamping: gold)))
            }
        })
    }

    /// A one-integer setter for one half of the bounty.
    private static func registerCrimeGoldSetter(
        _ name: String,
        violent: Bool,
        into registry: inout PapyrusNativeRegistry
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: name
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let gold = integer(call, at: 0) else {
                    return failure(call, "\(name) needs an integer amount")
                }
                guard world.setCrimeGold(of: faction, to: Int(gold), violent: violent) != nil else {
                    return failure(call, "\(name) needs a session with a crime runtime")
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

    /// Resolves a `Faction` receiver, then runs `body`. A FACT is keyed by the same
    /// `ReferenceKey` as its memberships and ledger rows, so it resolves like an
    /// `Actor` receiver.
    public static func factionTarget(
        _ call: PapyrusNativeCall,
        _ context: PapyrusNativeContext,
        body: (any PapyrusWorldBridge, ReferenceKey) -> PapyrusNativeResult
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
