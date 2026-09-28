// The guard and arrest natives (issue #505, roadmap item 21.6): `Actor`'s
// `GetCrimeFaction` and `IsGuard`, and `Faction`'s `CanPayCrimeGold`,
// `PlayerPayCrimeGold` and `SendPlayerToJail`.
//
// Policy is the crime family's, unchanged: a headless runtime or a session with
// no crime or faction data is a failure with a reason, and the interpreter
// substitutes the declared default. Every signature is quoted from the Creation
// Kit wiki at the registration site.
//
// Documented in docs/engine/papyrus-activation.md and docs/engine/guard-response.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension PapyrusNativeFunctions {
    public static func installGuard(into registry: inout PapyrusNativeRegistry) {
        installGuardQueries(into: &registry)
        installArrestOutcomes(into: &registry)
    }

    /// The two `Actor` questions.
    private static func installGuardQueries(into registry: inout PapyrusNativeRegistry) {
        // "Obtains the Faction this actor reports it's crimes to." —
        // `Faction Function GetCrimeFaction() native`
        // (<https://ck.uesp.net/wiki/GetCrimeFaction_-_Actor>). An actor with
        // no `CRIF` answers None, which is a fact about the actor rather than a
        // failure.
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "GetCrimeFaction"
        ) { call, context in
            guard let actor = actorTarget(call, context) else { return needsActor(call) }
            guard let faction = actor.world.crimeFaction(ofActor: actor.key) else {
                return failure(call, "GetCrimeFaction needs a session with faction data")
            }
            return .returned(faction.map { handle($0, in: actor.world) } ?? .none)
        })

        // "Is this actor a guard?" — `bool Function IsGuard() native`
        // (<https://ck.uesp.net/wiki/IsGuard_-_Actor>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Actor",
            functionName: "IsGuard"
        ) { call, context in
            guard let actor = actorTarget(call, context) else { return needsActor(call) }
            guard let isGuard = actor.world.isGuard(actor.key) else {
                return failure(call, "IsGuard needs a session with faction data")
            }
            return .returned(.boolean(isGuard))
        })
    }

    /// The three `Faction` arrest natives.
    private static func installArrestOutcomes(into registry: inout PapyrusNativeRegistry) {
        // "Checks to see if the player can pay the crime gold for this
        // faction." — `bool Function CanPayCrimeGold() native`
        // (<https://ck.uesp.net/wiki/CanPayCrimeGold_-_Faction>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "CanPayCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                guard let canPay = world.canPayCrimeGold(to: faction) else {
                    return failure(call, "CanPayCrimeGold needs a session with a crime runtime")
                }
                return .returned(.boolean(canPay))
            }
        })

        // "Has the player pay the crime gold on this faction, possibly removing
        // any stolen items in their inventory and sending them to jail." —
        // `Function PlayerPayCrimeGold(bool abRemoveStolenItems = True, bool
        // abGoToJail = True) native`
        // (<https://ck.uesp.net/wiki/PlayerPayCrimeGold_-_Faction>)
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "PlayerPayCrimeGold"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                settle(call, world, faction, .pay(
                    removeStolen: boolean(call, at: 0, default: true),
                    goToJail: boolean(call, at: 1, default: true)
                ))
            }
        })

        // `Function SendPlayerToJail(bool abRemoveInventory = True, bool
        // abRealJail = True) native`
        // (<https://ck.uesp.net/wiki/SendPlayerToJail_-_Faction>). Both
        // parameters are accepted and not yet read: the sentence here is
        // served at once with no jail cell and no belongings chest, so there
        // is no inventory to hold and no fake jail to choose instead
        // (docs/engine/guard-response.md).
        registry.register(PapyrusNativeFunction(
            scriptName: "Faction",
            functionName: "SendPlayerToJail"
        ) { call, context in
            factionTarget(call, context) { world, faction in
                settle(call, world, faction, .jail)
            }
        })
    }

    /// Runs one arrest outcome, turning a refusal into a failure with its
    /// reason so the script log says why nothing happened.
    private static func settle(
        _ call: PapyrusNativeCall,
        _ world: PapyrusWorldAccess,
        _ faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> PapyrusNativeResult {
        switch world.settleArrest(with: faction, outcome) {
        case .none:
            failure(call, "\(call.functionName) needs a session with a crime runtime")
        case .success:
            .returned(.none)
        case .failure(.noBounty):
            failure(call, "\(call.functionName): the player owes this faction nothing")
        case let .failure(.cannotAfford(owed, gold)):
            failure(call, "\(call.functionName): bounty \(owed) exceeds gold \(gold)")
        }
    }
}
