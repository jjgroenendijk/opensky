// The inventory condition functions: 47 `GetItemCount` (ptInventoryObject), 48 `GetGold`,
// 182 `GetEquipped`, and 659 `EPTemperingItemIsEnchanted`, from xEdit dev-4.1.6
// Core/wbDefinitionsTES5.pas.
// Recipes use them. See docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// Reads one holder's items on demand, so a condition can ask about any actor or
/// container, not only the holders a context copied in. Each answers nil without a holder.
nonisolated public struct InventoryConditionLookup: Sendable {
    public let count: @Sendable (FormID, ReferenceKey) -> Int32?
    public let isEquipped: @Sendable (FormID, ReferenceKey) -> Bool?
    public let keywordCounts: @Sendable (ReferenceKey) -> [FormID: Int32]?

    public init(
        count: @escaping @Sendable (FormID, ReferenceKey) -> Int32?,
        isEquipped: @escaping @Sendable (FormID, ReferenceKey) -> Bool?,
        keywordCounts: @escaping @Sendable (ReferenceKey) -> [FormID: Int32]?
    ) {
        self.count = count
        self.isEquipped = isEquipped
        self.keywordCounts = keywordCounts
    }
}

/// Item counts per holder, keyed by the item plugin's raw FormIDs. A holder the
/// tables do not name is read through `lookup`.
nonisolated public struct InventoryConditionResolution: Sendable {
    public static let empty = InventoryConditionResolution()

    private let counts: [ReferenceKey: [FormID: Int32]]
    private let equipped: [ReferenceKey: Set<FormID>]
    private let equipment: [ReferenceKey: ActorEquipmentFacts]
    /// Items per KWDA keyword, summed over each holder's stacks.
    private let keywordCounts: [ReferenceKey: [FormID: Int32]]
    private let lookup: InventoryConditionLookup?
    public let isAvailable: Bool

    public init(
        counts: [ReferenceKey: [FormID: Int32]],
        equipped: [ReferenceKey: Set<FormID>] = [:],
        equipment: [ReferenceKey: ActorEquipmentFacts] = [:],
        keywordCounts: [ReferenceKey: [FormID: Int32]] = [:],
        lookup: InventoryConditionLookup? = nil
    ) {
        self.counts = counts
        self.equipped = equipped
        self.equipment = equipment
        self.keywordCounts = keywordCounts
        self.lookup = lookup
        isAvailable = true
    }

    private init() {
        counts = [:]
        equipped = [:]
        equipment = [:]
        keywordCounts = [:]
        lookup = nil
        isAvailable = false
    }

    /// Nil without equipment data for `actor`.
    public func equipment(of actor: ReferenceKey) -> ActorEquipmentFacts? {
        equipment[actor]
    }

    /// Nil without inventory data for `holder`.
    public func count(ofKeyword keyword: FormID, in holder: ReferenceKey) -> Int32? {
        guard counts[holder] != nil else {
            return lookup?.keywordCounts(holder).map { $0[keyword] ?? 0 }
        }
        return keywordCounts[holder]?[keyword] ?? 0
    }

    /// Nil without inventory data. A holder neither the tables nor the lookup know
    /// holds nothing.
    public func count(of item: FormID, in holder: ReferenceKey) -> Int32? {
        guard isAvailable else { return nil }
        if let table = counts[holder] {
            return table[item] ?? 0
        }
        return lookup?.count(item, holder) ?? 0
    }

    /// Nil without equipment data for `holder`.
    public func isEquipped(_ item: FormID, on holder: ReferenceKey) -> Bool? {
        equipped[holder]?.contains(item) ?? lookup?.isEquipped(item, holder)
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
        installGoldAndEquipment(&registry)
        installEquipment(&registry)
    }

    /// `Gold001`, the septim, in `Skyrim.esm` (UESP "Skyrim:Gold").
    public static let goldItem = FormID(0x0000_000F)

    private static func installGoldAndEquipment(_ registry: inout ConditionFunctionRegistry) {
        // How many `Gold001` the run-on holds.
        registry.register(ConditionFunction(index: 48, name: "GetGold") { call in
            call.referenceKey().flatMap { holder in
                guard let count = call.context.inventory.count(of: Self.goldItem, in: holder)
                else { return .failure(.unavailableData(.inventory)) }
                return .success(Float(count))
            }
        })

        // xEdit `ptInventoryObject`: 1 when the run-on actor has the item equipped.
        registry.register(ConditionFunction(
            index: 182, name: "GetEquipped", parameter1: .formID
        ) { call in
            guard let item = call.parameter1 else { return .failure(.unresolvedParameter(182)) }
            return call.referenceKey().flatMap { holder in
                guard let equipped = call.context.inventory.isEquipped(item.asFormID, on: holder)
                else { return .failure(.unavailableData(.inventory)) }
                return .success(Self.isTrue(equipped))
            }
        })
    }
}
