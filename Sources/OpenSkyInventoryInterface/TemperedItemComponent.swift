// Tempered copies as a world-state component: per item, the quality level of each
// improved copy. Copies beyond the list are plain. Quality belongs to the copy, so a
// move takes the levels along: the lowest copies leave first. See docs/engine/crafting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// One owner's tempered copies.
nonisolated public struct TemperedItemState: WorldStateComponent, Sendable {
    /// Quality levels per item, highest first. Each entry is one copy.
    public private(set) var levels: [UInt32: [Int32]]

    public static var componentKind: WorldStateComponentKind {
        .temperedItems
    }

    /// Drops levels of zero or less and sorts each list, so a save decodes to the
    /// same state it encoded.
    public init(levels: [UInt32: [Int32]] = [:]) {
        self.levels = levels
            .mapValues { $0.filter { $0 > 0 }.sorted(by: >) }
            .filter { !$0.value.isEmpty }
    }

    public var isEmpty: Bool {
        levels.isEmpty
    }

    /// The level of each held copy of `item`, highest first. Plain copies read 0.
    public func copies(of item: FormID, held: Int32) -> [Int32] {
        let count = Int(max(0, held))
        let tempered = Array((levels[item.rawValue] ?? []).prefix(count))
        return tempered + Array(repeating: 0, count: count - tempered.count)
    }

    /// The best held copy, which is the one an equip picks.
    public func bestLevel(of item: FormID, held: Int32) -> Int32 {
        copies(of: item, held: held).first ?? 0
    }

    /// This state with one held copy of `item` at `from` raised to `to`.
    /// Nil when no held copy has level `from`.
    public func improving(
        _ item: FormID,
        held: Int32,
        from: Int32,
        to: Int32
    ) -> TemperedItemState? {
        var copies = copies(of: item, held: held)
        guard let index = copies.firstIndex(of: from) else { return nil }
        copies[index] = to
        var updated = levels
        updated[item.rawValue] = copies
        return TemperedItemState(levels: updated)
    }

    /// This state after `count` of the `held` copies of `item` leave, and the level
    /// of each copy that left. The lowest copies leave first, so the owner keeps
    /// the best one, which is the one an equip wears.
    public func taking(
        _ count: Int32, of item: FormID, held: Int32
    ) -> (remaining: TemperedItemState, taken: [Int32]) {
        let copies = copies(of: item, held: held)
        let leaving = min(Int(max(0, count)), copies.count)
        var updated = levels
        updated[item.rawValue] = Array(copies.dropLast(leaving))
        return (TemperedItemState(levels: updated), Array(copies.suffix(leaving)))
    }

    /// This state after copies at `arriving` levels join the `held` copies of `item`.
    public func giving(_ arriving: [Int32], of item: FormID, held: Int32) -> TemperedItemState {
        var updated = levels
        updated[item.rawValue] = copies(of: item, held: held) + arriving
        return TemperedItemState(levels: updated)
    }
}

nonisolated extension WorldStateComponentKind {
    /// Separate from `inventory`, because takes and drops rewrite that component and
    /// carry no quality.
    public static let temperedItems = Self(
        rawValue: "temperedItems", order: 30, affectsCellBuild: false
    )
}
