// Worn enchantments: armor, robes, rings, and amulets grant their effects while
// worn. Written as a reconcile, so every equip path calls it and a second call
// changes nothing. `EnchantedItemState` records each item's effect sequences,
// so removal is exact even when two items share an ENCH. Effects apply as
// unscaled constants, without resistances. See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// What one reconciliation did.
nonisolated public struct WornEnchantmentReport: Equatable, Sendable {
    /// Items whose effects were applied this time, ascending.
    public let applied: [FormID]
    /// Items whose effects were taken back off, ascending.
    public let removed: [FormID]
    /// Constant effects stored across every newly worn item.
    public let storedCount: Int
    /// Effects dispelled across every item that came off.
    public let dispelledCount: Int

    public static let none = WornEnchantmentReport(
        applied: [], removed: [], storedCount: 0, dispelledCount: 0
    )

    /// Whether anything moved, which is what tells a caller to refresh a readout.
    public var didChange: Bool {
        !applied.isEmpty || !removed.isEmpty
    }
}

@MainActor
public enum WornEnchantmentApplication {
    /// Brings `holder`'s constant effects in line with what it is wearing.
    ///
    /// - Parameter worn: the resolved enchantment of every item `holder` has
    ///   equipped that carries one. An entry that is not a constant effect — a
    ///   drawn enchanted sword, a staff — is ignored here rather than filtered by
    ///   the caller, so no caller has to know the rule.
    @discardableResult
    public static func reconcile(
        worn: [ItemEnchantmentProfile],
        on holder: ActorValueHolder,
        using runtime: inout ActiveEffectRuntime
    ) -> WornEnchantmentReport {
        let ledger = EnchantmentLedger(store: runtime.store)
        let profiles = worn.filter(\.isWorn)
        let wanted = Set(profiles.map(\.item.rawValue))
        var state = ledger.state(of: holder)
        var removed: [FormID] = []
        var dispelledCount = 0
        for item in state.wornItems where !wanted.contains(item.rawValue) {
            let sequences = Set(state.wornEffects(of: item))
            dispelledCount += runtime.dispel(on: holder) { sequences.contains($0.sequence) }
            state = state.setting(wornEffects: [], of: item)
            removed.append(item)
        }
        ledger.write(state, for: holder)
        var applied: [FormID] = []
        var storedCount = 0
        for profile in profiles.sorted(by: { $0.item.rawValue < $1.item.rawValue })
            where ledger.state(of: holder).wornEffects(of: profile.item).isEmpty
        {
            let stored = runtime.apply(
                profile.entries,
                fromPlugin: profile.sourcePlugin,
                source: profile.source,
                isConstant: true,
                on: holder
            )
            // An item whose every entry was refused establishes nothing and is
            // deliberately not recorded: recording it would make the next
            // reconcile skip an item that is granting nothing, and there would be
            // no sequence to dispel when it came off.
            guard !stored.isEmpty else { continue }
            ledger.setWornEffects(stored.map(\.sequence), of: profile.item, on: holder)
            storedCount += stored.count
            applied.append(profile.item)
        }
        return WornEnchantmentReport(
            applied: applied,
            removed: removed,
            storedCount: storedCount,
            dispelledCount: dispelledCount
        )
    }

    /// Takes every worn enchantment off `holder` and forgets them, which is what
    /// an `unequipAll` and a dev control mean.
    @discardableResult
    public static func removeAll(
        on holder: ActorValueHolder,
        using runtime: inout ActiveEffectRuntime
    ) -> WornEnchantmentReport {
        reconcile(worn: [], on: holder, using: &runtime)
    }
}
