// Crime-encounter condition functions, indices from xEdit wbDefinitionsTES5.pas: 61
// GetAlarmed, 125 IsGuard, 144 GetTrespassWarningLevel, 145 IsTrespassing, 278
// IsOwner, 314 IsActorAVictim, 497 CanPayCrimeGold, 499 GetDaysInJail, 656
// GetArrestedState, 657 GetArrestingActor. See docs/engine/condition-functions-world.md#crime.

import Foundation
import OpenSkyConditions
import OpenSkyFactionsInterface
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installCrimeSituation(_ registry: inout ConditionFunctionRegistry) {
        typealias Read = @Sendable (CrimeSituation, ReferenceKey) -> Bool
        let membership: [String: (index: UInt16, read: Read)] = [
            "GetAlarmed": (61, { $0.alarmed.contains($1) }),
            "IsTrespassing": (145, { $0.trespassers.contains($1) }),
            "IsActorAVictim": (314, { $0.victims.contains($1) }),
            "GetArrestingActor": (657, { $0.arrestingGuard == $1 }),
            "GetArrestedState": (656, { $1 == .player && $0.arrestingGuard != nil })
        ]
        for (name, (index, read)) in membership.sorted(by: { $0.key < $1.key }) {
            registry.register(ConditionFunction(index: index, name: name) { call in
                situation(call) { Self.isTrue(read($0, $1)) }
            })
        }
        registry.register(ConditionFunction(index: 144, name: "GetTrespassWarningLevel") { call in
            situation(call) { situation, warner in Float(situation.trespassWarnings[warner] ?? 0) }
        })
        registry.register(ConditionFunction(index: 499, name: "GetDaysInJail") { call in
            situation(call) { situation, _ in Float(situation.lastSentenceDays) }
        })
        registry.register(ConditionFunction(index: 125, name: "IsGuard") { call in
            policedFaction(call) { faction, _ in Self.isTrue(faction != nil) }
        })
        registry.register(ConditionFunction(index: 497, name: "CanPayCrimeGold") { call in
            policedFaction(call) { faction, situation in
                Self.isTrue(faction.map(situation.payableFactions.contains) ?? false)
            }
        })
        registry
            .register(ConditionFunction(index: 278, name: "IsOwner", parameter1: .formID) { call in
                guard
                    let parameter = call.parameter1,
                    let owner = call.context.crime.facts.resolvedKey(of: parameter.asFormID)
                else { return .failure(.unresolvedParameter(278)) }
                return situation(call) { situation, reference in
                    Self.isTrue(situation.owners[reference]?.key == owner)
                }
            })
    }

    private static func situation(
        _ call: ConditionCall,
        read: (CrimeSituation, ReferenceKey) -> Float
    ) -> Result<Float, ConditionFailure> {
        call.referenceKey().flatMap { key in
            guard let situation = call.context.crime.situation else {
                return .failure(.unavailableCrime)
            }
            return .success(read(situation, key))
        }
    }

    /// The crime faction the run-on actor polices, by the same rule the guards use.
    private static func policedFaction(
        _ call: ConditionCall,
        read: (ReferenceKey?, CrimeSituation) -> Float
    ) -> Result<Float, ConditionFailure> {
        let profiles = call.context.factions.facts
        guard profiles.isAvailable else { return .failure(.unavailableFactions) }
        return situation(call) { situation, key in
            let faction = profiles.fact(of: key).flatMap {
                GuardRecognition.policedFaction(of: $0, guardFaction: situation.guardFaction)
            }
            return read(faction, situation)
        }
    }
}
