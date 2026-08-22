// The crime condition function (issue #504, roadmap item 21.5), split out of
// `ConditionFunctions` the way the actor, data, magic and perk families are.
//
// One function, from the xEdit TES5 condition table
// (dev-4.1.6 Core/wbDefinitionsTES5.pas):
//
//   (Index: 459; Name: 'GetCrimeGold'; ParamType1: ptFactionNull)
//
// The index is the raw stored number; the Creation Kit spells it 4555.
//
// The same table carries two siblings this issue deliberately does not install:
//
//   (Index: 375; Name: 'GetCrimeGoldViolent'; ParamType1: ptFactionNull)
//   (Index: 376; Name: 'GetCrimeGoldNonviolent'; ParamType1: ptFactionNull)
//
// Both need the bounty split by whether the crime was violent, and
// `CrimeLedgerState` stores one total per faction. Registering them over that
// total would answer every violent question with the non-violent bounty
// included, which is a convincing wrong number rather than a measurable gap —
// so they stay unregistered and `ConditionTally` counts them by index, which is
// what the real-data sweep ranks the next implementation from.
//
// `ptFactionNull` is nullable by declaration, and a null parameter asks about
// the hold the subject is standing in rather than about no faction at all; the
// seam resolves that through `CrimeConditionResolution.currentCrimeFaction`,
// which the caller fills from `CrimeFactionResolver`.
//
// Documented in docs/formats/conditions.md and docs/engine/crime.md.

import Foundation

nonisolated extension ConditionFunctions {
    static func installCrime(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the amount of crime gold the player owes the specified
        // faction." The run-on names the actor whose ledger is read, and
        // parameter 1 names the FACT.
        registry.register(ConditionFunction(
            index: 459,
            name: "GetCrimeGold",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(459))
            }
            guard let faction = call.context.crime.key(of: parameter.asFormID) else {
                return .failure(.unavailableCrime)
            }
            return call.referenceKey().flatMap { actor in
                guard let gold = call.context.crime.crimeGold(of: faction, on: actor) else {
                    return .failure(.unavailableCrime)
                }
                return .success(Float(gold))
            }
        })
    }
}
