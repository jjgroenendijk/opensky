// The implemented CTDA condition functions (issue #251).
//
// Five to start, chosen because the engine can already answer them honestly
// from state it owns: the game clock, the globals seam, and the runtime
// reference index. Anything else stays unregistered and is counted by
// `ConditionTally` rather than guessed at.
//
// Indices below are the raw stored numbers; the Creation Kit spells each 4096
// higher. Sources: UESP "Skyrim Mod:Mod File Format/CTDA Field" for the
// encoding, the Creation Kit wiki condition-function list for names and return
// values, and xEdit dev Core/wbDefinitionsTES5.pas for the index table.

import Foundation

nonisolated enum ConditionFunctions {
    static func install(into registry: inout ConditionFunctionRegistry) {
        installTime(&registry)
        installReference(&registry)
        installGlobals(&registry)
    }

    // MARK: - Reference identity

    static func installReference(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 72,
            name: "GetIsID",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(72))
            }
            return call.reference().map { entry in
                Self.isTrue(Self.baseForm(of: entry) == parameter.asFormID)
            }
        })
    }

    /// The base object a placement stands for. Both placement records carry it
    /// in their NAME subrecord, decoded as `base`.
    static func baseForm(of entry: RuntimeReferenceEntry) -> FormID {
        switch entry.record {
        case let .reference(reference): reference.base
        case let .actor(actor): actor.base
        }
    }

    // MARK: - Globals

    static func installGlobals(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 74,
            name: "GetGlobalValue",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(74))
            }
            return call.global(parameter.asFormID)
        })

        // Index 77 per xEdit's TES5 condition-function table. gib.me's older
        // Fallout-era list numbers GetRandomPercent 4172 (stored 76), so the
        // two open sources disagree by one. The vanilla sweep settles it for
        // xEdit: stored index 76 never appears in Skyrim.esm, while 77 carries
        // 1203 conditions that all leave both parameter words zero and compare
        // against values spanning 0 to 100 — the no-parameter percentage
        // signature. Evidence recorded in docs/formats/conditions.md.
        registry.register(ConditionFunction(
            index: 77,
            name: "GetRandomPercent"
        ) { call in
            .success(Float(call.randomPercent()))
        })
    }

    /// Condition functions return 1 and 0 rather than a Bool, because the
    /// comparison that follows is numeric.
    static func isTrue(_ value: Bool) -> Float {
        value ? 1 : 0
    }
}
