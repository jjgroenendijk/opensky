// Memoized per-skill perk-tree counts for the `World > Progression` panel
// (issue #556).
//
// The Skills section names, for each of the eighteen skills, how many boxes of
// that skill's AVIF tree the player owns out of how many the tree has. Building
// that line from the records means resolving every `PNAM` of all eighteen trees
// — roughly nine hundred `PerkStore.resolve` calls on a vanilla load order —
// and then asking the perk component about each resolved key. The panel refreshes
// twice a second, so without a cache that walk runs twice a second while the
// panel is open.
//
// ## The two things that stale an entry, and only those
//
// A tree's membership is a pure function of the AVIF record and the PERK records
// its `PNAM` links resolve to. Nothing at runtime rewrites those, so a resolved
// key list survives for as long as the stores behind it stand: `invalidate()` on
// a rewire is the only thing that can drop one.
//
// The owned count is a function of that key list and the player's own
// `PerkState`, which a spend, a grant, a revoke or a script's `AddPerk` all move.
// Rather than asking every mutation site to report in, the cache keeps the
// owned-perk list it last counted against and recounts when the list it is
// handed differs. That is one array comparison per ask against a list a few
// dozen entries long, in place of a walk of the whole tree.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// One session's per-skill perk-tree counts.
nonisolated struct PerkTreeCountCache {
    /// How much of one skill's tree the player owns.
    struct Counts: Equatable, Sendable {
        /// Boxes of the tree whose perk the player owns.
        let owned: Int
        /// Boxes the tree has a resolvable perk for, which is what `owned`
        /// counts out of.
        let total: Int

        /// What a skill with no AVIF record reads.
        static let none = Counts(owned: 0, total: 0)
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
    private(set) var treeCount = 0
    /// Counts taken since then, which is one per skill per ownership change.
    private(set) var countCount = 0
    /// Asks served from a standing count, which is the whole point of the cache
    /// and what the Skills section shows growing per tick.
    private(set) var reuseCount = 0

    /// How many skills the cache holds a resolved tree for.
    var skillCount: Int {
        keys.count
    }

    /// Whether nothing has been asked for since the last wiring.
    var isEmpty: Bool {
        keys.isEmpty
    }

    /// How much of `index`'s tree `owned` covers, resolving the tree through
    /// `tree` the first time that skill is asked about and recounting only when
    /// the owned list has moved since the last count.
    ///
    /// - Parameters:
    ///   - owned: the player's owned perks, which the counts are taken against.
    ///     Compared as given, so a caller must hand over the same ordering every
    ///     time — `PerkState.owned` is sorted and deduplicated, which is exactly
    ///     that.
    ///   - tree: what to do when the skill's tree has not been resolved yet.
    ///     Called at most once per skill per wiring, so a caller may do the full
    ///     record walk in it.
    mutating func counts(
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
    mutating func invalidate() {
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
    var readout: PerkTreeCacheReadout {
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
}

/// One reading of the perk-tree count cache.
nonisolated struct PerkTreeCacheReadout: Equatable, Sendable {
    let skillCount: Int
    let treeCount: Int
    let countCount: Int
    let reuseCount: Int

    /// Nothing asked for yet, which is also what a session with no game data
    /// reads.
    static let empty = PerkTreeCacheReadout(
        skillCount: 0, treeCount: 0, countCount: 0, reuseCount: 0
    )

    /// One line for a readout.
    var describedLine: String {
        "Perk tree cache: \(skillCount) skill(s), \(treeCount) tree(s) resolved, "
            + "\(countCount) counted, \(reuseCount) reused"
    }
}
