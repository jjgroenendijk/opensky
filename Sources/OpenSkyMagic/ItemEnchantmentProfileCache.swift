// Memoized `ItemEnchantmentProfile.resolve` results, keyed by item. The combat
// frame hooks ask for every equipped weapon's enchantment each frame. A profile
// depends only on records that do not change at runtime, so only replaced
// stores stale an entry (`invalidate()`). A nil value is cached too: it means
// "carries none". See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// One session's resolved item enchantments.
nonisolated public struct ItemEnchantmentProfileCache: Sendable {
    /// The answer for each item asked about so far. A `.some(nil)` entry is a
    /// resolved "carries no enchantment"; see the file header.
    private var entries: [FormID: ItemEnchantmentProfile?] = [:]
    /// Items resolved from the records since the stores were last wired.
    public private(set) var resolvedCount = 0
    /// Answers served from an existing entry since then, which is the whole
    /// point of the cache and what a readout shows growing per frame.
    public private(set) var reuseCount = 0

    /// How many items the cache holds an answer for, enchanted or not.
    public var count: Int {
        entries.count
    }

    /// Whether nothing has been asked for since the last wiring.
    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// `item`'s enchantment, resolving it through `resolve` the first time it is
    /// asked for and reusing that answer afterwards.
    ///
    /// - Parameter resolve: what to do on a miss. Called at most once per item
    ///   per wiring, so a caller may do the full record walk in it.
    public mutating func profile(
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
    public mutating func invalidate() {
        entries.removeAll(keepingCapacity: true)
        resolvedCount = 0
        reuseCount = 0
    }

    /// What the Equipment section shows, which is the reading that makes the
    /// reuse visible without a profiler.
    public var readout: EnchantmentCacheReadout {
        EnchantmentCacheReadout(
            itemCount: count,
            resolvedCount: resolvedCount,
            reuseCount: reuseCount
        )
    }

    public init(
        entries: [FormID: ItemEnchantmentProfile?] = [:],
        resolvedCount: Int = 0,
        reuseCount: Int = 0
    ) {
        self.entries = entries
        self.resolvedCount = resolvedCount
        self.reuseCount = reuseCount
    }
}
