// Cell and worldspace condition functions. They read the loaded cell of each
// reference from `ConditionDataResolution`; a reference in no loaded cell fails.
// See docs/engine/condition-functions.md#places.

import Foundation
import OpenSkyFormatsESM

nonisolated extension ConditionFunctions {
    public static func installPlaces(_ registry: inout ConditionFunctionRegistry) {
        // "The cell must be an exact match" (<https://ck.uesp.net/wiki/GetInCell>).
        registry.register(ConditionFunction(
            index: 67, name: "GetInCell", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(67))
            }
            return Self.referenceCell(call).map { Self.isTrue($0.cell == parameter.asFormID) }
        })

        // "Always returns 0 if the actor is in an interior cell."
        // (<https://ck.uesp.net/wiki/GetInWorldspace>)
        registry.register(ConditionFunction(
            index: 310, name: "GetInWorldspace", parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(310))
            }
            return Self.referenceCell(call).map {
                Self.isTrue($0.worldspace == parameter.asFormID)
            }
        })

        // "Returns true if the calling reference is in the same cell as TargetRefID."
        // (<https://ck.uesp.net/wiki/GetInSameCell>)
        registry.register(ConditionFunction(
            index: 32, name: "GetInSameCell", parameter1: .formID
        ) { call in
            guard let other = Self.parameterKey(call, call.parameter1) else {
                return .failure(.unresolvedParameter(32))
            }
            guard let otherCell = call.context.data.cell(of: other) else {
                return .failure(.unavailableData(.cell))
            }
            return Self.referenceCell(call).map { Self.isTrue($0 == otherCell) }
        })
    }

    private static func referenceCell(
        _ call: ConditionCall
    ) -> Result<ReferenceCell, ConditionFailure> {
        call.referenceKey().flatMap { key in
            guard let cell = call.context.data.cell(of: key) else {
                return .failure(.unavailableData(.cell))
            }
            return .success(cell)
        }
    }
}
