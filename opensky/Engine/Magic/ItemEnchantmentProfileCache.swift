// Memoized `ItemEnchantmentProfile.resolve` results, keyed by the item they were
// resolved from (issue #489).
//
// Two frame hooks ask for an equipped item's enchantment every frame — the melee
// hook through `wornHands()` for every equipped weapon, and the archery hook
// through `equippedBowProfile()` while the player is in control. Resolving one is
// an item-definition lookup, an ENCH lookup, a `EnchantmentStore.baseChain` walk
// for the worn-restriction link and a copy of the effect-entry array, and none of
// that changes while the records under it stand still.
//
// ## Why a rewire is the only thing that can stale an entry
//
// A profile is a pure function of the WEAP or ARMO record and the ENCH record its
// `EITM` resolves to. Neither is mutable at runtime: equipping, spending a charge
// and applying a worn effect all write world state, and world state is not read
// here. So an entry can only go wrong when the stores themselves are replaced,
// which is what `invalidate()` is for.
//
// ## Why a resolved "carries none" is cached too
//
// Most equipped items are not enchanted, and those are exactly the lookups the
// frame hooks repeat. An entry therefore holds `ItemEnchantmentProfile?`: a
// present entry with a nil value is the answer "this item carries no
// enchantment", not a miss to be resolved again.
//
// Documented in docs/engine/magic.md.

import Foundation

/// One session's resolved item enchantments.
nonisolated struct ItemEnchantmentProfileCache {
    /// The answer for each item asked about so far. A `.some(nil)` entry is a
    /// resolved "carries no enchantment"; see the file header.
    private var entries: [FormID: ItemEnchantmentProfile?] = [:]
    /// Items resolved from the records since the stores were last wired.
    private(set) var resolvedCount = 0
    /// Answers served from an existing entry since then, which is the whole
    /// point of the cache and what a readout shows growing per frame.
    private(set) var reuseCount = 0

    /// How many items the cache holds an answer for, enchanted or not.
    var count: Int {
        entries.count
    }

    /// Whether nothing has been asked for since the last wiring.
    var isEmpty: Bool {
        entries.isEmpty
    }

    /// `item`'s enchantment, resolving it through `resolve` the first time it is
    /// asked for and reusing that answer afterwards.
    ///
    /// - Parameter resolve: what to do on a miss. Called at most once per item
    ///   per wiring, so a caller may do the full record walk in it.
    mutating func profile(
        of item: FormID,
        resolve: (FormID) -> ItemEnchantmentProfile?
    ) -> ItemEnchantmentProfile? {
        if let cached = entries[item] {
            reuseCount += 1
            return cached
        }
        let profile = resolve(item)
        entries[item] = .some(profile)
        resolvedCount += 1
        return profile
    }

    /// Drops every entry, for when the stores the profiles were resolved from
    /// are replaced.
    ///
    /// The tallies reset with them: they count what this wiring has done, and
    /// carrying them across a rewire would describe entries that no longer
    /// exist.
    mutating func invalidate() {
        entries.removeAll(keepingCapacity: true)
        resolvedCount = 0
        reuseCount = 0
    }

    /// What the Equipment section shows, which is the reading that makes the
    /// reuse visible without a profiler.
    var readout: EnchantmentCacheReadout {
        EnchantmentCacheReadout(
            itemCount: count,
            resolvedCount: resolvedCount,
            reuseCount: reuseCount
        )
    }
}

/// One reading of the profile cache.
nonisolated struct EnchantmentCacheReadout: Equatable, Sendable {
    let itemCount: Int
    let resolvedCount: Int
    let reuseCount: Int

    /// Nothing asked for yet, which is also what a session with no game data
    /// reads.
    static let empty = EnchantmentCacheReadout(itemCount: 0, resolvedCount: 0, reuseCount: 0)

    /// One line for a readout.
    var describedLine: String {
        "Enchantment cache: \(itemCount) item(s), \(resolvedCount) resolved, "
            + "\(reuseCount) reused"
    }
}
