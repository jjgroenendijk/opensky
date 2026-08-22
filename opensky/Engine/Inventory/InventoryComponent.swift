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
// * `stacks` is sorted by item FormID ascending and then by the stolen flag,
//   honest copies before stolen ones, with one entry per (item, stolen) pair
//   and every count strictly positive. Sorting is what makes a snapshot of two
//   stores that reached the same end state byte-identical.
// * `equipped` is sorted ascending and free of duplicates, for the same reason.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One stack of identical items: a base FormID, whether they were stolen, and
/// how many of it there are.
///
/// v1 stacks by base FormID plus the stolen flag, matching
/// `ItemDefinition.stackKey` widened by the one distinction crime introduces.
/// Per-instance data — tempering, enchanting, charge level — makes two
/// instances of the same base distinct and will widen the key further; see
/// docs/formats/records.md.
///
/// The stolen flag is part of the key rather than a property of the whole item
/// because the original tracks it per copy: "Should you steal multiple items of
/// the same type, each item considered stolen is tracked separately when
/// dropped" (<https://en.uesp.net/wiki/Skyrim:Crime>). Ten honest arrows and
/// one stolen arrow are therefore two stacks of the same base (issue #504).
nonisolated struct InventoryStack: Equatable, Sendable {
    /// Base item record: MISC, BOOK, ALCH, INGR, WEAP, AMMO or ARMO.
    let item: FormID
    /// How many. Always strictly positive inside a `ReferenceInventoryState`.
    let count: Int32
    /// Whether these copies were taken from somebody who owned them. "Stolen
    /// items in your inventory will be marked with the word 'Stolen', even if
    /// you were able to steal the item without being detected" (same page), so
    /// the flag follows the goods rather than the bounty.
    let stolen: Bool

    /// Defaulted so every call site that predates crime still reads as honest
    /// goods, which is what an item nothing marked actually is.
    init(item: FormID, count: Int32, stolen: Bool = false) {
        self.item = item
        self.count = count
        self.stolen = stolen
    }
}

/// How a removal of one item divides between honest and stolen copies.
///
/// Returned rather than inferred by the caller so a transfer can put the same
/// division back down on the other side: moving three arrows out of a stack of
/// two honest and two stolen has to arrive as two honest and one stolen, not as
/// three of whichever the destination happened to hold.
nonisolated struct StolenSplit: Equatable, Sendable {
    let clean: Int32
    let stolen: Int32

    static let none = StolenSplit(clean: 0, stolen: 0)

    var total: Int32 {
        clean + stolen
    }

    var isEmpty: Bool {
        total <= 0
    }
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
    /// Stacks sorted by item FormID and then by the stolen flag, one per
    /// (item, stolen) pair, counts positive.
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
        var merged: [StackKey: Int32] = [:]
        // `signum()` rather than a comparison against zero: a stack count is a
        // quantity, not a collection size, so the lint rule that rewrites
        // `count > 0` into `isEmpty` would be rewriting the wrong thing.
        for stack in stacks where stack.count.signum() == 1 {
            let key = StackKey(item: stack.item.rawValue, stolen: stack.stolen)
            let running = Int64(merged[key] ?? 0) + Int64(stack.count)
            merged[key] = Int32(clamping: running)
        }
        self.stacks = merged.keys.sorted().compactMap { key in
            guard let count = merged[key] else { return nil }
            return InventoryStack(item: FormID(key.item), count: count, stolen: key.stolen)
        }
        self.equipped = Set(equipped.map(\.rawValue)).sorted().map(FormID.init)
    }

    /// The compound stack key: base form, then honest before stolen. Ordering
    /// is total so a snapshot of two stores that reached the same end state
    /// stays byte-identical.
    private struct StackKey: Hashable, Comparable {
        let item: UInt32
        let stolen: Bool

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.item == rhs.item ? (!lhs.stolen && rhs.stolen) : lhs.item < rhs.item
        }
    }

    init?(erased: WorldStateComponentValue) {
        guard case let .inventory(value) = erased else { return nil }
        self = value
    }

    // MARK: - Reading

    var isEmpty: Bool {
        stacks.isEmpty && equipped.isEmpty
    }

    /// How many of `item` the owner holds, honest and stolen copies together;
    /// 0 when it holds none.
    ///
    /// The total rather than one flavour, because that is what every question
    /// that predates crime means by "how many do I have" — a quest that wants
    /// five ingots does not care where they came from.
    func count(of item: FormID) -> Int32 {
        Int32(clamping: stacks.reduce(Int64(0)) { $0 + ($1.item == item ? Int64($1.count) : 0) })
    }

    /// How many of `item` the owner holds with exactly this stolen flag.
    func count(of item: FormID, stolen: Bool) -> Int32 {
        stacks.first { $0.item == item && $0.stolen == stolen }?.count ?? 0
    }

    /// How many stolen copies of `item` the owner holds, which is what a
    /// merchant refusing hot goods and a "Stolen" marker both read.
    func stolenCount(of item: FormID) -> Int32 {
        count(of: item, stolen: true)
    }

    /// Whether any copy of `item` here is stolen, which is what an inventory
    /// row's marker shows.
    func isStolen(_ item: FormID) -> Bool {
        stolenCount(of: item) > 0
    }

    /// How a removal of `count` of `item` divides between honest and stolen
    /// copies.
    ///
    /// Honest copies go first, so an inventory that holds both spends the ones
    /// that carry no consequence before the ones that do. The split is clamped
    /// to what is actually held, so a caller that asks for more than there is
    /// sees a smaller `total` rather than a negative flavour.
    func split(taking count: Int32, of item: FormID) -> StolenSplit {
        guard count > 0 else { return .none }
        let clean = min(count, self.count(of: item, stolen: false))
        let stolen = min(count - clean, self.count(of: item, stolen: true))
        return StolenSplit(clean: clean, stolen: stolen)
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

    /// This inventory with `count` more of `item`, honest unless `stolen` says
    /// otherwise.
    ///
    /// - Throws: `InventoryError.nonPositiveCount` for a count of zero or less,
    ///   `InventoryError.countOverflow` when the stack would leave `Int32`.
    func adding(
        _ item: FormID,
        count: Int32,
        owner: ReferenceKey,
        stolen: Bool = false
    ) throws -> Self {
        guard count > 0 else { throw InventoryError.nonPositiveCount(count) }
        let total = Int64(self.count(of: item, stolen: stolen)) + Int64(count)
        guard total <= Int64(Int32.max) else {
            throw InventoryError.countOverflow(item: item, owner: owner)
        }
        return replacing(item, stolen: stolen, with: Int32(total))
    }

    /// This inventory with `split` more of `item`: its honest copies honest and
    /// its stolen ones stolen.
    ///
    /// The counterpart of `split(taking:of:)`, so a transfer puts down exactly
    /// the division it picked up.
    func adding(_ item: FormID, split: StolenSplit, owner: ReferenceKey) throws -> Self {
        var result = self
        if split.clean > 0 {
            result = try result.adding(item, count: split.clean, owner: owner, stolen: false)
        }
        if split.stolen > 0 {
            result = try result.adding(item, count: split.stolen, owner: owner, stolen: true)
        }
        return result
    }

    /// This inventory with `count` fewer of `item`, spending honest copies
    /// first and dropping each stack as it reaches zero.
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
        let split = split(taking: count, of: item)
        var result = self
        if split.clean > 0 {
            result = result.replacing(
                item, stolen: false, with: self.count(of: item, stolen: false) - split.clean
            )
        }
        if split.stolen > 0 {
            result = result.replacing(
                item, stolen: true, with: self.count(of: item, stolen: true) - split.stolen
            )
        }
        return result
    }

    /// This inventory with `count` of `item` re-marked stolen.
    ///
    /// The door a take out of an owned container comes through: the goods are
    /// already in hand and what changes is their standing. More than the owner
    /// holds marks everything it holds rather than throwing — this is a
    /// bookkeeping correction, not a movement, and there is nothing to conserve.
    func markingStolen(_ item: FormID, count: Int32) -> Self {
        let moved = min(max(0, count), self.count(of: item, stolen: false))
        guard moved > 0 else { return self }
        return replacing(item, stolen: false, with: self.count(of: item, stolen: false) - moved)
            .replacing(item, stolen: true, with: self.count(of: item, stolen: true) + moved)
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

    /// This inventory with one flavour of `item`'s stack set to exactly
    /// `count`, keeping the (form, stolen) ordering intact and removing the
    /// stack at zero.
    private func replacing(_ item: FormID, stolen: Bool, with count: Int32) -> Self {
        var result = self
        result.stacks.removeAll { $0.item == item && $0.stolen == stolen }
        guard count > 0 else { return result }
        let stack = InventoryStack(item: item, count: count, stolen: stolen)
        let index = result.stacks.firstIndex {
            $0.item.rawValue > item.rawValue || ($0.item == item && $0.stolen && !stolen)
        }
        result.stacks.insert(stack, at: index ?? result.stacks.endIndex)
        return result
    }
}
