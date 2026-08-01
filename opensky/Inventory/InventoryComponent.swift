// Inventory as a world-state component (issue #176, roadmap item 12.1.2): the
// value type that holds one owner's items once anything has touched them.
//
// The component lives here rather than in `WorldStateComponents.swift` because
// it is the one component with real behaviour of its own — stack arithmetic
// and an equipped set — while the other four are plain field bags. Only the
// `WorldStateComponentKind` case and the `WorldStateComponentValue` case sit
// with the rest; every store operation stays generic over the protocol.
//
// Full-override model: the component holds the owner's *entire* effective
// inventory, not a delta against the plugin baseline. The first mutation
// materializes the baseline into the component and everything afterwards edits
// that. An owner nothing has touched has no component at all and re-derives
// from plugin data through `InventoryBaselineResolver`. This is what keeps
// leveled and templated baselines out of delta arithmetic: a CONT whose CNTO
// list points at an LVLI has no stable "minus one iron sword" representation,
// but it does have a stable resolved list, and once the player has opened the
// chest the resolved list is the truth.
//
// Two invariants hold for every value of this type, enforced in `init` rather
// than checked at use sites:
//
// * `stacks` is sorted by item FormID ascending, with one entry per item and
//   every count strictly positive. Sorting is what makes a snapshot of two
//   stores that reached the same end state byte-identical.
// * `equipped` is sorted ascending and free of duplicates, for the same reason.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One stack of identical items: a base FormID and how many of it there are.
///
/// v1 stacks by base FormID alone, matching `ItemDefinition.stackKey`. Per-
/// instance data — tempering, enchanting, charge level — makes two instances of
/// the same base distinct and will turn this into a compound key; see
/// docs/formats/records.md.
nonisolated struct InventoryStack: Equatable, Sendable {
    /// Base item record: MISC, BOOK, ALCH, INGR, WEAP, AMMO or ARMO.
    let item: FormID
    /// How many. Always strictly positive inside a `ReferenceInventoryState`.
    let count: Int32
}

/// Failures the inventory layer reports. Every one of them is a caller mistake
/// rather than malformed input, which is why they are distinct from
/// `ESMError` — there is no file being parsed here.
nonisolated enum InventoryError: Error, Equatable {
    /// A count that is zero or negative was passed to `add` or `remove`.
    /// Moving "minus three" items is never what a caller meant.
    case nonPositiveCount(Int32)
    /// More was removed than the owner holds. Deliberately a failure rather
    /// than a clamp: silently removing four of three items is how conservation
    /// bugs hide.
    case insufficientCount(item: FormID, owner: ReferenceKey, requested: Int32, available: Int32)
    /// The resulting stack would not fit in `Int32`.
    case countOverflow(item: FormID, owner: ReferenceKey)
    /// A transfer whose source and destination are the same owner.
    case sameHolder(ReferenceKey)
}

/// Every item one owner holds, plus which of them are equipped.
nonisolated struct ReferenceInventoryState: WorldStateComponent {
    /// Stacks sorted by item FormID ascending, one per item, counts positive.
    private(set) var stacks: [InventoryStack]
    /// Equipped base FormIDs, sorted ascending and unique.
    ///
    /// Storage only. Slot conflicts and ARMA arbitration are issue #178's; this
    /// issue journals the set and puts it in the save so that work has
    /// somewhere to land.
    private(set) var equipped: [FormID]

    /// Nothing held and nothing equipped, which is also the player's baseline.
    static let empty = ReferenceInventoryState()

    static var componentKind: WorldStateComponentKind {
        .inventory
    }

    var erased: WorldStateComponentValue {
        .inventory(self)
    }

    /// Normalizes on the way in: duplicate items merge, non-positive counts
    /// drop out, and both arrays come out sorted. A merge that would overflow
    /// `Int32` saturates rather than throwing — this initializer is also the
    /// save decoder's entry point, and a corrupt file must degrade rather than
    /// fail the whole load, while the mutation API above refuses the same
    /// arithmetic outright.
    init(stacks: [InventoryStack] = [], equipped: [FormID] = []) {
        var merged: [UInt32: Int32] = [:]
        // `signum()` rather than a comparison against zero: a stack count is a
        // quantity, not a collection size, so the lint rule that rewrites
        // `count > 0` into `isEmpty` would be rewriting the wrong thing.
        for stack in stacks where stack.count.signum() == 1 {
            let running = Int64(merged[stack.item.rawValue] ?? 0) + Int64(stack.count)
            merged[stack.item.rawValue] = Int32(clamping: running)
        }
        self.stacks = merged
            .map { InventoryStack(item: FormID($0.key), count: $0.value) }
            .sorted { $0.item.rawValue < $1.item.rawValue }
        self.equipped = Set(equipped.map(\.rawValue)).sorted().map(FormID.init)
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .inventory(value) = erased else { return nil }
        self = value
    }

    // MARK: - Reading

    var isEmpty: Bool {
        stacks.isEmpty && equipped.isEmpty
    }

    /// How many of `item` the owner holds; 0 when it holds none.
    func count(of item: FormID) -> Int32 {
        stacks.first { $0.item == item }?.count ?? 0
    }

    /// Total number of individual items across every stack.
    ///
    /// `Int` rather than `Int32`, because a conservation test sums this across
    /// owners and the sum of two valid inventories can exceed a single stack's
    /// range.
    var totalCount: Int {
        stacks.reduce(0) { $0 + Int($1.count) }
    }

    func isEquipped(_ item: FormID) -> Bool {
        equipped.contains(item)
    }

    // MARK: - Stack arithmetic

    /// This inventory with `count` more of `item`.
    ///
    /// - Throws: `InventoryError.nonPositiveCount` for a count of zero or less,
    ///   `InventoryError.countOverflow` when the stack would leave `Int32`.
    func adding(_ item: FormID, count: Int32, owner: ReferenceKey) throws -> Self {
        guard count > 0 else { throw InventoryError.nonPositiveCount(count) }
        let total = Int64(self.count(of: item)) + Int64(count)
        guard total <= Int64(Int32.max) else {
            throw InventoryError.countOverflow(item: item, owner: owner)
        }
        return replacing(item, with: Int32(total))
    }

    /// This inventory with `count` fewer of `item`, dropping the stack when it
    /// reaches zero.
    ///
    /// - Throws: `InventoryError.nonPositiveCount` for a count of zero or less,
    ///   `InventoryError.insufficientCount` when the owner holds fewer.
    func removing(_ item: FormID, count: Int32, owner: ReferenceKey) throws -> Self {
        guard count > 0 else { throw InventoryError.nonPositiveCount(count) }
        let available = self.count(of: item)
        guard available >= count else {
            throw InventoryError.insufficientCount(
                item: item, owner: owner, requested: count, available: available
            )
        }
        return replacing(item, with: available - count)
    }

    // MARK: - Equipped set

    /// This inventory with `item` marked equipped. Equipping something already
    /// equipped changes nothing.
    func equipping(_ item: FormID) -> Self {
        var result = self
        result.equipped = Set(equipped.map(\.rawValue))
            .union([item.rawValue])
            .sorted()
            .map(FormID.init)
        return result
    }

    /// This inventory with `item` no longer equipped.
    func unequipping(_ item: FormID) -> Self {
        var result = self
        result.equipped = equipped.filter { $0 != item }
        return result
    }

    /// This inventory with the whole equipped set replaced, normalized the same
    /// way `init` normalizes it.
    func settingEquipped(_ items: [FormID]) -> Self {
        ReferenceInventoryState(stacks: stacks, equipped: items)
    }

    // MARK: - Private

    /// This inventory with `item`'s stack set to exactly `count`, keeping the
    /// FormID ordering intact and removing the stack at zero.
    private func replacing(_ item: FormID, with count: Int32) -> Self {
        var result = self
        result.stacks.removeAll { $0.item == item }
        if count > 0 {
            let stack = InventoryStack(item: item, count: count)
            let index = result.stacks.firstIndex { $0.item.rawValue > item.rawValue }
            result.stacks.insert(stack, at: index ?? result.stacks.endIndex)
        }
        return result
    }
}
