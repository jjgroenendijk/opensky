// 432 GetIsObjectType and 487 IsCarryable, from xEdit wbDefinitionsTES5.pas. The
// parameter is xEdit's `wbFormTypeEnum`.
// See docs/engine/condition-functions-world.md#reference-state.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension ConditionFunctions {
    /// `wbFormTypeEnum` values for the base types a placed reference can have.
    static let objectTypes: [Int32: FourCC] = {
        let names: [Int32: String] = [
            0: "ACTI", 1: "ARMO", 2: "BOOK", 3: "CONT", 4: "DOOR", 5: "INGR", 6: "LIGH",
            7: "MISC", 8: "STAT", 9: "GRAS", 10: "TREE", 12: "WEAP", 13: "NPC_", 14: "LVLN",
            17: "ALCH", 18: "LVLI", 19: "KEYM", 20: "AMMO", 21: "FLOR", 22: "FURN",
            23: "SOUN", 30: "IDLM", 33: "TACT", 42: "MSTT", 90: "APPA", 97: "SLGM",
            100: "SCRL"
        ]
        return names.mapValues { FourCC(stringLiteral: $0) }
    }()

    /// Base types that go into an inventory when taken. A light is carried only with
    /// its `DATA` flag, which the record index does not hold.
    static let carryableTypes: Set<FourCC> = [
        "WEAP", "ARMO", "BOOK", "INGR", "MISC", "ALCH", "KEYM", "AMMO", "SLGM", "SCRL",
        "APPA"
    ]

    static func installObjectType(_ registry: inout ConditionFunctionRegistry) {
        registry.register(ConditionFunction(
            index: 432, name: "GetIsObjectType", parameter1: .integer
        ) { call in
            guard let wanted = call.parameter1.flatMap({ objectTypes[$0.asInt32] }) else {
                return .failure(.unresolvedParameter(432))
            }
            return baseRecordType(call).map { isTrue($0 == wanted) }
        })
        registry.register(ConditionFunction(index: 487, name: "IsCarryable") { call in
            baseRecordType(call).flatMap { type in
                guard type != "LIGH" else { return .failure(.unavailableData(.keyword)) }
                return .success(isTrue(carryableTypes.contains(type)))
            }
        })
    }

    /// The record type of the run-on's base form. The player is an `NPC_`.
    private static func baseRecordType(_ call: ConditionCall) -> Result<FourCC, ConditionFailure> {
        call.referenceKey().flatMap { key in
            if key.namingPlayer == .player {
                return .success("NPC_")
            }
            guard let entry = call.context.references[key] else {
                return .failure(.unresolvedReference(call.condition.runOn))
            }
            guard
                let store = call.context.data.keywords,
                let base = store.resolvedID(
                    baseForm(of: entry), fromPlugin: basePlugin(of: entry.key)
                ),
                let type = store.recordType(of: base)
            else { return .failure(.unavailableData(.keyword)) }
            return .success(type)
        }
    }
}
