// The implemented CTDA condition functions: only those answerable from owned state.
// The rest stay unregistered and `ConditionTally` counts them. Indices are raw (the
// Creation Kit adds 4096). Sources: UESP "CTDA Field", the Creation Kit wiki
// function list, and xEdit wbDefinitionsTES5.pas.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public enum ConditionFunctions: Sendable {
    /// The functions the core answers from state it owns: time, reference
    /// identity, globals, and story-event data. The record-data family (`installData`) is core
    /// too; the whole-game registry installs it in its own place.
    public static func installCore(into registry: inout ConditionFunctionRegistry) {
        installTime(&registry)
        installReference(&registry)
        installGlobals(&registry)
        installEventData(&registry)
    }

    // MARK: - Reference identity

    public static func installReference(_ registry: inout ConditionFunctionRegistry) {
        // xEdit TES5 condition table: index 35, `GetDisabled`, no parameters.
        // Creation Kit semantics: 1 when the run-on reference is disabled.
        registry.register(ConditionFunction(
            index: 35,
            name: "GetDisabled"
        ) { call in
            call.referenceIsDisabled().map(Self.isTrue)
        })

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
    public static func baseForm(of entry: RuntimeReferenceEntry) -> FormID {
        switch entry.record {
        case let .reference(reference): reference.base
        case let .actor(actor): actor.base
        }
    }

    // MARK: - Globals

    public static func installGlobals(_ registry: inout ConditionFunctionRegistry) {
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

        // Index 77 per xEdit; gib.me's list says 76. In Skyrim.esm 76 never appears and
        // 77 carries 1203 parameterless conditions compared against 0-100.
        // See docs/formats/conditions.md.
        registry.register(ConditionFunction(
            index: 77,
            name: "GetRandomPercent"
        ) { call in
            .success(Float(call.randomPercent()))
        })
    }

    /// Condition functions return 1 and 0 rather than a Bool, because the
    /// comparison that follows is numeric.
    public static func isTrue(_ value: Bool) -> Float {
        value ? 1 : 0
    }
}
