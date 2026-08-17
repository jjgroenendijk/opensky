// Worn enchantments (issue #472, roadmap item 19.9): a piece of armour, a robe, a
// ring or an amulet granting its effects for as long as it is worn.
//
// ## Reconciliation rather than an equip hook
//
// The engine equips from several places — the inventory menu, the Items panel, the
// NPC appearance path, a load — and hanging "apply the enchantment" off each of
// them would be one missed call away from an effect that never comes off. So this
// is written as a *reconcile*: given who is wearing what, make the stored constant
// effects match, and do nothing when they already do. Every equip path calls the
// same function afterwards, calling it twice changes nothing, and a loaded session
// calls it once per actor to pick up an item that was already worn.
//
// The recorded sequences are what makes removal exact. A helmet and a necklace can
// carry the same ENCH — vanilla robes and circlets do — so dispelling by source
// record would take off effects the other item granted. `EnchantedItemState`
// records the `ActiveEffect.sequence` numbers each item established, and
// unequipping dispels those and nothing else.
//
// ## What is applied
//
// The whole effect list, as a `constant` effect per entry, unscaled. No
// resistances: a worn item's enchantment is applied to its own wearer, and issue
// 19.8's resistance step is for a *hostile* magnitude arriving from outside. A
// detrimental constant effect on a worn item — vanilla has a few, on cursed rings
// — therefore lands at its authored magnitude, which is what the record says.
//
// Documented in docs/engine/magic.md.

import Foundation

/// What one reconciliation did.
nonisolated struct WornEnchantmentReport: Equatable, Sendable {
    /// Items whose effects were applied this time, ascending.
    let applied: [FormID]
    /// Items whose effects were taken back off, ascending.
    let removed: [FormID]
    /// Constant effects stored across every newly worn item.
    let storedCount: Int
    /// Effects dispelled across every item that came off.
    let dispelledCount: Int

    static let none = WornEnchantmentReport(
        applied: [], removed: [], storedCount: 0, dispelledCount: 0
    )

    /// Whether anything moved, which is what tells a caller to refresh a readout.
    var didChange: Bool {
        !applied.isEmpty || !removed.isEmpty
    }

    var describedLine: String {
        guard didChange else { return "Worn enchantments unchanged." }
        return "Worn enchantments: \(applied.count) item(s) on (\(storedCount) effect(s)), "
            + "\(removed.count) off (\(dispelledCount) effect(s))."
    }
}

@MainActor
enum WornEnchantmentApplication {
    /// Brings `holder`'s constant effects in line with what it is wearing.
    ///
    /// - Parameter worn: the resolved enchantment of every item `holder` has
    ///   equipped that carries one. An entry that is not a constant effect — a
    ///   drawn enchanted sword, a staff — is ignored here rather than filtered by
    ///   the caller, so no caller has to know the rule.
    @discardableResult
    static func reconcile(
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
    static func removeAll(
        on holder: ActorValueHolder,
        using runtime: inout ActiveEffectRuntime
    ) -> WornEnchantmentReport {
        reconcile(worn: [], on: holder, using: &runtime)
    }
}
