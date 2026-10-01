// Memoized per-skill perk-tree counts for the `World > Progression` panel, which
// refreshes twice a second; one walk is about 900 `PerkStore.resolve` calls.
// A tree's key list changes only on a rewire (`invalidate()`). The owned count is
// recounted when the owned list differs from the last one, which costs one short
// array compare. See docs/engine/character-leveling.md.

import Foundation
import OpenSkyFormatsESM

/// One session's per-skill perk-tree counts.
nonisolated public struct PerkTreeCountCache: Sendable {
    /// How much of one skill's tree the player owns.
    public struct Counts: Equatable, Sendable {
        /// Boxes of the tree whose perk the player owns.
        public let owned: Int
        /// Boxes the tree has a resolvable perk for, which is what `owned`
        /// counts out of.
        public let total: Int

        /// What a skill with no AVIF record reads.
        public static let none = Counts(owned: 0, total: 0)
    }

    /// Every resolvable perk of one skill's tree, in node order, for each skill
    /// asked about since the last wiring.
    private var keys: [Int32: [ReferenceKey]] = [:]
    /// The counts standing for the owned-perk list in `ownedWhenCounted`.
    private var counts: [Int32: Counts] = [:]
    /// The player's owned perks as of the last count, which is what a later ask
    /// is compared against to decide whether the counts still hold.
    private var ownedWhenCounted: [ReferenceKey] = []
    /// The same list as a set, so counting a tree is one hash lookup per box
    /// rather than a scan of the owned array per box.
    private var ownedLookup: Set<ReferenceKey> = []

    /// Trees walked out of the records since the stores were last wired.
    public private(set) var treeCount = 0
    /// Counts taken since then, which is one per skill per ownership change.
    public private(set) var countCount = 0
    /// Asks served from a standing count, which is the whole point of the cache
    /// and what the Skills section shows growing per tick.
    public private(set) var reuseCount = 0

    /// How many skills the cache holds a resolved tree for.
    public var skillCount: Int {
        keys.count
    }

    /// Whether nothing has been asked for since the last wiring.
    public var isEmpty: Bool {
        keys.isEmpty
    }

    /// How much of `index`'s tree `owned` covers. `tree` runs at most once per skill
    /// per wiring. `owned` is compared as given, so pass `PerkState.owned` (sorted).
    public mutating func counts(
        forSkill index: Int32,
        owned: [ReferenceKey],
        tree: (Int32) -> [ReferenceKey]
    ) -> Counts {
        if owned != ownedWhenCounted {
            ownedWhenCounted = owned
            ownedLookup = Set(owned)
            counts.removeAll(keepingCapacity: true)
        }
        if let standing = counts[index] {
            reuseCount += 1
            return standing
        }
        let perks = resolvedTree(forSkill: index, tree: tree)
        let taken = Counts(
            owned: perks.count { ownedLookup.contains($0) },
            total: perks.count
        )
        counts[index] = taken
        countCount += 1
        return taken
    }

    /// Drops every entry, for when the stores the trees were resolved from are
    /// replaced.
    ///
    /// The tallies reset with them: they count what this wiring has done, and
    /// carrying them across a rewire would describe entries that no longer
    /// exist.
    public mutating func invalidate() {
        keys.removeAll(keepingCapacity: true)
        counts.removeAll(keepingCapacity: true)
        ownedWhenCounted = []
        ownedLookup = []
        treeCount = 0
        countCount = 0
        reuseCount = 0
    }

    /// What the Skills section shows, which is the reading that makes the reuse
    /// visible without a profiler.
    public var readout: PerkTreeCacheReadout {
        PerkTreeCacheReadout(
            skillCount: skillCount,
            treeCount: treeCount,
            countCount: countCount,
            reuseCount: reuseCount
        )
    }

    private mutating func resolvedTree(
        forSkill index: Int32,
        tree: (Int32) -> [ReferenceKey]
    ) -> [ReferenceKey] {
        if let standing = keys[index] {
            return standing
        }
        let resolved = tree(index)
        keys[index] = resolved
        treeCount += 1
        return resolved
    }

    public init(
        keys: [Int32: [ReferenceKey]] = [:],
        counts: [Int32: Counts] = [:],
        ownedWhenCounted: [ReferenceKey] = [],
        ownedLookup: Set<ReferenceKey> = [],
        treeCount: Int = 0,
        countCount: Int = 0,
        reuseCount: Int = 0
    ) {
        self.keys = keys
        self.counts = counts
        self.ownedWhenCounted = ownedWhenCounted
        self.ownedLookup = ownedLookup
        self.treeCount = treeCount
        self.countCount = countCount
        self.reuseCount = reuseCount
    }
}

/// One reading of the perk-tree count cache.
nonisolated public struct PerkTreeCacheReadout: Equatable, Sendable {
    public let skillCount: Int
    public let treeCount: Int
    public let countCount: Int
    public let reuseCount: Int

    /// Nothing asked for yet, which is also what a session with no game data
    /// reads.
    public static let empty = PerkTreeCacheReadout(
        skillCount: 0, treeCount: 0, countCount: 0, reuseCount: 0
    )

    /// One line for a readout.
    public var describedLine: String {
        "Perk tree cache: \(skillCount) skill(s), \(treeCount) tree(s) resolved, "
            + "\(countCount) counted, \(reuseCount) reused"
    }
}
