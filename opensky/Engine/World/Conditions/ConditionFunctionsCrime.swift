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
// and its two siblings, which split the same bounty by whether the crime was
// violent (issue #563):
//
//   (Index: 375; Name: 'GetCrimeGoldViolent'; ParamType1: ptFactionNull)
//   (Index: 376; Name: 'GetCrimeGoldNonviolent'; ParamType1: ptFactionNull)
//
// `CrimeLedgerEntry` holds the two halves, and `GetCrimeGold` answers their
// sum. Which crimes are violent is `CrimeKind.isViolent`.
//
// `ptFactionNull` is nullable by declaration, and a null parameter asks about
// the hold the subject is standing in rather than about no faction at all; the
// seam resolves that through `CrimeConditionResolution.currentCrimeFaction`,
// which the caller fills from `CrimeFactionResolver`.
//
// Documented in docs/formats/conditions.md and docs/engine/guard-response.md.

import Foundation

nonisolated extension ConditionFunctions {
    static func installCrime(_ registry: inout ConditionFunctionRegistry) {
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
