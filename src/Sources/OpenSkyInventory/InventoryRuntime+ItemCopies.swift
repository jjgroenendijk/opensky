// Per-copy reads and moves. Copy state lives in its own component; every inventory
// move in `InventoryRuntime` carries the copies it moves. See docs/engine/item-copies.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyInventoryInterface
import OpenSkyWorldState

extension InventoryRuntime {
    public func itemCopies(of holder: InventoryHolder) -> ItemCopyState {
        store.component(ItemCopyState.self, for: holder.key) ?? ItemCopyState()
    }

    /// The quality of the best held copy of `item`, which is the copy an equip wears.
    public func temperLevel(of item: FormID, in holder: InventoryHolder) -> Int32 {
        itemCopies(of: holder).bestLevel(of: item, held: count(of: item, in: holder))
    }

    /// Each held copy of `item`, best first.
    public func copies(of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        itemCopies(of: holder).copies(of: item, held: count(of: item, in: holder))
    }

    /// Changes the first held copy of `item` that `matches`. False when none matches.
    @discardableResult
    public func editCopy(
        of item: FormID,
        in holder: InventoryHolder,
        where matches: (ItemCopy) -> Bool,
        _ edit: (inout ItemCopy) -> Void
    ) -> Bool {
        let held = count(of: item, in: holder)
        guard let updated = itemCopies(of: holder).editing(item, held: held, where: matches, edit)
        else { return false }
        writeCopies(updated, for: holder)
        return true
    }

    /// The `count` copies of `item` a move out of `holder` takes: the plainest ones.
    /// Read before the move, because the move changes the held count.
    func leavingCopies(_ count: Int32, of item: FormID, in holder: InventoryHolder) -> [ItemCopy] {
        itemCopies(of: holder).taking(
            count, of: item, held: self.count(of: item, in: holder),
            preferring: actingCopy.preferred(for: item)
        ).taken
    }

    /// Runs `body` as an action on one menu row's `copy` of `item`: that copy is marked
    /// chosen, so an equip wears it, and a move takes it first.
    public func acting<Result>(
        on copy: ItemCopy?, of item: FormID, in holder: InventoryHolder,
        _ body: () throws -> Result
    ) rethrows -> Result {
        guard let copy else { return try body() }
        choose(copy, of: item, in: holder)
        let saved = actingCopy.current
        actingCopy.current = (item, copy.unchosen)
        defer { actingCopy.current = saved }
        return try body()
    }

    /// Marks the first held copy equal to `copy` chosen and clears the mark on the rest.
    private func choose(_ copy: ItemCopy, of item: FormID, in holder: InventoryHolder) {
        let held = count(of: item, in: holder)
        var copies = itemCopies(of: holder).copies(of: item, held: held).map(\.unchosen)
        guard let index = copies.firstIndex(of: copy.unchosen) else { return }
        copies[index].isChosen = true
        var state = itemCopies(of: holder).copies
        state[item.rawValue] = copies
        writeCopies(ItemCopyState(copies: state), for: holder)
    }

    /// Rewrites `holder`'s copy list after `item` changed from `before` held copies:
    /// `taken` copies left, then `arriving` copies came in.
    func recopy(
        _ item: FormID,
        in holder: InventoryHolder,
        before: Int32,
        taken: Int32 = 0,
        arriving: [ItemCopy] = []
    ) {
        let state = itemCopies(of: holder)
        guard state.copies[item.rawValue] != nil || arriving.contains(where: { !$0.isPlain })
        else { return }
        let remaining = state.taking(
            taken, of: item, held: before, preferring: actingCopy.preferred(for: item)
        ).remaining
        let updated = remaining.giving(arriving, of: item, held: max(0, before - taken))
        writeCopies(updated, for: holder)
    }

    func writeCopies(_ state: ItemCopyState, for holder: InventoryHolder) {
        if state.isEmpty {
            store.reset(ItemCopyState.componentKind, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
    }
}

/// The copy a menu row acts on while its action runs.
final class ActingCopy {
    var current: (item: FormID, copy: ItemCopy)?

    func preferred(for item: FormID) -> ItemCopy? {
        current?.item == item ? current?.copy : nil
    }
}
