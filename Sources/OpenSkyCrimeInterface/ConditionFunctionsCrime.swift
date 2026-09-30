// The crime condition functions (xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas):
// 459 `GetCrimeGold`, 375 `GetCrimeGoldViolent`, 376 `GetCrimeGoldNonviolent`,
// all `ptFactionNull`. A null parameter means the hold the subject stands in,
// through `CrimeConditionResolution.currentCrimeFaction`. See
// docs/engine/condition-functions.md and docs/engine/guard-response.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installCrime(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the amount of crime gold the player owes the specified
        // faction." The run-on names the actor whose ledger is read, and
        // parameter 1 names the FACT.
        registerCrimeGold(index: 459, name: "GetCrimeGold", violent: nil, into: &registry)
        registerCrimeGold(
            index: 375, name: "GetCrimeGoldViolent", violent: true, into: &registry
        )
        registerCrimeGold(
            index: 376, name: "GetCrimeGoldNonviolent", violent: false, into: &registry
        )
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
            guard let faction = call.context.crime.key(of: parameter.asFormID) else {
                return .failure(.unavailableCrime)
            }
            return call.referenceKey().flatMap { actor in
                let crime = call.context.crime
                let gold = if let violent {
                    crime.crimeGold(of: faction, violent: violent, on: actor)
                } else {
                    crime.crimeGold(of: faction, on: actor)
                }
                guard let gold else { return .failure(.unavailableCrime) }
                return .success(Float(gold))
            }
        })
    }
}
