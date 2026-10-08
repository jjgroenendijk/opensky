// The inventory condition functions: 47 `GetItemCount` (ptInventoryObject) and 659
// `EPTemperingItemIsEnchanted`, from xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas.
// Recipes use them. See docs/engine/condition-functions.md.

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

/// The item a tempering recipe would improve. Empty outside a tempering check.
nonisolated public struct TemperingConditionResolution: Sendable {
    public static let empty = TemperingConditionResolution(isEnchanted: nil)

    /// Nil when no item is being tempered.
    public let isEnchanted: Bool?

    public init(isEnchanted: Bool?) {
        self.isEnchanted = isEnchanted
    }
}

nonisolated extension TemperingConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    public var inventory: InventoryConditionResolution {
        get { self[resolution: InventoryConditionResolution.self] }
        set { self[resolution: InventoryConditionResolution.self] = newValue }
    }

    public var tempering: TemperingConditionResolution {
        get { self[resolution: TemperingConditionResolution.self] }
        set { self[resolution: TemperingConditionResolution.self] = newValue }
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
        // Vanilla tempering recipes pair `!= 1` with `HasPerk ArcaneBlacksmith`
        // in an OR group. The function reads the item, not the run-on reference.
        registry.register(ConditionFunction(
            index: 659,
            name: "EPTemperingItemIsEnchanted"
        ) { call in
            guard let enchanted = call.context.tempering.isEnchanted else {
                return .failure(.unavailableData(.inventory))
            }
            return .success(enchanted ? 1 : 0)
        })
    }
}
