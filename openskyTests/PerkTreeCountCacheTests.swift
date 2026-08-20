// The memoized side of the Progression panel's skill lines (issue #556): a
// skill's tree is resolved out of the records once, the counts taken from it
// stand until the player's owned perks move, and a rewire drops the lot.
//
// The trees here are plain key lists rather than real AVIF records: what is
// under test is when the cache goes back to the records and what it counts, and
// a synthetic tree states both without a load order.

@testable import opensky
import Testing

struct PerkTreeCountCacheTests {
    private static let oneHanded: Int32 = 6
    private static let destruction: Int32 = 21

    /// One perk key, addressed the way a resolved `PNAM` link is.
    private static func key(_ objectID: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID))
    }

    /// Counts how often the cache had to walk a tree out of the records, which
    /// is the whole claim: once per skill, however many ticks ask.
    private struct Trees {
        let bySkill: [Int32: [ReferenceKey]]
        private(set) var walks = 0

        mutating func counts(
            forSkill index: Int32,
            owned: [ReferenceKey],
            in cache: inout PerkTreeCountCache
        ) -> PerkTreeCountCache.Counts {
            cache.counts(forSkill: index, owned: owned) { index in
                walks += 1
                return bySkill[index] ?? []
            }
        }
    }

    private static func trees() -> Trees {
        Trees(bySkill: [
            oneHanded: [key(1), key(2), key(3)],
            destruction: [key(4), key(5)]
        ])
    }

    @Test
    func aSkillIsWalkedOnceAndCountedOnce() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()
        let owned = [Self.key(1), Self.key(4)]

        let first = trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
        #expect(first == PerkTreeCountCache.Counts(owned: 1, total: 3))
        for _ in 0 ..< 9 {
            #expect(trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache) == first)
        }

        #expect(trees.walks == 1)
        #expect(cache.treeCount == 1)
        #expect(cache.countCount == 1)
        #expect(cache.reuseCount == 9)
        #expect(cache.skillCount == 1)
    }

    /// Each skill is its own entry, and asking about a second one does not
    /// disturb the first.
    @Test
    func eachSkillKeepsItsOwnCount() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()
        let owned = [Self.key(1), Self.key(4), Self.key(5)]

        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
                == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )
        #expect(
            trees.counts(forSkill: Self.destruction, owned: owned, in: &cache)
                == PerkTreeCountCache.Counts(owned: 2, total: 2)
        )
        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
                == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )

        #expect(trees.walks == 2)
        #expect(cache.countCount == 2)
        #expect(cache.reuseCount == 1)
    }

    /// A skill this load order carries no tree for is an entry too: an empty
    /// answer must not send the panel back to the records twice a second.
    @Test
    func aSkillWithNoTreeIsCachedAsEmpty() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()

        #expect(trees.counts(forSkill: 99, owned: [], in: &cache) == .none)
        #expect(trees.counts(forSkill: 99, owned: [], in: &cache) == .none)

        #expect(trees.walks == 1)
        #expect(cache.reuseCount == 1)
    }

    /// A gained perk moves the counts on the next ask, without walking the tree
    /// again — the keys stand, only what the player owns changed.
    @Test
    func gainingAPerkRecountsWithoutRewalking() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()

        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: [Self.key(1)], in: &cache)
                == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )
        #expect(
            trees.counts(
                forSkill: Self.oneHanded, owned: [Self.key(1), Self.key(2)], in: &cache
            ) == PerkTreeCountCache.Counts(owned: 2, total: 3)
        )

        #expect(trees.walks == 1)
        #expect(cache.countCount == 2)
        #expect(cache.reuseCount == 0)
    }

    /// A removed perk is a change in the same way a gained one is: the counts
    /// must fall rather than stand on the list they were taken against.
    @Test
    func losingAPerkRecountsToo() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()
        let owned = [Self.key(1), Self.key(2)]

        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
                == PerkTreeCountCache.Counts(owned: 2, total: 3)
        )
        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: [Self.key(2)], in: &cache)
                == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )
    }

    /// A change to a perk outside this skill's tree still recounts, because the
    /// cache compares the owned list rather than reasoning about which tree the
    /// changed perk sits in.
    @Test
    func aChangeElsewhereRecountsEverySkill() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()

        #expect(
            trees.counts(forSkill: Self.oneHanded, owned: [Self.key(1)], in: &cache)
                == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )
        #expect(
            trees.counts(
                forSkill: Self.oneHanded, owned: [Self.key(1), Self.key(4)], in: &cache
            ) == PerkTreeCountCache.Counts(owned: 1, total: 3)
        )

        #expect(cache.countCount == 2)
    }

    /// Rewiring the stores drops every entry and every tally: the counts under
    /// them were taken from records that are no longer there.
    @Test
    func aRewireDropsEverything() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()
        let owned = [Self.key(1)]

        _ = trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
        _ = trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
        #expect(!cache.isEmpty)

        cache.invalidate()
        #expect(cache.isEmpty)
        #expect(cache.readout == .empty)

        _ = trees.counts(forSkill: Self.oneHanded, owned: owned, in: &cache)
        #expect(trees.walks == 2)
        #expect(cache.readout.treeCount == 1)
        #expect(cache.readout.countCount == 1)
        #expect(cache.readout.reuseCount == 0)
    }

    /// The line the Skills section closes with, which is how the reuse is read
    /// from the panel rather than from a profiler.
    @Test
    func theReadoutSpellsOutWhatTheCacheDid() {
        var trees = Self.trees()
        var cache = PerkTreeCountCache()

        _ = trees.counts(forSkill: Self.oneHanded, owned: [], in: &cache)
        _ = trees.counts(forSkill: Self.destruction, owned: [], in: &cache)
        _ = trees.counts(forSkill: Self.oneHanded, owned: [], in: &cache)

        #expect(
            cache.readout.describedLine
                == "Perk tree cache: 2 skill(s), 2 tree(s) resolved, 2 counted, 1 reused"
        )
    }
}
