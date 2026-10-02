// The inventory condition function: 47 `GetItemCount` (ptInventoryObject), from
// xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas. Recipes use it to show only what
// the player holds the parts for. See docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// Item counts per holder, keyed by the item plugin's raw FormIDs.
nonisolated public struct InventoryConditionResolution: Sendable {
    public static let empty = InventoryConditionResolution()

    private let counts: [ReferenceKey: [FormID: Int32]]
    public let isAvailable: Bool

    public init(counts: [ReferenceKey: [FormID: Int32]]) {
        self.counts = counts
        isAvailable = true
    }

    private init() {
        counts = [:]
        isAvailable = false
    }

    /// Nil without inventory data. A holder with no entry holds nothing.
    public func count(of item: FormID, in holder: ReferenceKey) -> Int32? {
        guard isAvailable else { return nil }
        return counts[holder]?[item] ?? 0
    }
}

nonisolated extension InventoryConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var inventory: InventoryConditionResolution {
        get { self[resolution: InventoryConditionResolution.self] }
        set { self[resolution: InventoryConditionResolution.self] = newValue }
    }
}

nonisolated extension ConditionFunctions {
    public static func installInventory(_ registry: inout ConditionFunctionRegistry) {
        // "Returns the number of the specified item in the inventory of the
        // calling reference." (<https://ck.uesp.net/wiki/GetItemCount>)
        registry.register(ConditionFunction(
            index: 47,
            name: "GetItemCount",
            parameter1: .formID
        ) { call in
            guard let parameter = call.parameter1 else {
                return .failure(.unresolvedParameter(47))
            }
            return call.referenceKey().flatMap { holder in
                guard let count = call.context.inventory.count(of: parameter.asFormID, in: holder)
                else { return .failure(.unavailableData(.inventory)) }
                return .success(Float(count))
            }
        })
    }
}
