// The crime condition functions (xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas):
// 459 `GetCrimeGold`, 375 `GetCrimeGoldViolent`, 376 `GetCrimeGoldNonviolent`,
// all `ptFactionNull`. Each reads the player's bounty. A null parameter means the
// run-on actor's crime faction, else the hold the subject stands in. See
// docs/engine/condition-functions.md and docs/engine/guard-response.md.

import Foundation
public import OpenSkyConditions
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM

nonisolated public enum ConditionFunctionsCrime {
    public static func installCrime(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the player's current crime gold. Uses the crime gold from the
        // calling actor's crime faction unless the factionID is specified."
        // (<https://ck.uesp.net/wiki/GetCrimeGold>)
        registerCrimeGold(index: 459, name: "GetCrimeGold", violent: nil, into: &registry)
        registerCrimeGold(
            index: 375, name: "GetCrimeGoldViolent", violent: true, into: &registry
        )
        registerCrimeGold(
            index: 376, name: "GetCrimeGoldNonviolent", violent: false, into: &registry
        )
        ConditionFunctionsCrimeSituation.installCrimeSituation(&registry)
    }

    /// One crime-gold reader: the whole bounty when `violent` is nil, one half
    /// otherwise.
    private static func registerCrimeGold(
        index: UInt16,
        name: String,
        violent: Bool?,
        into registry: inout ConditionFunctionRegistry
    ) {
        registry.register(ConditionFunction(
            index: index,
            name: name,
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(index))
            }
            return call.referenceKey().flatMap { actor in
                let crime = call.context.crime
                let faction = parameter.asFormID.isNull
                    ? call.context.crimeFaction(of: actor)
                    : crime.facts.key(of: parameter.asFormID)
                guard let faction else { return .failure(.unavailableCrime) }
                let gold = if let violent {
                    crime.crimeGold(of: faction, violent: violent, on: .player)
                } else {
                    crime.crimeGold(of: faction, on: .player)
                }
                guard let gold else { return .failure(.unavailableCrime) }
                return .success(Float(gold))
            }
        })
    }
}

nonisolated extension ConditionContext {
    /// The crime faction a null `ptFactionNull` parameter means for `actor`: its own, else
    /// the hold it stands in.
    func crimeFaction(of actor: ReferenceKey) -> ReferenceKey? {
        factions.facts.fact(of: actor)?.crimeFaction ?? crime.currentCrimeFaction
    }

    /// The player's bounty with `actor`'s crime faction, as `<CrimeGold>` in a guard's
    /// topic shows it. Nil without crime data or a faction.
    public func playerCrimeGold(owedTo actor: ReferenceKey) -> Int32? {
        crimeFaction(of: actor).flatMap { crime.crimeGold(of: $0, on: .player) }
    }
}
