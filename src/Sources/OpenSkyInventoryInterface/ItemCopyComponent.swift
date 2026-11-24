// Item copies as a world-state component: per item, the copies that differ from the
// record, each with its temper level, trapped soul, enchantment charge, and made
// enchantment. Copies beyond the list are plain. What a copy holds belongs to it, so a
// move takes it along: the plainest copies leave first. See docs/engine/item-copies.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// One copy of an item, as far as it differs from its record.
nonisolated public struct ItemCopy: Hashable, Sendable {
    /// The temper quality level; 0 is untempered.
    public var level: Int32
    /// The `SoulLevel` raw value a soul gem copy holds; 0 is the record's own soul.
    public var soul: UInt8
    /// The enchantment charge left; nil is the full charge.
    public var charge: Float?
    /// The `ENCH` an enchanting table put on this copy.
    public var enchantment: FormID?
    /// The name typed at the enchanter; nil shows the record's name.
    public var name: String?
    /// The poison on this weapon copy and the hits it has left.
    public var poison: WeaponPoison?
    /// The copy the player last picked from a menu row. It sorts first, so an equip
    /// wears it.
    public var isChosen = false

    public init(
        level: Int32 = 0,
        soul: UInt8 = 0,
        charge: Float? = nil,
        enchantment: FormID? = nil
    ) {
        self.level = max(0, level)
        self.soul = soul
        self.charge = charge.map { $0.isFinite ? max(0, $0) : 0 }
        self.enchantment = enchantment
    }

    public static let plain = ItemCopy()

    public var isPlain: Bool {
        self == .plain
    }

    /// This copy with the menu's choice mark cleared, as a move hands it on.
    public var unchosen: ItemCopy {
        var copy = self
        copy.isChosen = false
        return copy
    }

    /// Best first: the chosen copy, then higher temper, then a made enchantment, then a
    /// bigger soul. Charge, name, and poison do not count, so a hit does not hand the
    /// equipped role to another copy; the sort is stable, so ties keep their stored order.
    static func isBefore(_ lhs: ItemCopy, _ rhs: ItemCopy) -> Bool {
        if lhs.isChosen != rhs.isChosen {
            return lhs.isChosen
        }
        if lhs.level != rhs.level {
            return lhs.level > rhs.level
        }
        let left = lhs.enchantment.map { UInt64($0.rawValue) + 1 } ?? 0
        let right = rhs.enchantment.map { UInt64($0.rawValue) + 1 } ?? 0
        if left != right {
            return left > right
        }
        return lhs.soul > rhs.soul
    }
}

/// One owner's copies that differ from their record.
nonisolated public struct ItemCopyState: WorldStateComponent, Sendable {
    /// Distinct copies per item, best first.
    public private(set) var copies: [UInt32: [ItemCopy]]

    public static var componentKind: WorldStateComponentKind {
        .itemCopies
    }

    /// Drops plain copies and sorts each list, so a save decodes to the state it encoded.
    public init(copies: [UInt32: [ItemCopy]] = [:]) {
        self.copies = copies
            .mapValues { $0.filter { !$0.isPlain }.sorted(by: ItemCopy.isBefore) }
            .filter { !$0.value.isEmpty }
    }

    /// Copies that differ only in temper level.
    public init(levels: [UInt32: [Int32]]) {
        self.init(copies: levels.mapValues { $0.map { ItemCopy(level: $0) } })
    }

    public var isEmpty: Bool {
        copies.isEmpty
    }

    /// The tempered levels per item, as the level-only save chunk stores them.
    public var levels: [UInt32: [Int32]] {
        copies.mapValues { $0.map(\.level).filter { $0 > 0 } }.filter { !$0.value.isEmpty }
    }

    /// Each held copy of `item`, best first. Copies beyond the list are plain.
    public func copies(of item: FormID, held: Int32) -> [ItemCopy] {
        let count = Int(max(0, held))
        let distinct = Array((copies[item.rawValue] ?? []).prefix(count))
        return (distinct + Array(repeating: .plain, count: count - distinct.count))
            .sorted(by: ItemCopy.isBefore)
    }

    /// The level of each held copy of `item`, highest first.
    public func levels(of item: FormID, held: Int32) -> [Int32] {
        copies(of: item, held: held).map(\.level)
    }

    /// The best held copy, which is the one an equip picks.
    public func bestCopy(of item: FormID, held: Int32) -> ItemCopy? {
        copies(of: item, held: held).first
    }

    public func bestLevel(of item: FormID, held: Int32) -> Int32 {
        bestCopy(of: item, held: held)?.level ?? 0
    }

    /// This state with the first held copy of `item` that `matches` changed by `edit`.
    /// Nil when no held copy matches.
    public func editing(
        _ item: FormID,
        held: Int32,
        where matches: (ItemCopy) -> Bool,
        _ edit: (inout ItemCopy) -> Void
    ) -> ItemCopyState? {
        var held = copies(of: item, held: held)
        guard let index = held.firstIndex(where: matches) else { return nil }
        edit(&held[index])
        var updated = copies
        updated[item.rawValue] = held
        return ItemCopyState(copies: updated)
    }

    /// This state with one held copy of `item` at level `from` raised to `to`.
    public func improving(_ item: FormID, held: Int32, from: Int32, to: Int32) -> ItemCopyState? {
        editing(item, held: held, where: { $0.level == from }, { $0.level = to })
    }

    /// This state after `count` of the `held` copies of `item` leave, and each copy that
    /// left. Copies equal to `preferring` leave first, as a move from a menu row takes
    /// that row's copies; then the plainest, so the owner keeps the best one.
    public func taking(
        _ count: Int32, of item: FormID, held: Int32, preferring: ItemCopy? = nil
    ) -> (remaining: ItemCopyState, taken: [ItemCopy]) {
        var held = copies(of: item, held: held)
        let leaving = min(Int(max(0, count)), held.count)
        var taken: [ItemCopy] = []
        while
            let preferring, taken.count < leaving,
            let index = held.lastIndex(where: { $0.unchosen == preferring.unchosen })
        {
            taken.append(held.remove(at: index))
        }
        let rest = leaving - taken.count
        taken += held.suffix(rest)
        held.removeLast(rest)
        var updated = copies
        updated[item.rawValue] = held
        return (ItemCopyState(copies: updated), taken.map(\.unchosen))
    }

    /// This state after `arriving` copies join the `held` copies of `item`.
    public func giving(_ arriving: [ItemCopy], of item: FormID, held: Int32) -> ItemCopyState {
        var updated = copies
        updated[item.rawValue] = copies(of: item, held: held) + arriving
        return ItemCopyState(copies: updated)
    }
}

nonisolated extension WorldStateComponentKind {
    /// Separate from `inventory`, because takes and drops rewrite that component and
    /// carry no copy state.
    public static let itemCopies = Self(
        rawValue: "itemCopies", order: 30, affectsCellBuild: false
    )
}
